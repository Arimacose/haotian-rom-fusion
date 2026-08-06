#!/usr/bin/env python3
"""Hash the read-only extracted official dynamic-partition filesystems."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any


CHUNK_SIZE = 8 * 1024 * 1024
CATEGORY_PATTERNS = {
    "camera": ("camera", "camx", "mialgo"),
    "display": ("display", "brightness", "hdr", "panel"),
    "fingerprint": ("fingerprint", "goodix", "udfps"),
    "haptics": ("haptic", "vibrat", "cs40"),
    "touch": ("touch",),
}


def configured_path(value: str) -> Path:
    """Resolve a configured Windows path on Windows or through WSL /mnt."""
    if os.name != "nt":
        match = re.fullmatch(r"([A-Za-z]):\\(.*)", value)
        if match:
            drive, remainder = match.groups()
            return Path("/mnt") / drive.lower() / Path(remainder.replace("\\", "/"))
    return Path(value)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(CHUNK_SIZE), b""):
            digest.update(block)
    return digest.hexdigest()


def write_json_atomic(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    temporary.replace(path)


def categories(relative_path: str) -> list[str]:
    lowered = relative_path.lower()
    result = [
        category
        for category, patterns in CATEGORY_PATTERNS.items()
        if any(pattern in lowered for pattern in patterns)
    ]
    if lowered.endswith(".ko"):
        result.append("kernel_module")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--full-output", type=Path)
    parser.add_argument("--summary-output", type=Path)
    args = parser.parse_args()

    config = json.loads(args.config.read_text(encoding="utf-8-sig"))
    audit_root = configured_path(config["audit_root"]).resolve()
    official_root = configured_path(
        config["official_3_0_304"]["extract_root"]
    ).resolve()
    filesystem_root = official_root / "filesystems"
    if audit_root not in official_root.parents:
        raise ValueError(f"Official work root is outside audit root: {official_root}")
    if not filesystem_root.is_dir():
        raise FileNotFoundError(filesystem_root)

    full_output = (
        args.full_output.resolve()
        if args.full_output
        else official_root / "official-filesystem-file-manifest.json"
    )
    summary_output = (
        args.summary_output.resolve()
        if args.summary_output
        else Path(__file__).resolve().parents[1]
        / "evidence"
        / "official-filesystem-summary.json"
    )
    if official_root not in full_output.parents:
        raise ValueError(f"Full manifest must stay under official work root: {full_output}")

    super_manifest_path = official_root / "official-super-partition-manifest.json"
    super_manifest = json.loads(super_manifest_path.read_text(encoding="utf-8-sig"))
    image_records = {
        item["name"]: item for item in super_manifest["partitions"] if item["bytes"]
    }

    entries: list[dict[str, Any]] = []
    partition_summaries: list[dict[str, Any]] = []
    total_category_counts: Counter[str] = Counter()

    for partition_root in sorted(path for path in filesystem_root.iterdir() if path.is_dir()):
        partition_name = partition_root.name
        partition_entries: list[dict[str, Any]] = []
        partition_categories: Counter[str] = Counter()
        logical_bytes = 0
        symlink_count = 0

        for current, directory_names, file_names in os.walk(
            partition_root, followlinks=False
        ):
            current_path = Path(current)
            for directory_name in list(directory_names):
                candidate = current_path / directory_name
                if candidate.is_symlink():
                    relative = candidate.relative_to(partition_root).as_posix()
                    partition_entries.append(
                        {
                            "partition": partition_name,
                            "path": relative,
                            "type": "symlink",
                            "target": os.readlink(candidate),
                        }
                    )
                    directory_names.remove(directory_name)
                    symlink_count += 1

            for file_name in file_names:
                candidate = current_path / file_name
                relative = candidate.relative_to(partition_root).as_posix()
                matched_categories = categories(relative)
                if candidate.is_symlink():
                    record = {
                        "partition": partition_name,
                        "path": relative,
                        "type": "symlink",
                        "target": os.readlink(candidate),
                    }
                    symlink_count += 1
                else:
                    size = candidate.stat().st_size
                    logical_bytes += size
                    record = {
                        "partition": partition_name,
                        "path": relative,
                        "type": "file",
                        "bytes": size,
                        "sha256": sha256(candidate),
                    }
                if matched_categories:
                    record["categories"] = matched_categories
                    partition_categories.update(matched_categories)
                partition_entries.append(record)

        partition_entries.sort(key=lambda item: (item["path"], item["type"]))
        entries.extend(partition_entries)
        total_category_counts.update(partition_categories)
        image = image_records.get(partition_name, {})
        partition_summaries.append(
            {
                "name": partition_name,
                "image_bytes": image.get("bytes"),
                "image_sha256": image.get("sha256"),
                "file_count": sum(
                    item["type"] == "file" for item in partition_entries
                ),
                "symlink_count": symlink_count,
                "logical_file_bytes": logical_bytes,
                "category_counts": dict(sorted(partition_categories.items())),
            }
        )

    generated_at = datetime.now().astimezone().isoformat(timespec="seconds")
    full_manifest = {
        "schema_version": "1.0",
        "generated_at": generated_at,
        "source_super_sha256": super_manifest["source_super_sha256"],
        "filesystem_root": str(filesystem_root),
        "entry_count": len(entries),
        "entries": entries,
    }
    write_json_atomic(full_output, full_manifest)

    summary = {
        "schema_version": "1.0",
        "generated_at": generated_at,
        "source_super_sha256": super_manifest["source_super_sha256"],
        "filesystem_count": len(partition_summaries),
        "file_count": sum(item["file_count"] for item in partition_summaries),
        "symlink_count": sum(
            item["symlink_count"] for item in partition_summaries
        ),
        "logical_file_bytes": sum(
            item["logical_file_bytes"] for item in partition_summaries
        ),
        "category_counts": dict(sorted(total_category_counts.items())),
        "partitions": partition_summaries,
        "full_manifest": {
            "path": str(full_output),
            "bytes": full_output.stat().st_size,
            "sha256": sha256(full_output),
        },
    }
    write_json_atomic(summary_output, summary)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
