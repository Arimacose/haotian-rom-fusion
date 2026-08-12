#!/usr/bin/env bash
set -euo pipefail

kernel_root="${1:-device/xiaomi/haotian-kernel}"
output="${2:-${kernel_root}/prebuilt_kernel_headers.tar.gz}"
expected_commit="802915cc6b269c3bf577327c4c165c3117852ff5"
headers="${kernel_root}/kernel-headers"

if [[ ! -d "${kernel_root}/.git" ]]; then
    echo "Kernel repository is absent: ${kernel_root}" >&2
    exit 2
fi

actual_commit="$(git -C "${kernel_root}" rev-parse HEAD)"
if [[ "${actual_commit}" != "${expected_commit}" ]]; then
    echo "Unexpected kernel commit: ${actual_commit}" >&2
    echo "Expected: ${expected_commit}" >&2
    exit 3
fi

required_paths=(
    "${kernel_root}/kernel"
    "${kernel_root}/dtbo.img"
    "${kernel_root}/dtb"
    "${kernel_root}/vendor_ramdisk"
    "${kernel_root}/vendor_dlkm"
    "${kernel_root}/system_dlkm"
    "${kernel_root}/system_dlkm_flatten"
    "${headers}/linux/netfilter/xt_CONNMARK.h"
    "${headers}/linux/netfilter/xt_connmark.h"
)
for required in "${required_paths[@]}"; do
    if [[ ! -e "${required}" ]]; then
        echo "Required official-coherent kernel input is absent: ${required}" >&2
        echo "Use a case-sensitive Linux checkout for this repository." >&2
        exit 4
    fi
done

output_dir="$(dirname "${output}")"
mkdir -p "${output_dir}"
temporary="${output}.tmp.$$"
staging="$(mktemp -d "${TMPDIR:-/tmp}/haotian-kernel-headers.XXXXXX")"
trap 'rm -f "${temporary}"; rm -rf "${staging}"' EXIT

# A checkout hosted on a Windows filesystem can expose every generated header
# as executable, while the same commit on ext4 exposes regular headers as
# 0644.  Normalize permissions before archiving so the output is identical
# across both supported staging layouts.  Symlinks, if introduced upstream,
# remain symlinks and are not chmodded.
cp -a "${headers}/." "${staging}/"
find "${staging}" -type d -exec chmod 0755 {} +
find "${staging}" -type f -exec chmod 0644 {} +

LC_ALL=C tar \
    --sort=name \
    --mtime='UTC 1970-01-01' \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    --format=gnu \
    -C "${staging}" \
    -cf - . | gzip -n -9 > "${temporary}"

gzip -t "${temporary}"
archive_entries="$(tar -tzf "${temporary}")"
grep -Fxq './linux/netfilter/xt_CONNMARK.h' <<<"${archive_entries}"
grep -Fxq './linux/netfilter/xt_connmark.h' <<<"${archive_entries}"

mv -f "${temporary}" "${output}"
rm -rf "${staging}"
trap - EXIT

bytes="$(stat -c '%s' "${output}")"
digest="$(sha256sum "${output}" | cut -d' ' -f1)"
printf 'kernel_commit=%s\n' "${actual_commit}"
printf 'archive=%s\n' "${output}"
printf 'bytes=%s\n' "${bytes}"
printf 'sha256=%s\n' "${digest}"
