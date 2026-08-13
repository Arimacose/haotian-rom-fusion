#!/usr/bin/env bash
set -uo pipefail

ROOT=/home/arima/android/yaap16
PRODUCT_OUT="$ROOT/out/target/product/haotian"
TF="$PRODUCT_OUT/obj/PACKAGING/target_files_intermediates/yaap_haotian-target-files"
TF="${TF/target-files/target_files}"
TFZIP="$TF.zip"
OTA="$PRODUCT_OUT/YAAP-16-HOMEMADE-haotian-20260813.zip"
HOST_BIN="$ROOT/out/host/linux-x86/bin"
AUDIT=/mnt/d/Codex/haotian-rom-fusion-build/logs/stage-c-integrity
WORK="$ROOT/out/stage-c-integrity-work"
PYTHON_DEPS="$ROOT/out/stage-c-integrity-python"
SUMMARY="$AUDIT/payload-apex-summary.tsv"
mkdir -p "$AUDIT" "$WORK"
export PATH="$HOST_BIN:$PATH"

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

extract_payload() {
    rm -f "$WORK/payload.bin" "$WORK/payload_properties.txt" "$WORK/payload_properties.regenerated.txt"
    unzip -p "$OTA" payload.bin >"$WORK/payload.bin"
    unzip -p "$OTA" payload_properties.txt >"$WORK/payload_properties.txt"
    stat -c '%n\t%s\t%y' "$WORK/payload.bin" "$WORK/payload_properties.txt"
    sha256sum "$WORK/payload.bin" "$WORK/payload_properties.txt" | tee "$AUDIT/payload-sha256.txt"
    local expected
    expected=$(unzip -Z -v "$OTA" payload.bin | awk '/uncompressed size:/ {print $3; exit}')
    local actual
    actual=$(stat -c %s "$WORK/payload.bin")
    printf 'zip_declared_payload_size=%s\nextracted_payload_size=%s\n' "$expected" "$actual"
    [[ -z "$expected" || "$expected" = "$actual" ]]
}

payload_properties_check() {
    "$HOST_BIN/brillo_update_payload" properties \
        --payload "$WORK/payload.bin" \
        --properties_file "$WORK/payload_properties.regenerated.txt"
    echo '=== embedded ==='
    cat "$WORK/payload_properties.txt"
    echo '=== regenerated ==='
    cat "$WORK/payload_properties.regenerated.txt"
    cmp "$WORK/payload_properties.txt" "$WORK/payload_properties.regenerated.txt"
}

payload_verify() {
    rm -rf "$WORK/payload-verify"
    mkdir -p "$WORK/payload-verify"
    "$HOST_BIN/brillo_update_payload" verify \
        --payload "$WORK/payload.bin" \
        --target_image "$TFZIP" \
        --work_dir "$WORK/payload-verify"
}

payload_static_check() {
    local public_key="$WORK/testkey.pub.pem"
    local compat="$WORK/paycheck-compat"
    rm -rf "$compat"
    cp -a "$ROOT/system/update_engine/scripts" "$compat"
    python3 - "$compat/update_payload/checker.py" <<'PY'
import hashlib
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
needle = """    if msg.HasField(field_name):
      raise error.PayloadError('%sfield %r exists.' %
                               (msg_name + ' ' if msg_name else '', field_name))
"""
replacement = """    # Android 16 removed the legacy ChromeOS old_kernel_info and
    # old_rootfs_info fields while this checker still probes for them.
    # A field absent from the active descriptor is necessarily not present.
    if field_name not in msg.DESCRIPTOR.fields_by_name:
      return
    if msg.HasField(field_name):
      raise error.PayloadError('%sfield %r exists.' %
                               (msg_name + ' ' if msg_name else '', field_name))
"""
if source.count(needle) != 1:
    raise SystemExit("unexpected paycheck checker source; compatibility patch not applied")
patched = source.replace(needle, replacement)
path.write_text(patched, encoding="utf-8")
print("paycheck_original_sha256=" + hashlib.sha256(source.encode()).hexdigest())
print("paycheck_patched_sha256=" + hashlib.sha256(patched.encode()).hexdigest())
PY
    openssl x509 -pubkey -noout \
        -in "$ROOT/build/make/target/product/security/testkey.x509.pem" \
        >"$public_key"
    PYTHONPATH="$PYTHON_DEPS:$compat" \
        python3 "$compat/paycheck.py" \
        "$WORK/payload.bin" \
        --type full \
        --check \
        --key "$public_key" \
        --report "$AUDIT/payload-static-report.txt"
}

payload_info() {
    cd "$ROOT" || return 1
    if ! PYTHONPATH="$PYTHON_DEPS" python3 -c 'import google.protobuf' >/dev/null 2>&1; then
        python3 -m pip install --target "$PYTHON_DEPS" protobuf==3.20.3
    fi
    PYTHONPATH="$PYTHON_DEPS:$ROOT/system/update_engine/scripts" \
        python3 system/update_engine/scripts/payload_info.py "$WORK/payload.bin"
}

apex_check() {
    local apex_root partition source actual count=0 failed=0
    local apex_work="$WORK/apex"
    rm -rf "$apex_work"
    mkdir -p "$apex_work"
    : >"$AUDIT/apex-results.tsv"
    printf 'partition\tfile\ttype\tapksigner_rc\thost_verifier_rc\n' >>"$AUDIT/apex-results.tsv"

    for partition in system system_ext product vendor odm; do
        case "$partition" in
            system) apex_root="$TF/SYSTEM/apex" ;;
            system_ext) apex_root="$TF/SYSTEM_EXT/apex" ;;
            product) apex_root="$TF/PRODUCT/apex" ;;
            vendor) apex_root="$TF/VENDOR/apex" ;;
            odm) apex_root="$TF/ODM/apex" ;;
        esac
        [[ -d "$apex_root" ]] || continue
        while IFS= read -r -d '' source; do
            count=$((count + 1))
            local_name=$(basename "$source")
            echo "=== $partition/$local_name ==="
            set +e
            "$HOST_BIN/apksigner" verify --verbose --print-certs "$source"
            apk_rc=$?
            set -e
            type=$($HOST_BIN/deapexer info --print-type "$source")
            actual="$source"
            if [[ "$type" = COMPRESSED ]]; then
                actual="$apex_work/${partition}-${local_name%.capex}.apex"
                "$HOST_BIN/deapexer" decompress --input "$source" --output "$actual"
            fi
            set +e
            "$HOST_BIN/host_apex_verifier" \
                --deapexer="$HOST_BIN/deapexer" \
                --debugfs="$(command -v debugfs)" \
                --fsckerofs="$(command -v fsck.erofs)" \
                --sdk_version=36 \
                --apex="$actual" \
                --partition_tag="$partition"
            host_rc=$?
            set -e
            printf '%s\t%s\t%s\t%s\t%s\n' "$partition" "$local_name" "$type" "$apk_rc" "$host_rc" >>"$AUDIT/apex-results.tsv"
            if [[ $apk_rc -ne 0 || $host_rc -ne 0 ]]; then
                failed=$((failed + 1))
            fi
            [[ "$actual" = "$source" ]] || rm -f "$actual"
        done < <(find "$apex_root" -maxdepth 1 -type f \( -name '*.apex' -o -name '*.capex' \) -print0 | sort -z)
    done
    printf 'apex_count=%s\napex_failed=%s\n' "$count" "$failed"
    cat "$AUDIT/apex-results.tsv"
    [[ $count -gt 0 && $failed -eq 0 ]]
}

main() {
    set -e
    : >"$SUMMARY"
    run_check payload_extract extract_payload
    run_check payload_properties payload_properties_check
    run_check payload_signature_verify payload_verify
    run_check payload_static_check payload_static_check
    run_check payload_info payload_info
    run_check apex apex_check

    local failed
    failed=$(awk -F '\t' '$2 != "passed" {count++} END {print count+0}' "$SUMMARY")
    printf 'failed_checks=%s\n' "$failed" | tee "$AUDIT/payload-apex-final.status"
    cat "$SUMMARY"
    return "$failed"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main
fi
