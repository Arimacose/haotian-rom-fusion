#!/usr/bin/env python3
"""Extract and compare official, LineageOS, and EvolutionX kernels."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


LINUX_BANNER = re.compile(rb"Linux version [^\x00\r\n]{1,512}")


def sha256(path: Path, block_size: int = 8 * 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(block_size), b""):
            digest.update(block)
    return digest.hexdigest()


def banner(path: Path) -> str | None:
    match = LINUX_BANNER.search(path.read_bytes())
    if not match:
        return None
    return match.group(0).decode("utf-8", errors="replace")


def find_official_boot(extract_root: Path) -> Path | None:
    matches = sorted(extract_root.glob("extracted/**/images/boot.img"))
    return matches[0] if matches else None


def unpack_boot(
    boot_image: Path, unpack_tool: Path, output_directory: Path
) -> tuple[Path, str]:
    resolved_output = output_directory.resolve()
    resolved_parent = output_directory.parent.resolve()
    if resolved_output.parent != resolved_parent:
        raise ValueError(f"Unexpected unpack target: {resolved_output}")
    if output_directory.exists():
        shutil.rmtree(output_directory)
    output_directory.mkdir(parents=True)
    completed = subprocess.run(
        [
            sys.executable,
            str(unpack_tool),
            "--boot_img",
            str(boot_image),
            "--out",
            str(output_directory),
        ],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    kernel = output_directory / "kernel"
    if not kernel.is_file():
        raise FileNotFoundError(f"No kernel extracted from {boot_image}")
    return kernel, completed.stdout


def describe(name: str, path: Path) -> dict[str, Any]:
    return {
        "name": name,
        "path": str(path),
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
        "linux_banner": banner(path),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument(
        "--output-root",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "evidence",
    )
    parser.add_argument("--allow-missing-official", action="store_true")
    args = parser.parse_args()

    config = json.loads(args.config.read_text(encoding="utf-8-sig"))
    output_root = args.output_root.resolve()
    temporary_root = output_root / "kernel-unpack"
    output_root.mkdir(parents=True, exist_ok=True)

    official_boot = find_official_boot(Path(config["official_3_0_304"]["extract_root"]))
    if official_boot is None and not args.allow_missing_official:
        raise FileNotFoundError("Official 3.0.304 boot.img has not been extracted")

    kernels: list[dict[str, Any]] = []
    unpack_notes: dict[str, str] = {}
    if official_boot is not None:
        official_kernel, unpack_output = unpack_boot(
            official_boot,
            Path(config["tools"]["unpack_bootimg"]),
            temporary_root / "official-3.0.304",
        )
        kernels.append(describe("official-3.0.304", official_kernel))
        unpack_notes["official-3.0.304"] = unpack_output

    evolution_kernel = Path(config["evolutionx"]["kernel"])
    lineage_kernel = Path(config["lineageos"]["kernel"])
    for name, path in (
        ("evolutionx-0603", evolution_kernel),
        ("lineageos-0704", lineage_kernel),
    ):
        if not path.is_file():
            raise FileNotFoundError(path)
        kernels.append(describe(name, path))

    groups: dict[str, list[str]] = {}
    for item in kernels:
        groups.setdefault(item["sha256"], []).append(item["name"])

    result = {
        "schema_version": "1.0",
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "device": "haotian",
        "official_pending": official_boot is None,
        "kernels": kernels,
        "identical_sha256_groups": [
            {"sha256": digest, "members": members}
            for digest, members in groups.items()
        ],
        "unpack_notes": unpack_notes,
    }

    json_path = output_root / "kernel-three-way-comparison.json"
    markdown_path = output_root / "kernel-three-way-comparison.md"
    json_path.write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    lines = [
        "# haotian kernel comparison",
        "",
        f"Generated: `{result['generated_at']}`",
        "",
        "| Baseline | Bytes | SHA-256 | Linux banner |",
        "|---|---:|---|---|",
    ]
    for item in kernels:
        lines.append(
            f"| {item['name']} | {item['bytes']} | `{item['sha256']}` | "
            f"`{item['linux_banner'] or 'not located'}` |"
        )
    lines.extend(
        [
            "",
            "## Identical groups",
            "",
        ]
    )
    for digest, members in groups.items():
        lines.append(f"- `{digest}`: {', '.join(members)}")
    if official_boot is None:
        lines.extend(
            [
                "",
                "Official 3.0.304 boot extraction is pending; rerun after Phase 1.",
            ]
        )
    markdown_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
