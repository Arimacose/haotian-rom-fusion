#!/usr/bin/env python3
"""Measure pinned proprietary-list coverage against official extracted files."""

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


def configured_path(value: str) -> Path:
    if os.name != "nt":
        match = re.fullmatch(r"([A-Za-z]):\\(.*)", value)
        if match:
            drive, remainder = match.groups()
            return Path("/mnt") / drive.lower() / Path(remainder.replace("\\", "/"))
    return Path(value)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_json_atomic(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    temporary.replace(path)


def parse_entry(line: str) -> tuple[str, dict[str, Any]] | None:
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        return None
    flags: list[str] = []
    if ";" in stripped:
        stripped, flag_text = stripped.split(";", 1)
        flags = [item for item in flag_text.split(";") if item]
    pinned_hash = None
    if "|" in stripped:
        stripped, pinned_hash = stripped.split("|", 1)
    source = stripped.lstrip("-").split(":", 1)[0]
    return source, {"flags": flags, "pinned_hash": pinned_hash}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--full-output", type=Path)
    parser.add_argument("--summary-output", type=Path)
    parser.add_argument("--haotian-list", type=Path)
    parser.add_argument("--common-list", type=Path)
    args = parser.parse_args()

    config = json.loads(args.config.read_text(encoding="utf-8-sig"))
    official_root = configured_path(config["official_3_0_304"]["extract_root"]).resolve()
    filesystem_root = official_root / "filesystems"
    lineage_work = configured_path(config["lineageos"]["partition_root"]).resolve().parent
    source_root = lineage_work / "public-source"
    lists = {
        "haotian": args.haotian_list.resolve()
        if args.haotian_list
        else source_root / "device_xiaomi_haotian" / "proprietary-files.txt",
        "sm8750-common": args.common_list.resolve()
        if args.common_list
        else source_root
        / "device_xiaomi_sm8750-common"
        / "proprietary-files.txt",
    }
    for path in [filesystem_root, *lists.values()]:
        if not path.exists():
            raise FileNotFoundError(path)

    full_output = (
        args.full_output.resolve()
        if args.full_output
        else official_root / "proprietary-coverage-full.json"
    )
    summary_output = (
        args.summary_output.resolve()
        if args.summary_output
        else Path(__file__).resolve().parents[1]
        / "evidence"
        / "proprietary-coverage-summary.json"
    )
    if official_root not in full_output.parents:
        raise ValueError(f"Full output must stay under official work root: {full_output}")

    list_results: list[dict[str, Any]] = []
    full_entries: list[dict[str, Any]] = []
    for list_name, list_path in lists.items():
        lines = list_path.read_text(encoding="utf-8", errors="replace").splitlines()
        entries: list[dict[str, Any]] = []
        by_partition: Counter[str] = Counter()
        hits_by_partition: Counter[str] = Counter()
        for line_number, line in enumerate(lines, start=1):
            parsed = parse_entry(line)
            if parsed is None:
                continue
            source, metadata = parsed
            components = Path(source).parts
            partition = components[0] if components else ""
            by_partition[partition] += 1
            partition_root = filesystem_root / f"{partition}_a"
            candidate = (
                partition_root.joinpath(*components)
                if partition == "system"
                else partition_root.joinpath(*components[1:])
            )
            present = os.path.lexists(candidate)
            if present:
                hits_by_partition[partition] += 1
            entry = {
                "list": list_name,
                "line": line_number,
                "source": source,
                "partition": partition,
                "present": present,
                "type": (
                    "symlink"
                    if present and candidate.is_symlink()
                    else "file"
                    if present
                    else None
                ),
                **metadata,
            }
            if not present:
                entry["relocation_candidates"] = [
                    str(path.relative_to(filesystem_root))
                    for path in filesystem_root.rglob(Path(source).name)
                ][:20]
            entries.append(entry)
            full_entries.append(entry)

        missing = [entry["source"] for entry in entries if not entry["present"]]
        relocated = [
            entry
            for entry in entries
            if not entry["present"] and entry.get("relocation_candidates")
        ]
        list_results.append(
            {
                "name": list_name,
                "source_path": str(list_path),
                "source_sha256": sha256(list_path),
                "source_header": [line for line in lines[:4] if line.startswith("#")],
                "entry_count": len(entries),
                "present_count": len(entries) - len(missing),
                "missing_count": len(missing),
                "relocation_candidate_count": len(relocated),
                "coverage_percent": round(
                    100 * (len(entries) - len(missing)) / len(entries), 3
                ),
                "entries_by_partition": dict(sorted(by_partition.items())),
                "hits_by_partition": dict(sorted(hits_by_partition.items())),
                "missing_sample": missing[:200],
                "relocation_candidates": [
                    {
                        "source": entry["source"],
                        "candidates": entry["relocation_candidates"],
                    }
                    for entry in relocated[:50]
                ],
            }
        )

    generated_at = datetime.now().astimezone().isoformat(timespec="seconds")
    full = {
        "schema_version": "1.0",
        "generated_at": generated_at,
        "official_version": config["official_3_0_304"]["version"],
        "entry_count": len(full_entries),
        "entries": full_entries,
    }
    write_json_atomic(full_output, full)

    entry_count = sum(item["entry_count"] for item in list_results)
    present_count = sum(item["present_count"] for item in list_results)
    relocation_candidate_count = sum(
        item["relocation_candidate_count"] for item in list_results
    )
    summary = {
        "schema_version": "1.0",
        "generated_at": generated_at,
        "official_version": config["official_3_0_304"]["version"],
        "entry_count": entry_count,
        "present_count": present_count,
        "missing_count": entry_count - present_count,
        "relocation_candidate_count": relocation_candidate_count,
        "coverage_percent": round(100 * present_count / entry_count, 3),
        "lists": list_results,
        "full_result": {
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
