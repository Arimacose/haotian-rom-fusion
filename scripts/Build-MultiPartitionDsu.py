#!/usr/bin/env python3
"""Build and verify a deterministic multi-partition Android DSU ZIP.

The builder keeps the source filesystem payload byte-for-byte unchanged.  It
can rebuild each AVB hashtree footer with a host-compatible SPL property while
recording both the source and staged hashes in a sidecar manifest.  Only image
files are stored in the DSU ZIP; reports and hashes stay beside the artifact.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


CHUNK_SIZE = 16 * 1024 * 1024
SPARSE_MAGIC = bytes.fromhex("3aff26ed")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(CHUNK_SIZE), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run_checked(command: list[str]) -> str:
    result = subprocess.run(
        command,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode:
        rendered = subprocess.list2cmdline(command)
        raise RuntimeError(f"Command failed ({result.returncode}): {rendered}\n{result.stdout}")
    return result.stdout


def avb_command(avbtool: Path, *arguments: str) -> list[str]:
    if avbtool.suffix.lower() == ".py":
        return [sys.executable, str(avbtool), *arguments]
    return [str(avbtool), *arguments]


def parse_avb_info(text: str) -> dict[str, Any]:
    def capture(pattern: str, required: bool = True) -> str | None:
        match = re.search(pattern, text, flags=re.MULTILINE)
        if match:
            return match.group(1).strip()
        if required:
            raise ValueError(f"Missing AVB field matching {pattern!r}")
        return None

    properties: dict[str, str] = {}
    for key, value in re.findall(r"^\s*Prop:\s+(.+?)\s+->\s+'(.*)'\s*$", text, flags=re.MULTILINE):
        properties[key.strip()] = value

    return {
        "image_size": int(capture(r"^Image size:\s+(\d+) bytes$")),
        "original_image_size": int(capture(r"^Original image size:\s+(\d+) bytes$")),
        "algorithm": capture(r"^Algorithm:\s+(\S+)$"),
        "partition_name": capture(r"^\s+Partition Name:\s+(\S+)$"),
        "hash_algorithm": capture(r"^\s+Hash Algorithm:\s+(\S+)$"),
        "salt": capture(r"^\s+Salt:\s+([0-9a-fA-F]+)$"),
        "root_digest": capture(r"^\s+Root Digest:\s+([0-9a-fA-F]+)$"),
        "tree_size": int(capture(r"^\s+Tree Size:\s+(\d+)(?: bytes)?$")),
        "fec_size": int(capture(r"^\s+FEC size:\s+(\d+) bytes$")),
        "properties": properties,
    }


def inspect_avb(avbtool: Path, image: Path) -> dict[str, Any]:
    output = run_checked(avb_command(avbtool, "info_image", "--image", str(image)))
    return parse_avb_info(output)


def validate_raw_ext4(image: Path) -> dict[str, Any]:
    with image.open("rb") as stream:
        first = stream.read(4)
        stream.seek(1080)
        ext4_magic = stream.read(2)
    if first == SPARSE_MAGIC:
        raise ValueError(f"{image} is Android sparse; DSU profile requires a raw image")
    if ext4_magic != bytes.fromhex("53ef"):
        raise ValueError(f"{image} does not expose the expected ext4 superblock magic")
    return {"android_sparse": False, "filesystem": "ext4", "ext4_magic_offset": 1080}


def rebuild_footer(
    avbtool: Path,
    image: Path,
    source_info: dict[str, Any],
    spl_property: str | None,
    target_spl: str | None,
) -> dict[str, Any]:
    properties = dict(source_info["properties"])
    source_spl: str | None = None
    if spl_property is not None:
        if spl_property not in properties:
            raise ValueError(f"{image.name} is missing {spl_property}")
        if target_spl is None:
            raise ValueError(f"{image.name}: target SPL is required with {spl_property}")
        source_spl = properties[spl_property]
        properties[spl_property] = target_spl

    run_checked(avb_command(avbtool, "erase_footer", "--image", str(image)))

    command = avb_command(
        avbtool,
        "add_hashtree_footer",
        "--image",
        str(image),
        "--partition_name",
        source_info["partition_name"],
        "--partition_size",
        str(source_info["image_size"]),
        "--hash_algorithm",
        source_info["hash_algorithm"],
        "--salt",
        source_info["salt"],
        "--algorithm",
        "NONE",
        "--do_not_generate_fec",
    )
    for key, value in properties.items():
        command.extend(["--prop", f"{key}:{value}"])
    run_checked(command)
    verification = run_checked(avb_command(avbtool, "verify_image", "--image", str(image)))
    staged_info = inspect_avb(avbtool, image)

    if staged_info["root_digest"] != source_info["root_digest"]:
        raise ValueError(
            f"{image.name}: filesystem root digest changed: "
            f"{source_info['root_digest']} -> {staged_info['root_digest']}"
        )
    if staged_info["image_size"] != source_info["image_size"]:
        raise ValueError(f"{image.name}: partition size changed")
    if spl_property is not None and staged_info["properties"].get(spl_property) != target_spl:
        raise ValueError(f"{image.name}: staged SPL property was not updated")

    return {
        "spl_override_applied": spl_property is not None and source_spl != target_spl,
        "security_patch_property": spl_property,
        "source_security_patch": source_spl,
        "staged_security_patch": target_spl if spl_property is not None else None,
        "filesystem_root_digest_unchanged": True,
        "source_fec_size": source_info["fec_size"],
        "staged_fec_size": staged_info["fec_size"],
        "verification_output": verification.strip().splitlines(),
        "avb": staged_info,
    }


def add_file_deterministically(
    archive: zipfile.ZipFile,
    source: Path,
    member_name: str,
    timestamp: tuple[int, int, int, int, int, int],
) -> None:
    info = zipfile.ZipInfo(member_name, date_time=timestamp)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.create_system = 3
    info.external_attr = 0o100644 << 16
    info.flag_bits |= 0x800
    with source.open("rb") as input_stream, archive.open(info, "w", force_zip64=True) as output_stream:
        shutil.copyfileobj(input_stream, output_stream, length=CHUNK_SIZE)


def verify_zip(package: Path, staged: dict[str, Path]) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    expected_names = [f"{name}.img" for name in staged]
    with zipfile.ZipFile(package, "r") as archive:
        actual_names = archive.namelist()
        if actual_names != expected_names:
            raise ValueError(f"ZIP members differ: expected {expected_names}, got {actual_names}")
        bad_member = archive.testzip()
        if bad_member is not None:
            raise ValueError(f"ZIP CRC failed for {bad_member}")
        for name, path in staged.items():
            member_name = f"{name}.img"
            digest = hashlib.sha256()
            with archive.open(member_name, "r") as stream:
                for chunk in iter(lambda: stream.read(CHUNK_SIZE), b""):
                    digest.update(chunk)
            entry = archive.getinfo(member_name)
            staged_hash = sha256_file(path)
            if digest.hexdigest() != staged_hash:
                raise ValueError(f"ZIP content hash differs for {member_name}")
            results.append(
                {
                    "name": member_name,
                    "uncompressed_size": entry.file_size,
                    "compressed_size": entry.compress_size,
                    "crc32": f"{entry.CRC:08x}",
                    "sha256": staged_hash,
                }
            )
    return results


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--avbtool", required=True, type=Path)
    parser.add_argument("--clean", action="store_true", help="replace an existing profile output")
    parser.add_argument("--keep-staging", action="store_true", help="retain staged IMG files after ZIP validation")
    return parser.parse_args()


def main() -> int:
    args = parse_arguments()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    args.output_dir.mkdir(parents=True, exist_ok=True)
    profile_dir = args.output_dir / config["profile"]
    if profile_dir.exists():
        if not args.clean:
            raise FileExistsError(f"Output exists; use --clean: {profile_dir}")
        shutil.rmtree(profile_dir)
    profile_dir.mkdir(parents=True)

    if not args.avbtool.is_file():
        raise FileNotFoundError(args.avbtool)
    avbtool_hash = sha256_file(args.avbtool)
    source_root = Path(config["source_root"])
    partition_specs = config["partitions"]
    source_total = sum(int(item["expected_size"]) for item in partition_specs)
    free_space = shutil.disk_usage(args.output_dir).free
    required_peak = source_total * 2 + 2 * 1024**3
    if free_space < required_peak:
        raise OSError(
            f"Free space {free_space} is below estimated peak {required_peak} bytes"
        )

    staging_dir = profile_dir / "staging"
    staging_dir.mkdir()
    staged_paths: dict[str, Path] = {}
    partition_results: list[dict[str, Any]] = []

    for spec in partition_specs:
        name = spec["name"]
        source = source_root / spec["source"]
        if not source.is_file():
            raise FileNotFoundError(source)
        source_size = source.stat().st_size
        source_hash = sha256_file(source)
        if source_size != int(spec["expected_size"]):
            raise ValueError(f"{name}: source size differs")
        if source_hash != spec["expected_sha256"].lower():
            raise ValueError(f"{name}: source SHA-256 differs")

        filesystem = validate_raw_ext4(source)
        source_avb = inspect_avb(args.avbtool, source)
        if source_avb["partition_name"] != name:
            raise ValueError(f"{name}: AVB partition name is {source_avb['partition_name']}")

        staged = staging_dir / f"{name}.img"
        shutil.copyfile(source, staged)
        footer_result = rebuild_footer(
            args.avbtool,
            staged,
            source_avb,
            spec.get("security_patch_property"),
            spec.get("target_security_patch", config.get("host_security_patch")),
        )
        staged_paths[name] = staged
        partition_results.append(
            {
                "name": name,
                "source": str(source),
                "source_size": source_size,
                "source_sha256": source_hash,
                "staged_size": staged.stat().st_size,
                "staged_sha256": sha256_file(staged),
                "filesystem": filesystem,
                "source_avb": source_avb,
                "footer_rebuild": footer_result,
            }
        )
        print(f"prepared {name}: {staged.stat().st_size} bytes", flush=True)

    zip_timestamp = tuple(config["zip_timestamp"])
    package = profile_dir / config["package_name"]
    with zipfile.ZipFile(
        package,
        mode="w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=int(config.get("zip_compresslevel", 6)),
        allowZip64=True,
    ) as archive:
        for name, staged in staged_paths.items():
            print(f"compressing {name}.img", flush=True)
            add_file_deterministically(archive, staged, f"{name}.img", zip_timestamp)

    print("verifying ZIP CRC and decompressed member hashes", flush=True)
    zip_members = verify_zip(package, staged_paths)
    package_hash = sha256_file(package)
    manifest = {
        "schema": 1,
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "profile": config["profile"],
        "purpose": config["purpose"],
        "source_ota": config["source_ota"],
        "host_baseline": config["host_baseline"],
        "host_security_patch": config["host_security_patch"],
        "spl_override_scope": "AVB property descriptor only; ext4 payload root digests are unchanged",
        "package": {
            "path": str(package),
            "size": package.stat().st_size,
            "sha256": package_hash,
            "members": zip_members,
        },
        "partitions": partition_results,
        "omitted_partitions": config["omitted_partitions"],
        "tools": {
            "python": sys.version,
            "avbtool": str(args.avbtool),
            "avbtool_sha256": avbtool_hash,
        },
        "runtime_validation": "not_started",
    }
    manifest_path = profile_dir / f"{package.name}.manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    hash_path = profile_dir / f"{package.name}.sha256"
    hash_path.write_text(f"{package_hash}  {package.name}\n", encoding="ascii")

    if not args.keep_staging:
        shutil.rmtree(staging_dir)

    print(json.dumps(manifest["package"], indent=2), flush=True)
    print(f"manifest: {manifest_path}", flush=True)
    print(f"sha256:   {hash_path}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
