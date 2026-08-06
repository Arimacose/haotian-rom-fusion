#!/usr/bin/env python3
"""Validate pinned haotian inputs and write a compact evidence manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime
from pathlib import Path
from typing import Any


def sha256(path: Path, block_size: int = 8 * 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(block_size), b""):
            digest.update(block)
    return digest.hexdigest()


def add_record(
    records: list[dict[str, Any]],
    name: str,
    path_value: str,
    expected_bytes: int | None = None,
    expected_sha256: str | None = None,
    hash_present: bool = True,
) -> None:
    path = Path(path_value)
    record: dict[str, Any] = {
        "name": name,
        "path": str(path),
        "exists": path.is_file(),
        "expected_bytes": expected_bytes,
        "expected_sha256": expected_sha256,
    }
    if path.is_file():
        record["bytes"] = path.stat().st_size
        record["size_match"] = (
            expected_bytes is None or path.stat().st_size == expected_bytes
        )
        if hash_present:
            actual_hash = sha256(path)
            record["sha256"] = actual_hash
            record["sha256_match"] = (
                expected_sha256 is None or actual_hash == expected_sha256.lower()
            )
        else:
            record["sha256"] = None
            record["sha256_match"] = None
    else:
        record["bytes"] = None
        record["size_match"] = None
        record["sha256"] = None
        record["sha256_match"] = None
    records.append(record)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parents[1]
        / "evidence"
        / "baseline-manifest.json",
    )
    parser.add_argument(
        "--allow-missing",
        action="store_true",
        help="Record absent inputs as pending instead of returning a failing status.",
    )
    parser.add_argument(
        "--skip-large-hashes",
        action="store_true",
        help="Check paths and sizes without hashing multi-gigabyte archives.",
    )
    parser.add_argument(
        "--config-only",
        action="store_true",
        help="Parse and validate the configuration without reading local artifacts.",
    )
    args = parser.parse_args()

    config = json.loads(args.config.read_text(encoding="utf-8-sig"))
    required_top = {
        "schema_version",
        "device",
        "official_3_0_304",
        "evolutionx",
        "lineageos",
        "tools",
        "source",
    }
    missing_keys = sorted(required_top - set(config))
    if missing_keys:
        raise ValueError(f"Missing configuration keys: {missing_keys}")
    if config["device"] != "haotian":
        raise ValueError(f"Unexpected device: {config['device']}")

    if args.config_only:
        print(json.dumps({"config": str(args.config), "valid": True}, indent=2))
        return 0

    records: list[dict[str, Any]] = []
    official = config["official_3_0_304"]
    evolution = config["evolutionx"]
    lineage = config["lineageos"]

    add_record(
        records,
        "official-fastboot-3.0.304",
        official["archive"],
        official["expected_bytes"],
        official.get("sha256"),
        not args.skip_large_hashes,
    )
    add_record(
        records,
        "official-firmware-3.0.304",
        official["firmware_zip"]["path"],
        official["firmware_zip"]["bytes"],
        official["firmware_zip"]["sha256"],
        True,
    )
    add_record(
        records,
        "evolutionx-0603-ota",
        evolution["archive"],
        evolution["bytes"],
        evolution["sha256"],
        not args.skip_large_hashes,
    )
    add_record(
        records,
        "lineageos-0704-ota",
        lineage["archive"],
        lineage["bytes"],
        lineage["sha256"],
        not args.skip_large_hashes,
    )
    add_record(
        records,
        "evolutionx-kernel",
        evolution["kernel"],
        36_456_960,
        "99485b0132e3aa28f4e965119591c8149fe3c20e7e0fd10d753ef014a582472e",
        True,
    )
    add_record(
        records,
        "lineageos-kernel",
        lineage["kernel"],
        36_456_960,
        "99485b0132e3aa28f4e965119591c8149fe3c20e7e0fd10d753ef014a582472e",
        True,
    )

    mismatches = [
        record["name"]
        for record in records
        if record["exists"]
        and (
            record["size_match"] is False
            or record["sha256_match"] is False
        )
    ]
    absent = [record["name"] for record in records if not record["exists"]]
    result = {
        "schema_version": "1.0",
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "device": config["device"],
        "records": records,
        "mismatches": mismatches,
        "absent": absent,
        "valid": not mismatches and (args.allow_missing or not absent),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(args.output.suffix + ".tmp")
    temporary.write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    temporary.replace(args.output)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["valid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
