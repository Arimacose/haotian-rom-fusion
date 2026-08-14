# YAAP 16 Stage D r2 runtime report

## Current state

- r1 real-device result: boot timeout after all five DSU partitions mounted.
- Root cause: `audiohalservice.qti` could not load mandatory `sthal` because `android.hardware.soundtrigger3-V1-ndk.so` was absent.
- Source cause: `libsoundtriggerhal.qti.so;DISABLE_DEPS` suppressed the ELF dependency closure.
- Source fix commit: `5ec5c607cde8fc32f695a0c734e75b186738ff75` on `agent/audio-vintf-soundtrigger-fix`.
- r2 OTA incremental: `haotian.staged.20260814.2`.
- r2 DSU SHA-256: `6c84ad0eb7f50874a5152a38461ec9832f98159446ce68d8e641308fc25f8ad2`.
- Offline core audit: 14/14 passed.
- Payload/APEX audit: 6/6 passed.
- Audio VINTF and SoundTrigger closure gates: passed.
- Independent DSU raw-ext4/e2fsck/AVB/hash audit: passed.
- r2 real-device acceptance: pending.

## Runtime acceptance gates

1. Enable and verify the temporary Wi-Fi global proxy before DSU entry.
2. Verify `system_gsi`, `system_ext_gsi`, `product_gsi`, `vendor_gsi`, and `odm_gsi` are the active mounts.
3. Require `sys.boot_completed=1` and `init.svc.bootanim=stopped`.
4. Require stable `audiohalservice.qti`, `audioserver`, and `system_server` PIDs with no repeating tombstones.
5. Execute every DSU-testable core-function check and record measured results.
6. Exit DSU and restore the phone proxy plus temporary relay to the pre-entry state.

## Artifact paths

- Package: `D:\Codex\haotian-rom-fusion-build\dsu\yaap16-staged-upper5-host304-soundtrigger-r2\YAAP-16-20260814-haotian-upper5-host304-soundtrigger-r2-mpDSU.zip`
- Machine-readable evidence: `D:\Codex\haotian-rom-fusion\evidence\yaap16-stage-d-r2-soundtrigger.json`
- Failure report: `D:\Codex\haotian-rom-fusion-build\logs\stage-d-dsu-runtime\20260814-second-yaap-upper5\boot-observation-01\BOOT_FAILURE_ROOT_CAUSE.md`
