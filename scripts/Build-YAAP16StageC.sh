#!/usr/bin/env bash
set -uo pipefail

ROOT=/home/arima/android/yaap16
LOG_ROOT=/mnt/d/Codex/haotian-rom-fusion-build/logs/stage-c-builds
ATTEMPT=${1:?usage: run_stage_c_frozen_release.sh ATTEMPT}
BUILD_EPOCH=${BUILD_EPOCH:-1786625277}
BUILD_NUMBER_VALUE=${BUILD_NUMBER_VALUE:-haotian.stagec.20260813.1}
LOG="$LOG_ROOT/yaap16-stage-c-frozen-release-attempt${ATTEMPT}.log"
STATUS="$LOG_ROOT/yaap16-stage-c-frozen-release-attempt${ATTEMPT}.status"
COMMAND="$LOG_ROOT/yaap16-stage-c-frozen-release-attempt${ATTEMPT}.command.txt"
RESOURCE="$LOG_ROOT/yaap16-stage-c-frozen-release-attempt${ATTEMPT}.resources.txt"

mkdir -p "$LOG_ROOT"
cd "$ROOT" || exit 97
export TARGET_BUILD_GAPPS=true
export BUILD_DATETIME="$BUILD_EPOCH"
export BUILD_NUMBER="$BUILD_NUMBER_VALUE"
export BUILD_USERNAME=android-build
export BUILD_HOSTNAME=haotian-builder

start_epoch=$(date +%s)
start_iso=$(date --iso-8601=seconds)
before_out_bytes=$(du -sb out 2>/dev/null | awk '{print $1}' || printf '0')
before_free_bytes=$(df --output=avail -B1 "$ROOT" | tail -1 | tr -d ' ')

set +u
source build/envsetup.sh
lunch yaap_haotian-bp4a-userdebug
set -u

printf 'TARGET_BUILD_GAPPS=true BUILD_DATETIME=%q BUILD_NUMBER=%q m -j16 bacon target-files-package\n' \
    "$BUILD_DATETIME" "$BUILD_NUMBER" >"$COMMAND"
{
    echo "start=$start_iso"
    echo "build_epoch=$BUILD_DATETIME"
    echo "build_number=$BUILD_NUMBER"
    echo "memory_before:"
    free -b
    echo "swap_before:"
    swapon --show --bytes || true
    echo "filesystem_before:"
    df -B1 "$ROOT"
} >"$RESOURCE"

set +e
m -j16 bacon target-files-package 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e

end_epoch=$(date +%s)
end_iso=$(date --iso-8601=seconds)
elapsed=$((end_epoch - start_epoch))
after_out_bytes=$(du -sb out 2>/dev/null | awk '{print $1}' || printf '0')
after_free_bytes=$(df --output=avail -B1 "$ROOT" | tail -1 | tr -d ' ')

if [[ $rc -eq 0 ]]; then result=passed; else result=failed; fi
{
    echo "result=$result"
    echo "exit_code=$rc"
    echo "elapsed_seconds=$elapsed"
    echo "start=$start_iso"
    echo "end=$end_iso"
    echo "target_build_gapps=true"
    echo "variant=yaap_haotian-bp4a-userdebug"
    echo "jobs=16"
    echo "targets=bacon,target-files-package"
    echo "build_epoch=$BUILD_DATETIME"
    echo "build_number=$BUILD_NUMBER"
    echo "out_bytes_before=$before_out_bytes"
    echo "out_bytes_after=$after_out_bytes"
    echo "filesystem_free_bytes_before=$before_free_bytes"
    echo "filesystem_free_bytes_after=$after_free_bytes"
    echo "log=$LOG"
} >"$STATUS"
{
    echo "end=$end_iso"
    echo "memory_after:"
    free -b
    echo "swap_after:"
    swapon --show --bytes || true
    echo "filesystem_after:"
    df -B1 "$ROOT"
} >>"$RESOURCE"

exit "$rc"
