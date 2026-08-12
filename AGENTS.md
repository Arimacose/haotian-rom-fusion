# Project working rules

## Scope

This repository manages source, reproducible metadata, comparison logic, patches, validation gates, and release documentation for `haotian` ROM adaptation.

## Device boundary

- Keep all work offline until a task explicitly enters a controlled device-validation phase.
- Do not issue `adb`, `fastboot`, EDL, recovery, slot-switch, reboot, wipe, format, or flash commands as part of static-analysis work.
- Before a later device phase, record the active slot, partition hashes, boot state, rollback material, and acceptance criteria.

## Artifact handling

- Use `D:\Codex\haotian-rom-fusion-build` for the current official dump,
  proprietary staging and future build-adjacent artifacts. Keep the historical
  EvolutionX audit under `D:\Codex\haotian-evox-0603-audit` read-only.
- Keep OTA, firmware, images, blobs, APKs, modules, keys, persist data, and build output outside Git.
- Commit hashes and compact evidence only.
- Verify every downloaded archive before extraction and every selected baseline before comparison.
- Preserve the official HyperOS 3.0.304 artifact as read-only input.

## Active product policy

- YAAP `sixteen` is the Android ROM/platform base; preserve its AOSP-first
  product and framework inheritance.
- Treat HyperOS 3.0.304 as the authoritative firmware, vendor/odm and proprietary hardware baseline.
- Import Lineage-named components only when a concrete device HAL ABI, CAF
  project or policy dependency requires them. Keep LineageOS images, framework,
  Settings, SystemUI, Updater and product inheritance outside the YAAP product.
- Retain EvolutionX, LineageOS and DerpFest images as read-only comparison and
  runtime evidence rather than product bases.
- Keep the current stage at source closure and static validation. Enter build
  work only in an explicitly requested build phase; enter runtime work only in
  a separately requested controlled validation phase.
- Keep feature enablement separate from production hardening.
- Production output requires `user`, SELinux enforcing, coherent identity, production keys, and a complete AVB chain.

## Git workflow

- Use `agent/<description>` branches for implementation work.
- Stage explicit paths and keep commits focused.
- Push large-artifact metadata only after local hashes pass.
- Open draft pull requests for review; merge after checks and evidence are complete.
- Never commit credentials, tokens, signing keys, proprietary payloads, or per-device calibration values.

## Validation

- Python scripts must pass `python -m py_compile`.
- PowerShell scripts must parse successfully in Windows PowerShell 5.1 and PowerShell 7 syntax where practical.
- JSON must parse and preserve UTF-8.
- Patches must pass `git apply --check` against their pinned source commit.
- Reports must separate static evidence, source inference, developer-reported behavior, and later runtime acceptance.
