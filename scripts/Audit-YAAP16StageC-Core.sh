#!/usr/bin/env bash
set -uo pipefail

ROOT=/home/arima/android/yaap16
PRODUCT_OUT="$ROOT/out/target/product/haotian"
TF="$PRODUCT_OUT/obj/PACKAGING/target_files_intermediates/yaap_haotian-target-files"
TF="${TF/target-files/target_files}"
TFZIP="$TF.zip"
IMAGES="$TF/IMAGES"
OTA="$PRODUCT_OUT/YAAP-16-HOMEMADE-haotian-20260813.zip"
KEY="$ROOT/vendor/haotian/security/avb.pem"
HOST_BIN="$ROOT/out/host/linux-x86/bin"
AUDIT=/mnt/d/Codex/haotian-rom-fusion-build/logs/stage-c-integrity
SUMMARY="$AUDIT/core-summary.tsv"
mkdir -p "$AUDIT"
: >"$SUMMARY"

run_check() {
    local name=$1
    shift
    local log="$AUDIT/$name.log"
    local start end rc result
    start=$(date --iso-8601=seconds)
    echo "[$start] START $name" | tee "$log"
    set +e
    (set -e; "$@") >>"$log" 2>&1
    rc=$?
    set -e
    end=$(date --iso-8601=seconds)
    if [[ $rc -eq 0 ]]; then result=passed; else result=failed; fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$result" "$rc" "$start" "$end" >>"$SUMMARY"
    echo "[$end] END $name result=$result rc=$rc" | tee -a "$log"
}

check_inputs() {
    for path in "$OTA" "$TFZIP" "$TF" "$KEY"; do
        [[ -e "$path" ]] || { echo "missing: $path"; return 1; }
    done
    stat -c '%n\t%s\t%y' "$OTA" "$TFZIP"
    echo "target_files_directory=$TF"
    echo "avb_key=$KEY"
}

hash_artifacts() {
    local manifest="$AUDIT/artifact-sha256.txt"
    {
        sha256sum "$OTA" "$TFZIP"
        find "$IMAGES" -maxdepth 1 -type f -name '*.img' -print0 | sort -z | xargs -0 sha256sum
    } | tee "$manifest"
    local expected actual
    expected=$(awk '{print $1}' "$OTA.sha256sum")
    actual=$(sha256sum "$OTA" | awk '{print $1}')
    printf 'ota_expected=%s\nota_actual=%s\n' "$expected" "$actual"
    [[ "$expected" = "$actual" ]]
}

ota_structure() {
    python3 - "$OTA" "$PRODUCT_OUT/ota_metadata" <<'PY'
import json
import pathlib
import re
import sys
import zipfile

ota = pathlib.Path(sys.argv[1])
metadata_file = pathlib.Path(sys.argv[2])
required = {
    "META-INF/com/android/metadata",
    "META-INF/com/android/metadata.pb",
    "payload.bin",
    "payload_properties.txt",
    "apex_info.pb",
    "care_map.pb",
}
with zipfile.ZipFile(ota) as zf:
    names = zf.namelist()
    if len(names) != len(set(names)):
        raise SystemExit("duplicate ZIP members detected")
    missing = sorted(required - set(names))
    if missing:
        raise SystemExit(f"missing required members: {missing}")
    bad = zf.testzip()
    if bad:
        raise SystemExit(f"CRC failure: {bad}")
    metadata = zf.read("META-INF/com/android/metadata").decode("utf-8")
    disk_metadata = metadata_file.read_text(encoding="utf-8")
    if metadata.rstrip() != disk_metadata.rstrip():
        raise SystemExit("OTA embedded metadata differs from ota_metadata")
    props = dict(line.split("=", 1) for line in metadata.splitlines() if "=" in line)
    expected = {
        "ota-type": "AB",
        "pre-device": "haotian",
        "post-sdk-level": "36",
        "post-security-patch-level": "2026-05-05",
        "post-build-incremental": "haotian.stagec.20260813.1",
        "post-timestamp": "1786625277",
    }
    for key, value in expected.items():
        if props.get(key) != value:
            raise SystemExit(f"{key}: expected {value}, got {props.get(key)}")
    payload = zf.getinfo("payload.bin")
    if payload.compress_type != zipfile.ZIP_STORED:
        raise SystemExit("payload.bin is not stored, streaming offsets are unsafe")
    result = {
        "archive_size": ota.stat().st_size,
        "member_count": len(names),
        "required_members": sorted(required),
        "payload_size": payload.file_size,
        "payload_compress_type": payload.compress_type,
        "metadata": props,
    }
    print(json.dumps(result, indent=2, ensure_ascii=False))
PY
}

ota_signature_check() {
    cd "$ROOT" || return 1
    PATH="$HOST_BIN:$PATH" "$HOST_BIN/check_ota_package_signature" \
        "$ROOT/build/make/target/product/security/testkey.x509.pem" \
        "$OTA"
}

apk_signature_inventory_check() {
    cd "$ROOT" || return 1
    "$HOST_BIN/check_target_files_signatures" \
        -v \
        --logfile "$AUDIT/apk-signature-tool.log" \
        "$TFZIP"
}

vintf_check() {
    cd "$ROOT" || return 1
    "$HOST_BIN/check_target_files_vintf" -v --logfile "$AUDIT/vintf-tool.log" "$TF"
}

target_files_validate() {
    cd "$ROOT" || return 1
    mkdir -p "$ROOT/out/stage-c-integrity-tmp"
    TMPDIR="$ROOT/out/stage-c-integrity-tmp" "$HOST_BIN/validate_target_files" "$TFZIP"
}

artifact_coherence_check() {
    python3 - "$OTA" "$TFZIP" "$TF" "$PRODUCT_OUT/ota_metadata" <<'PY'
import hashlib
import json
import pathlib
import sys
import zipfile

ota_path = pathlib.Path(sys.argv[1])
tfzip_path = pathlib.Path(sys.argv[2])
tf_dir = pathlib.Path(sys.argv[3])
disk_metadata_path = pathlib.Path(sys.argv[4])

def digest_stream(stream):
    h = hashlib.sha256()
    for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
        h.update(block)
    return h.hexdigest()

def parse_props(text):
    return dict(
        line.split("=", 1)
        for line in text.splitlines()
        if line and not line.startswith("#") and "=" in line
    )

expected_epoch = "1786625277"
expected_incremental = "haotian.stagec.20260813.1"
with zipfile.ZipFile(ota_path) as ota:
    ota_metadata_text = ota.read("META-INF/com/android/metadata").decode("utf-8")
ota_metadata = parse_props(ota_metadata_text)
disk_metadata = parse_props(disk_metadata_path.read_text(encoding="utf-8"))
if ota_metadata != disk_metadata:
    raise SystemExit("embedded OTA metadata does not equal the final on-disk metadata")
if ota_metadata.get("post-timestamp") != expected_epoch:
    raise SystemExit(f"unexpected OTA epoch: {ota_metadata.get('post-timestamp')}")
if ota_metadata.get("post-build-incremental") != expected_incremental:
    raise SystemExit(f"unexpected OTA incremental: {ota_metadata.get('post-build-incremental')}")

results = []
with zipfile.ZipFile(tfzip_path) as tfzip:
    build_member = "SYSTEM/build.prop"
    directory_build = (tf_dir / build_member).read_bytes()
    zipped_build = tfzip.read(build_member)
    if directory_build != zipped_build:
        raise SystemExit("target-files ZIP SYSTEM/build.prop differs from directory")
    build_props = parse_props(directory_build.decode("utf-8"))
    if build_props.get("ro.build.date.utc") != expected_epoch:
        raise SystemExit(f"unexpected build.prop epoch: {build_props.get('ro.build.date.utc')}")
    if build_props.get("ro.build.version.incremental") != expected_incremental:
        raise SystemExit(f"unexpected build.prop incremental: {build_props.get('ro.build.version.incremental')}")

    names = set(tfzip.namelist())
    for image_path in sorted((tf_dir / "IMAGES").glob("*.img")):
        member = f"IMAGES/{image_path.name}"
        if member not in names:
            raise SystemExit(f"missing target-files ZIP member: {member}")
        with image_path.open("rb") as source:
            directory_hash = digest_stream(source)
        with tfzip.open(member) as source:
            zip_hash = digest_stream(source)
        if directory_hash != zip_hash:
            raise SystemExit(f"target-files image mismatch: {member}")
        results.append({
            "image": image_path.name,
            "bytes": image_path.stat().st_size,
            "sha256": directory_hash,
        })

print(json.dumps({
    "build_epoch": expected_epoch,
    "build_incremental": expected_incremental,
    "ota_metadata_matches_disk": True,
    "target_files_build_prop_matches_directory": True,
    "matched_images": results,
}, indent=2))
PY
}

avb_check() {
    cd "$IMAGES" || return 1
    local public_key="$AUDIT/avb-public-key.bin"
    "$HOST_BIN/avbtool" extract_public_key --key "$KEY" --output "$public_key"
    local image
    for image in system system_ext product vendor odm system_dlkm vendor_dlkm init_boot vendor_boot dtbo; do
        echo "=== verify $image ==="
        "$HOST_BIN/avbtool" verify_image --image "$image.img"
    done
    for image in boot recovery vbmeta_system; do
        echo "=== verify signed $image ==="
        "$HOST_BIN/avbtool" verify_image --image "$image.img" --key "$KEY"
    done
    echo '=== verify root vbmeta and chains ==='
    "$HOST_BIN/avbtool" verify_image \
        --image vbmeta.img \
        --key "$KEY" \
        --expected_chain_partition "boot:3:$public_key" \
        --expected_chain_partition "recovery:1:$public_key" \
        --expected_chain_partition "vbmeta_system:2:$public_key" \
        --follow_chain_partitions
    echo '=== root digest ==='
    "$HOST_BIN/avbtool" calculate_vbmeta_digest --image vbmeta.img --hash_algorithm sha256
    echo '=== partition digests ==='
    "$HOST_BIN/avbtool" print_partition_digests --image vbmeta.img --json
}

filesystem_check() {
    local image
    for image in system system_ext product vendor odm system_dlkm vendor_dlkm; do
        echo "=== e2fsck $image ==="
        e2fsck -fn "$IMAGES/$image.img"
        echo "=== debugfs stats $image ==="
        debugfs -R stats "$IMAGES/$image.img" 2>&1 | grep -E \
            'Filesystem volume name|Filesystem UUID|Filesystem state|Block count|Free blocks|Inode count|Free inodes|Block size'
    done
}

dynamic_partition_check() {
    python3 - "$TF/META/misc_info.txt" "$IMAGES" <<'PY'
import json
import pathlib
import sys

props = {}
for line in pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    if "=" in line:
        key, value = line.split("=", 1)
        props[key] = value
images = pathlib.Path(sys.argv[2])
expected = props["dynamic_partition_list"].split()
actual = {p.stem: p.stat().st_size for p in images.glob("*.img") if p.stem in expected}
if set(actual) != set(expected):
    raise SystemExit(f"dynamic images differ: expected={expected}, actual={sorted(actual)}")
group_size = int(props["super_qti_dynamic_partitions_group_size"])
super_size = int(props["super_partition_size"])
total = sum(actual.values())
if total > group_size:
    raise SystemExit(f"image total {total} exceeds group {group_size}")
if group_size >= super_size:
    raise SystemExit("dynamic group does not leave metadata headroom")
print(json.dumps({
    "super_partition_size": super_size,
    "group_size": group_size,
    "partition_sizes": actual,
    "partition_total": total,
    "group_free_if_fully_allocated": group_size - total,
    "virtual_ab": props.get("virtual_ab"),
    "virtual_ab_compression": props.get("virtual_ab_compression"),
    "virtual_ab_compression_method": props.get("virtual_ab_compression_method"),
    "virtual_ab_cow_version": props.get("virtual_ab_cow_version"),
}, indent=2))
PY
    python3 - "$IMAGES/super_empty.img" <<'PY'
import hashlib
import json
import pathlib
import struct
import sys

path = pathlib.Path(sys.argv[1])
data = path.read_bytes()
if len(data) < 4096 + 128:
    raise SystemExit(f"super_empty metadata blob too small: {len(data)}")

geometry = bytearray(data[:4096])
magic, struct_size = struct.unpack_from("<II", geometry, 0)
if magic != 0x616C4467 or struct_size != 52:
    raise SystemExit(f"invalid geometry: magic={magic:#x} struct_size={struct_size}")
stored_geometry_hash = bytes(geometry[8:40])
geometry[8:40] = b"\0" * 32
calculated_geometry_hash = hashlib.sha256(geometry[:struct_size]).digest()
if stored_geometry_hash != calculated_geometry_hash:
    raise SystemExit("geometry SHA-256 mismatch")
metadata_max_size, metadata_slots, logical_block_size = struct.unpack_from("<III", data, 40)

base = 4096
header_magic, major, minor, header_size = struct.unpack_from("<IHHI", data, base)
if header_magic != 0x414C5030 or major != 10 or minor > 2:
    raise SystemExit(f"unsupported metadata header: magic={header_magic:#x} version={major}.{minor}")
if header_size not in (128, 256):
    raise SystemExit(f"unexpected header size: {header_size}")
stored_header_hash = data[base + 12:base + 44]
tables_size = struct.unpack_from("<I", data, base + 44)[0]
stored_tables_hash = data[base + 48:base + 80]
if len(data) != base + header_size + tables_size:
    raise SystemExit(
        f"metadata blob length mismatch: actual={len(data)} expected={base + header_size + tables_size}"
    )
header = bytearray(data[base:base + header_size])
header[12:44] = b"\0" * 32
if hashlib.sha256(header).digest() != stored_header_hash:
    raise SystemExit("metadata header SHA-256 mismatch")
tables = data[base + header_size:base + header_size + tables_size]
if hashlib.sha256(tables).digest() != stored_tables_hash:
    raise SystemExit("metadata tables SHA-256 mismatch")

descriptor_names = ("partitions", "extents", "groups", "block_devices")
descriptors = {}
for index, name in enumerate(descriptor_names):
    offset, count, entry_size = struct.unpack_from("<III", data, base + 80 + index * 12)
    if offset + count * entry_size > tables_size:
        raise SystemExit(f"{name} descriptor exceeds table bounds")
    descriptors[name] = (offset, count, entry_size)

def entries(name):
    offset, count, entry_size = descriptors[name]
    return [tables[offset + i * entry_size:offset + (i + 1) * entry_size] for i in range(count)]

def cstr(raw):
    return raw.split(b"\0", 1)[0].decode("ascii")

partition_rows = []
for entry in entries("partitions"):
    if len(entry) < 52:
        raise SystemExit("short partition entry")
    name = cstr(entry[:36])
    attributes, first_extent, extent_count, group_index = struct.unpack_from("<IIII", entry, 36)
    partition_rows.append({
        "name": name,
        "attributes": attributes,
        "first_extent_index": first_extent,
        "num_extents": extent_count,
        "group_index": group_index,
    })

group_rows = []
for entry in entries("groups"):
    if len(entry) < 48:
        raise SystemExit("short group entry")
    name = cstr(entry[:36])
    flags = struct.unpack_from("<I", entry, 36)[0]
    maximum_size = struct.unpack_from("<Q", entry, 40)[0]
    group_rows.append({"name": name, "flags": flags, "maximum_size": maximum_size})

device_rows = []
for entry in entries("block_devices"):
    if len(entry) < 64:
        raise SystemExit("short block-device entry")
    first_sector, alignment, alignment_offset, size = struct.unpack_from("<QIIQ", entry, 0)
    name = cstr(entry[24:60])
    flags = struct.unpack_from("<I", entry, 60)[0]
    device_rows.append({
        "name": name,
        "size": size,
        "first_logical_sector": first_sector,
        "alignment": alignment,
        "alignment_offset": alignment_offset,
        "flags": flags,
    })

base_partitions = {"system", "system_dlkm", "system_ext", "product", "vendor", "vendor_dlkm", "odm"}
expected_partitions = {f"{name}_{slot}" for name in base_partitions for slot in ("a", "b")}
actual_partitions = {row["name"] for row in partition_rows}
if actual_partitions != expected_partitions:
    raise SystemExit(
        f"super_empty partition names differ: missing={sorted(expected_partitions - actual_partitions)} "
        f"extra={sorted(actual_partitions - expected_partitions)}"
    )
expected_groups = {
    "default": 0,
    "qti_dynamic_partitions_a": 11809841488,
    "qti_dynamic_partitions_b": 11809841488,
}
actual_groups = {row["name"]: row["maximum_size"] for row in group_rows}
if actual_groups != expected_groups:
    raise SystemExit(f"unexpected super groups: {group_rows}")
if len(device_rows) != 1 or device_rows[0]["name"] != "super" or device_rows[0]["size"] != 11811160064:
    raise SystemExit(f"unexpected super block device: {device_rows}")
if any(row["group_index"] >= len(group_rows) for row in partition_rows):
    raise SystemExit("partition refers to missing group")
flags = struct.unpack_from("<I", data, base + 128)[0] if header_size >= 132 else 0
if flags & 0x1 == 0:
    raise SystemExit(f"Virtual A/B flag not set: {flags:#x}")

print(json.dumps({
    "format": "minimal liblp super_empty metadata image",
    "flashable_full_super_image": False,
    "bytes": len(data),
    "geometry": {
        "metadata_max_size": metadata_max_size,
        "metadata_slot_count": metadata_slots,
        "logical_block_size": logical_block_size,
        "sha256_valid": True,
    },
    "header": {
        "version": f"{major}.{minor}",
        "header_size": header_size,
        "tables_size": tables_size,
        "flags": flags,
        "virtual_ab": True,
        "header_sha256_valid": True,
        "tables_sha256_valid": True,
    },
    "partitions": partition_rows,
    "groups": group_rows,
    "block_devices": device_rows,
    "descriptors": {name: {"offset": row[0], "count": row[1], "entry_size": row[2]} for name, row in descriptors.items()},
}, indent=2))
PY
}

selinux_check() {
    local policy="$TF/ODM/etc/selinux/precompiled_sepolicy"
    [[ -s "$policy" ]]
    [[ -e "$PRODUCT_OUT/fake_packages/sepolicy_neverallows-timestamp" ]]
    echo '=== permissive domains ==='
    local permissive
    permissive=$("$HOST_BIN/sepolicy-analyze" "$policy" permissive)
    printf '%s\n' "$permissive"
    local expected_permissive
    expected_permissive=$(printf '%s\n' \
        aoncameraservice_app \
        backuptool \
        qti-testscripts \
        su \
        vendor-qti-testscripts \
        vendor_cta_app \
        vendor_hal_debugutils_default \
        vendor_logkit_app \
        vendor_pdt_app | sort)
    local actual_permissive
    actual_permissive=$(printf '%s\n' "$permissive" | sed '/^$/d' | sort)
    if [[ "$actual_permissive" != "$expected_permissive" ]]; then
        echo 'unexpected userdebug permissive-domain set'
        diff -u <(printf '%s\n' "$expected_permissive") <(printf '%s\n' "$actual_permissive") || true
        return 1
    fi
    echo 'classification=userdebug-only expected allowlist; production user build must contain zero permissive domains'
    echo '=== precompiled policy digests ==='
    python3 - "$TF" <<'PY'
import hashlib
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
pairs = [
    (root / "SYSTEM/etc/selinux/plat_sepolicy_and_mapping.sha256", root / "ODM/etc/selinux/precompiled_sepolicy.plat_sepolicy_and_mapping.sha256"),
    (root / "SYSTEM_EXT/etc/selinux/system_ext_sepolicy_and_mapping.sha256", root / "ODM/etc/selinux/precompiled_sepolicy.system_ext_sepolicy_and_mapping.sha256"),
    (root / "PRODUCT/etc/selinux/product_sepolicy_and_mapping.sha256", root / "ODM/etc/selinux/precompiled_sepolicy.product_sepolicy_and_mapping.sha256"),
]
for source, compiled in pairs:
    a = source.read_text(encoding="ascii").strip()
    b = compiled.read_text(encoding="ascii").strip()
    print(f"{source.relative_to(root)}={a}")
    print(f"{compiled.relative_to(root)}={b}")
    if a != b:
        raise SystemExit(f"SELinux policy digest mismatch: {source} != {compiled}")
PY
}

build_identity_check() {
    python3 - "$PRODUCT_OUT/system/build.prop" "$PRODUCT_OUT/ota_metadata" <<'PY'
import json
import pathlib
import sys

def parse(path):
    out = {}
    for line in pathlib.Path(path).read_text(encoding="utf-8").splitlines():
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            out[k] = v
    return out

build = parse(sys.argv[1])
ota = parse(sys.argv[2])
checks = {
    "ro.build.version.sdk": "36",
    "ro.build.type": "userdebug",
    "ro.build.tags": "test-keys",
    "ro.build.flavor": "yaap_haotian-userdebug",
    "ro.yaap.device": "haotian",
    "ro.build.date.utc": "1786625277",
    "ro.build.version.incremental": "haotian.stagec.20260813.1",
}
for key, value in checks.items():
    if build.get(key) != value:
        raise SystemExit(f"{key}: expected {value}, got {build.get(key)}")
if ota.get("ota-type") != "AB" or ota.get("pre-device") != "haotian":
    raise SystemExit("OTA metadata identity mismatch")
print(json.dumps({"build": {k: build.get(k) for k in checks}, "ota": ota}, indent=2))
PY
}

main() {
    set -e
    run_check inputs check_inputs
    run_check hashes hash_artifacts
    run_check ota_structure ota_structure
    run_check artifact_coherence artifact_coherence_check
    run_check ota_whole_file_and_payload_signature ota_signature_check
    run_check target_files_zip_crc unzip -tq "$TFZIP"
    run_check apk_signature_inventory apk_signature_inventory_check
    run_check vintf vintf_check
    run_check validate_target_files target_files_validate
    run_check avb avb_check
    run_check filesystems filesystem_check
    run_check dynamic_partitions dynamic_partition_check
    run_check selinux selinux_check
    run_check build_identity build_identity_check

    local failed
    failed=$(awk -F '\t' '$2 != "passed" {count++} END {print count+0}' "$SUMMARY")
    printf 'failed_checks=%s\n' "$failed" | tee "$AUDIT/core-final.status"
    cat "$SUMMARY"
    return "$failed"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main
fi
