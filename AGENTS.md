# Project working rules

## Scope

This repository manages source, reproducible metadata, comparison logic, patches, validation gates, and release documentation for `haotian` ROM adaptation.

## Device boundary

- Keep all work offline until a task explicitly enters a controlled device-validation phase.
- Do not issue `adb`, `fastboot`, EDL, recovery, slot-switch, reboot, wipe, format, or flash commands as part of static-analysis work.
- Before a later device phase, record the active slot, partition hashes, boot state, rollback material, and acceptance criteria.

## Artifact handling

- Use `D:\Codex\haotian-evox-0603-audit` for downloaded and extracted artifacts.
- Keep OTA, firmware, images, blobs, APKs, modules, keys, persist data, and build output outside Git.
- Commit hashes and compact evidence only.
- Verify every downloaded archive before extraction and every selected baseline before comparison.
- Preserve the official HyperOS 3.0.304 artifact as read-only input.

## Active product policy

- EvolutionX `bka` is the sole Android ROM/platform base.
- Treat HyperOS 3.0.304 as the authoritative firmware, vendor/odm and proprietary hardware baseline.
- Retain LineageOS only as read-only comparison evidence; do not use its images or make it the product base.
- Start runtime bring-up with a non-flashing EvolutionX `system` + `system_ext` + `product` DSU profile over the installed 3.0.304 hardware stack.
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
