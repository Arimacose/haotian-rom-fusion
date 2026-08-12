#!/usr/bin/env python3
"""Run bounded static checks for the YAAP 16 haotian source closure.

This script deliberately avoids envsetup, lunch, Soong, Ninja, image creation,
and device access. It validates only files, Git revisions, manifest structure,
selected module declarations, proprietary-tree coverage, and kernel inputs.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import tarfile
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any


EXPECTED_PROJECTS = {
    "vendor/yaap": "32d6a6d1016b98d6435c5ce674ae7c236dc5acb7",
    "device/xiaomi/haotian": "534e15a4b4fc49672826e2c99d1fcad1d64e5802",
    "device/xiaomi/sm8750-common": "dbfb9fc599f7e2ff7e3c5add6b9c8f38185db90a",
    "device/xiaomi/haotian-kernel": "802915cc6b269c3bf577327c4c165c3117852ff5",
    "hardware/lineage/interfaces": "ca560522cee3977861002372d1408cd7bb690198",
    "device/lineage/sepolicy": "4aa6646b41042e19d9238034ed202d9a6b1a5ed9",
    "device/qcom/sepolicy_vndr/sm8750": "b5c02660d4e410403385bbdd33185ae3261c7ec8",
    "hardware/qcom-caf/sm8750/audio/agm": "853c0f6afd242b506636c9af47cb4ed64a4056f0",
    "hardware/qcom-caf/sm8750/audio/graphservices": "62591b81ddb14cb1ddecf2a8e7162f2082456793",
    "hardware/qcom-caf/sm8750/audio/pal": "39f7cccd8bbd3e51b71431e574fb38651be23cae",
    "hardware/qcom-caf/sm8750/audio/primary-hal": "443dec4613a7e5dbc997eb2d7b087f0f07ae5258",
    "hardware/qcom-caf/sm8750/data-ipa-cfg-mgr": "5c754092b8e85dd72904b9a5c62a687bae9ce627",
    "hardware/qcom-caf/sm8750/dataipa": "c6206833bd59478caaa0a69e9d71f1bbfa866a96",
    "hardware/qcom-caf/sm8750/display/core": "20cf597e21bdd31af4e3a55660e991e22f69bf8b",
    "hardware/qcom-caf/sm8750/display/hal": "4b74f47925c54e95c805275832a65830af0431b6",
    "hardware/qcom-caf/sm8750/display/intf": "19b5c055b40bc3d7af4309662eea98c7e7a72cee",
    "hardware/qcom-caf/common": "488707fd3df37a6d8f1bd6bdb69087523a0e5f92",
    "hardware/xiaomi": "892a1cded9c7bf89adf4700af5dfca099ec54782",
    "packages/apps/EuiccPolicy": "7232f94f1a908272d4b72bf13277a54c889f9f2c",
    "vendor/qcom/opensource/commonsys/audio": "af06e9427170c7cf089a2f8306dec026d20aba0c",
    "vendor/qcom/opensource/commonsys-intf/audio": "7d983f8254cb84c0460e2460bd4fca1cc10a0899",
    "vendor/qcom/opensource/libvmmem": "a4a0b08614eb1de238dd1fbe4cef94213560d5f1",
}

EXPECTED_VENDOR_TREES = {
    "haotian": {"files": 3046, "bytes": 5_465_316_231},
    "sm8750-common": {"files": 1782, "bytes": 785_115_017},
}

EXPECTED_SOUNDTRIGGER = (
    "vendor/xiaomi/sm8750-common/proprietary/vendor/lib64/hw/"
    "libsoundtriggerhal.qti.so"
)
EXPECTED_SOUNDTRIGGER_SHA256 = (
    "387afadf222ca499c924c17ba9966bd1750ee1cad2a1f4f543d328c7098ef553"
)

EXPECTED_KERNEL = {
    "kernel": "99485b0132e3aa28f4e965119591c8149fe3c20e7e0fd10d753ef014a582472e",
    "dtbo.img": "602f91eb634ad49d70c59d45a071358f37e02ded68db563efb9b25b4d7dfa804",
    "prebuilt_kernel_headers.tar.gz": "5466a76ca2c4b0dca9a6f02b60daccf772b01d876b4d952730dd38442b97f46f",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def git(path: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", "-C", os.fspath(path), *args], text=True, stderr=subprocess.STDOUT
    ).strip()


def tree_totals(path: Path) -> tuple[int, int]:
    files = [item for item in path.rglob("*") if item.is_file()]
    return len(files), sum(item.stat().st_size for item in files)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--resolved-manifest", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--gapps-profile",
        choices=("gapps", "default"),
        help="Record an explicit runtime profile selected outside the product makefile.",
    )
    args = parser.parse_args()

    source = args.source.resolve()
    checks: list[dict[str, Any]] = []

    def check(
        check_id: str,
        passed: bool,
        actual: Any,
        expected: Any,
        *,
        severity: str = "error",
        note: str = "",
    ) -> None:
        checks.append(
            {
                "id": check_id,
                "status": "pass" if passed else ("pending" if severity == "pending" else "fail"),
                "severity": severity,
                "actual": actual,
                "expected": expected,
                "note": note,
            }
        )

    manifest_root = ET.parse(args.resolved_manifest).getroot()
    projects = manifest_root.findall("project")
    by_path = {(item.get("path") or item.get("name")): item for item in projects}
    paths = list(by_path)
    check("manifest.project_count", len(projects) == 1150, len(projects), 1150)
    check("manifest.unique_paths", len(paths) == len(projects), len(paths), len(projects))

    for path, expected_revision in EXPECTED_PROJECTS.items():
        manifest_project = by_path.get(path)
        manifest_revision = manifest_project.get("revision") if manifest_project is not None else None
        check(
            f"manifest.revision.{path}",
            manifest_revision == expected_revision,
            manifest_revision,
            expected_revision,
        )
        project_root = source / path
        local_revision = git(project_root, "rev-parse", "HEAD") if project_root.is_dir() else None
        check(f"git.head.{path}", local_revision == expected_revision, local_revision, expected_revision)
        status = git(project_root, "status", "--porcelain=v1") if project_root.is_dir() else "absent"
        check(f"git.clean.{path}", status == "", status or "clean", "clean")

    android_products = (source / "device/xiaomi/haotian/AndroidProducts.mk").read_text(encoding="utf-8")
    product_mk = (source / "device/xiaomi/haotian/yaap_haotian.mk").read_text(encoding="utf-8")
    board_device = (source / "device/xiaomi/haotian/BoardConfig.mk").read_text(encoding="utf-8")
    board_common = (source / "device/xiaomi/sm8750-common/BoardConfigCommon.mk").read_text(encoding="utf-8")
    common_mk = (source / "device/xiaomi/sm8750-common/common.mk").read_text(encoding="utf-8")
    version_mk = (source / "vendor/yaap/config/version.mk").read_text(encoding="utf-8")

    check("product.makefile_registered", "yaap_haotian.mk" in android_products, True, True)
    expected_lunch = {"yaap_haotian-user", "yaap_haotian-userdebug", "yaap_haotian-eng"}
    check(
        "product.lunch_choices",
        expected_lunch.issubset(set(android_products.replace("\\", " ").split())),
        sorted(token for token in android_products.replace("\\", " ").split() if token.startswith("yaap_haotian-")),
        sorted(expected_lunch),
    )
    check("product.name", "PRODUCT_NAME := yaap_haotian" in product_mk, True, True)
    check(
        "product.yaap_inheritance",
        "vendor/yaap/config/common_full_phone.mk" in product_mk,
        True,
        True,
    )
    check(
        "product.lineage_base_removed",
        "vendor/lineage/config" not in product_mk and "PRODUCT_NAME := lineage_" not in product_mk,
        True,
        True,
    )
    check(
        "product.stock_identity",
        "OS3.0.304.0.WOBCNXM" in product_mk and "2410DPN6CC" in product_mk,
        True,
        True,
    )
    check("board.vendor_include", "vendor/xiaomi/haotian/BoardConfigVendor.mk" in board_device, True, True)
    check(
        "board.common_vendor_include",
        "vendor/xiaomi/sm8750-common/BoardConfigVendor.mk" in board_common,
        True,
        True,
    )
    check(
        "board.yaap_fingerprint_variable",
        "LINEAGE_VERSION" not in board_common and "ROM_FINGERPRINT" in board_common and "ROM_FINGERPRINT :=" in version_mk,
        True,
        True,
    )
    release_map = (source / "vendor/yaap/release/release_config_map.mk").read_text(
        encoding="utf-8"
    )
    check("product.android16_release", "bp4a" in release_map, "bp4a" in release_map, True)

    health_bp = (source / "hardware/lineage/interfaces/health/aidl/default/Android.bp").read_text(encoding="utf-8")
    health_policy_files = [
        source / "device/lineage/sepolicy/common/public/attributes",
        source / "device/lineage/sepolicy/common/dynamic/service.te",
        source / "device/lineage/sepolicy/common/dynamic/service_contexts",
        source / "device/lineage/sepolicy/common/dynamic/hal_lineage_health.te",
        source / "device/lineage/sepolicy/common/vendor/file_contexts",
        source / "device/lineage/sepolicy/common/vendor/hal_lineage_health_default.te",
        source / "device/xiaomi/sm8750-common/sepolicy/vendor/hal_lineage_health_default.te",
    ]
    check(
        "health.module_definition",
        'name: "vendor.lineage.health-service.default"' in health_bp,
        True,
        True,
    )
    check(
        "health.product_reference",
        "vendor.lineage.health-service.default" in common_mk,
        True,
        True,
    )
    check(
        "health.policy_files",
        all(path.is_file() for path in health_policy_files),
        [os.fspath(path.relative_to(source)) for path in health_policy_files if path.is_file()],
        [os.fspath(path.relative_to(source)) for path in health_policy_files],
    )
    health_policy = "\n".join(path.read_text(encoding="utf-8") for path in health_policy_files if path.is_file())
    for token in (
        "hal_attribute_lineage(lineage_health)",
        "hal_lineage_health_service",
        "hal_lineage_health_default_exec",
        "vendor.lineage.health.IChargingControl/default",
    ):
        check(f"health.policy_token.{token}", token in health_policy, token if token in health_policy else None, token)

    vendor_root = source / "vendor/xiaomi"
    for name, expected in EXPECTED_VENDOR_TREES.items():
        actual_files, actual_bytes = tree_totals(vendor_root / name)
        check(f"vendor.files.{name}", actual_files == expected["files"], actual_files, expected["files"])
        check(f"vendor.bytes.{name}", actual_bytes == expected["bytes"], actual_bytes, expected["bytes"])
        for required in ("Android.bp", "Android.mk", "BoardConfigVendor.mk"):
            path = vendor_root / name / required
            check(f"vendor.required.{name}.{required}", path.is_file(), path.is_file(), True)

    commonsys_audio_bp = (
        source / "vendor/qcom/opensource/commonsys/audio/hal_adapter/Android.bp"
    ).read_text(encoding="utf-8")
    for module in ("libaudiohalvendorextn", "qtiaudiohalvendorextn"):
        check(
            f"audio.source_module.{module}",
            f'name: "{module}"' in commonsys_audio_bp,
            module if f'name: "{module}"' in commonsys_audio_bp else None,
            module,
        )

    soundtrigger_path = source / EXPECTED_SOUNDTRIGGER
    soundtrigger_bp = (source / "vendor/xiaomi/sm8750-common/Android.bp").read_text(
        encoding="utf-8"
    )
    soundtrigger_mk = (
        source / "vendor/xiaomi/sm8750-common/sm8750-common-vendor.mk"
    ).read_text(encoding="utf-8")
    soundtrigger_list = (
        source / "device/xiaomi/sm8750-common/proprietary-files.txt"
    ).read_text(encoding="utf-8")
    check(
        "audio.soundtrigger.proprietary_entry",
        "vendor/lib64/hw/libsoundtriggerhal.qti.so;DISABLE_DEPS" in soundtrigger_list,
        "present" if "libsoundtriggerhal.qti.so;DISABLE_DEPS" in soundtrigger_list else "absent",
        "present",
    )
    check(
        "audio.soundtrigger.module",
        'name: "libsoundtriggerhal.qti"' in soundtrigger_bp,
        "present" if 'name: "libsoundtriggerhal.qti"' in soundtrigger_bp else "absent",
        "present",
    )
    check(
        "audio.soundtrigger.product_package",
        "libsoundtriggerhal.qti" in soundtrigger_mk,
        "present" if "libsoundtriggerhal.qti" in soundtrigger_mk else "absent",
        "present",
    )
    actual_soundtrigger_sha = sha256(soundtrigger_path) if soundtrigger_path.is_file() else None
    check(
        "audio.soundtrigger.sha256",
        actual_soundtrigger_sha == EXPECTED_SOUNDTRIGGER_SHA256,
        actual_soundtrigger_sha,
        EXPECTED_SOUNDTRIGGER_SHA256,
    )

    kernel_root = source / "device/xiaomi/haotian-kernel"
    for filename, expected_digest in EXPECTED_KERNEL.items():
        path = kernel_root / filename
        actual_digest = sha256(path) if path.is_file() else None
        check(f"kernel.sha256.{filename}", actual_digest == expected_digest, actual_digest, expected_digest)

    archive = kernel_root / "prebuilt_kernel_headers.tar.gz"
    with tarfile.open(archive, "r:gz") as tar:
        members = tar.getmembers()
        names = {item.name for item in members}
        file_modes = {item.mode for item in members if item.isfile()}
        directory_modes = {item.mode for item in members if item.isdir()}
    check("kernel.headers.entries", len(members) == 1099, len(members), 1099)
    check(
        "kernel.headers.case_pair",
        {"./linux/netfilter/xt_CONNMARK.h", "./linux/netfilter/xt_connmark.h"}.issubset(names),
        sorted(name for name in names if name.endswith(("xt_CONNMARK.h", "xt_connmark.h"))),
        ["./linux/netfilter/xt_CONNMARK.h", "./linux/netfilter/xt_connmark.h"],
    )
    check("kernel.headers.file_modes", file_modes == {0o644}, sorted(file_modes), [0o644])
    check("kernel.headers.directory_modes", directory_modes == {0o755}, sorted(directory_modes), [0o755])

    avb_key = source / "vendor/haotian/security/avb.pem"
    check(
        "release.avb_private_key",
        avb_key.is_file(),
        "present" if avb_key.is_file() else "absent",
        "present before first build",
        severity="pending",
        note="Keep the private key local and outside the management repository.",
    )
    gapps_enabled = (
        args.gapps_profile == "gapps" or "TARGET_BUILD_GAPPS := true" in product_mk
    )
    gapps_explicit = args.gapps_profile is not None
    selected_profile = (
        "GApps" if args.gapps_profile == "gapps" else "YAAP default MicroG/vanilla path"
    )
    check(
        "product.gapps_profile",
        (gapps_enabled == (args.gapps_profile == "gapps")) if gapps_explicit else False,
        (
            "GApps (TARGET_BUILD_GAPPS=true runtime profile)"
            if gapps_enabled
            else "YAAP default MicroG/vanilla path"
        ),
        selected_profile if gapps_explicit else "choose before first build",
        severity="error" if gapps_explicit else "pending",
        note="Explicit runtime selection takes precedence over the product default.",
    )
    out_dir = source / "out"
    check(
        "execution.compile_skipped",
        not out_dir.exists(),
        "out absent" if not out_dir.exists() else "out present",
        "no compile output in this phase",
        severity="pending" if out_dir.exists() else "info",
    )

    failures = [item for item in checks if item["status"] == "fail" and item["severity"] == "error"]
    pending = [item for item in checks if item["status"] == "pending"]
    report = {
        "schema_version": "1.0",
        "source": os.fspath(source),
        "resolved_manifest": os.fspath(args.resolved_manifest.resolve()),
        "summary": {
            "result": "pass" if not failures else "fail",
            "checks": len(checks),
            "passed": sum(item["status"] == "pass" for item in checks),
            "failed": len(failures),
            "pending": len(pending),
            "compile_started": out_dir.exists(),
        },
        "checks": checks,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["summary"], ensure_ascii=False))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
