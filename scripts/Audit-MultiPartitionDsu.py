#!/usr/bin/env python3
"""Independently audit a multi-partition DSU ZIP and its build manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, BinaryIO


CHUNK_SIZE = 16 * 1024 * 1024


def digest_stream(stream: BinaryIO) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    for chunk in iter(lambda: stream.read(CHUNK_SIZE), b""):
        digest.update(chunk)
        size += len(chunk)
    return digest.hexdigest(), size


def digest_file(path: Path) -> str:
    with path.open("rb") as stream:
        return digest_stream(stream)[0]


def run(command: list[str]) -> str:
    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if result.returncode:
        raise RuntimeError(
            f"command failed ({result.returncode}): {subprocess.list2cmdline(command)}\n"
            f"{result.stdout}"
        )
    return result.stdout


def parse_avb(text: str) -> dict[str, Any]:
    def capture(pattern: str) -> str:
        match = re.search(pattern, text, re.MULTILINE)
        if not match:
            raise ValueError(f"missing AVB field matching {pattern!r}")
        return match.group(1).strip()

    properties = {
        key.strip(): value
        for key, value in re.findall(
            r"^\s*Prop:\s+(.+?)\s+->\s+'(.*)'\s*$", text, re.MULTILINE
        )
    }
    return {
        "image_size": int(capture(r"^Image size:\s+(\d+) bytes$")),
        "original_image_size": int(capture(r"^Original image size:\s+(\d+) bytes$")),
        "algorithm": capture(r"^Algorithm:\s+(\S+)$"),
        "partition_name": capture(r"^\s+Partition Name:\s+(\S+)$"),
        "hash_algorithm": capture(r"^\s+Hash Algorithm:\s+(\S+)$"),
        "salt": capture(r"^\s+Salt:\s+([0-9a-fA-F]+)$").lower(),
        "root_digest": capture(r"^\s+Root Digest:\s+([0-9a-fA-F]+)$").lower(),
        "tree_size": int(capture(r"^\s+Tree Size:\s+(\d+)(?: bytes)?$")),
        "fec_size": int(capture(r"^\s+FEC size:\s+(\d+) bytes$")),
        "properties": properties,
    }


def inspect_avb(avbtool: Path, image: Path) -> tuple[dict[str, Any], str]:
    verification = run([str(avbtool), "verify_image", "--image", str(image)])
    information = run([str(avbtool), "info_image", "--image", str(image)])
    return parse_avb(information), verification


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--sidecar", required=True, type=Path)
    parser.add_argument("--avbtool", required=True, type=Path)
    parser.add_argument("--work-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    expected_package = manifest["package"]
    package_hash = digest_file(args.package)
    if args.package.stat().st_size != expected_package["size"]:
        raise ValueError("package size differs from manifest")
    if package_hash != expected_package["sha256"]:
        raise ValueError("package SHA-256 differs from manifest")
    sidecar_parts = args.sidecar.read_text(encoding="ascii").split()
    if not sidecar_parts or sidecar_parts[0].lower() != package_hash:
        raise ValueError("package SHA-256 sidecar differs")

    expected_members = expected_package["members"]
    expected_names = [item["name"] for item in expected_members]
    partition_by_name = {item["name"]: item for item in manifest["partitions"]}
    args.work_dir.mkdir(parents=True, exist_ok=True)
    temp_root = Path(tempfile.mkdtemp(prefix="dsu-audit-", dir=args.work_dir))
    results: list[dict[str, Any]] = []
    try:
        with zipfile.ZipFile(args.package, "r") as archive:
            infos = archive.infolist()
            actual_names = [info.filename for info in infos]
            if actual_names != expected_names:
                raise ValueError(f"ZIP members differ: {actual_names}")
            if len(actual_names) != len(set(actual_names)):
                raise ValueError("duplicate ZIP member names")

            for expected, info in zip(expected_members, infos, strict=True):
                name = info.filename.removesuffix(".img")
                spec = partition_by_name[name]
                extracted = temp_root / info.filename
                digest = hashlib.sha256()
                extracted_size = 0
                with archive.open(info, "r") as source, extracted.open("wb") as target:
                    for chunk in iter(lambda: source.read(CHUNK_SIZE), b""):
                        target.write(chunk)
                        digest.update(chunk)
                        extracted_size += len(chunk)
                member_hash = digest.hexdigest()
                if extracted_size != expected["uncompressed_size"] or extracted_size != info.file_size:
                    raise ValueError(f"{info.filename}: uncompressed size differs")
                if info.compress_size != expected["compressed_size"]:
                    raise ValueError(f"{info.filename}: compressed size differs")
                if f"{info.CRC:08x}" != expected["crc32"]:
                    raise ValueError(f"{info.filename}: CRC differs")
                if member_hash != expected["sha256"] or member_hash != spec["staged_sha256"]:
                    raise ValueError(f"{info.filename}: decompressed SHA-256 differs")
                with extracted.open("rb") as stream:
                    if stream.read(4) == bytes.fromhex("3aff26ed"):
                        raise ValueError(f"{info.filename}: sparse Android image")
                    stream.seek(1080)
                    if stream.read(2) != bytes.fromhex("53ef"):
                        raise ValueError(f"{info.filename}: ext4 magic missing")

                filesystem_output = run(["e2fsck", "-fn", str(extracted)])
                staged_avb, avb_verification = inspect_avb(args.avbtool, extracted)
                expected_avb = spec["footer_rebuild"]["avb"]
                fields = (
                    "image_size",
                    "original_image_size",
                    "algorithm",
                    "partition_name",
                    "hash_algorithm",
                    "salt",
                    "root_digest",
                    "tree_size",
                    "fec_size",
                    "properties",
                )
                differences = {
                    field: {"expected": expected_avb[field], "actual": staged_avb[field]}
                    for field in fields
                    if expected_avb[field] != staged_avb[field]
                }
                if differences:
                    raise ValueError(f"{info.filename}: AVB metadata differs: {differences}")
                if staged_avb["partition_name"] != name or staged_avb["algorithm"] != "NONE":
                    raise ValueError(f"{info.filename}: DSU AVB identity differs")
                if staged_avb["fec_size"] != 0:
                    raise ValueError(f"{info.filename}: DSU footer unexpectedly carries FEC")

                source_path = Path(spec["source"])
                if source_path.stat().st_size != spec["source_size"]:
                    raise ValueError(f"{info.filename}: source size changed after package build")
                if digest_file(source_path) != spec["source_sha256"]:
                    raise ValueError(f"{info.filename}: source hash changed after package build")
                source_avb, _ = inspect_avb(args.avbtool, source_path)
                if source_avb["root_digest"] != staged_avb["root_digest"]:
                    raise ValueError(f"{info.filename}: filesystem root digest differs from source")

                results.append(
                    {
                        "name": info.filename,
                        "zip_timestamp": list(info.date_time),
                        "uncompressed_size": extracted_size,
                        "compressed_size": info.compress_size,
                        "crc32": f"{info.CRC:08x}",
                        "sha256": member_hash,
                        "filesystem": "raw ext4",
                        "e2fsck_read_only": "passed",
                        "avb_verify": "passed",
                        "avb": staged_avb,
                        "source_root_digest_unchanged": True,
                        "avb_verification_output": avb_verification.strip().splitlines(),
                        "filesystem_check_tail": filesystem_output.strip().splitlines()[-5:],
                    }
                )
                extracted.unlink()
    finally:
        shutil.rmtree(temp_root, ignore_errors=True)

    report = {
        "schema": 1,
        "result": "passed",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "runtime_validation": "not_started",
        "package": {
            "path": str(args.package),
            "size": args.package.stat().st_size,
            "sha256": package_hash,
            "sidecar_matches": True,
            "exact_member_order": expected_names,
            "duplicate_members": False,
        },
        "checks": {
            "zip_crc_and_stream_hashes": "passed",
            "raw_ext4": "passed",
            "e2fsck_read_only": "passed",
            "avb_hashtrees": "passed",
            "avb_manifest_equivalence": "passed",
            "source_image_hashes": "passed",
            "source_root_digests_unchanged": "passed",
        },
        "members": results,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(report["package"], indent=2))
    print(f"audit={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
