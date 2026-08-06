# Security and release gates

## Artifact facts

The analyzed EvolutionX and LineageOS packages are development-oriented reference artifacts. The fusion project creates a separate production profile rather than copying either security configuration.

| Property | EvolutionX 0603 | LineageOS 0704 | Fusion production target |
|---|---|---|---|
| build variant | userdebug | userdebug | user |
| build tags | test-keys | release-keys | project release-keys |
| `ro.debuggable` | 1 | 0 | 0 |
| `ro.adb.secure` | 0 | 1 | 1 |
| SELinux | enforcing plus named permissive domains | global permissive | enforcing with no permissive domains |
| main vbmeta flags | 3 | 3 | 0 |
| full GMS | present with spoof framework | absent | explicit build choice |
| identity | Pixel/Evolution and Xiaomi mixed signals | Xiaomi fingerprint and Lineage AVB mixed signals | one coherent project identity |

## Gate S1 - build identity

- `TARGET_BUILD_VARIANT=user` for the release candidate.
- `ro.secure=1`, `ro.debuggable=0`, `ro.force.debuggable=0`, `ro.adb.secure=1`.
- Build fingerprint, description, AVB properties and OTA metadata describe the same build.
- No `eng` identity appears in release boot properties or AVB descriptors.

## Gate S2 - SELinux

- Kernel command line and bootconfig select enforcing.
- `getenforce` reports Enforcing in the later runtime phase.
- Compiled policy contains no `typepermissive` entry for project domains.
- Denials are resolved with labeled resources and least-privilege rules.
- Broad `sysfs` access in the reconstructed vibrator patch is narrowed after the exact CS40L26 genfs labels are confirmed.

## Gate S3 - AVB

- Main vbmeta and chained vbmeta images use flags `0`.
- Every intended partition has a descriptor.
- Rollback indexes and locations are documented and internally consistent.
- Public keys extracted from all vbmeta images match the project key manifest.
- The signed release package is verified again after publication.

## Gate S4 - signing keys

- Generate independent platform, media, shared, networkstack, OTA and AVB keys.
- Store private material outside the Git repository.
- Commit only public certificate fingerprints and key rotation policy.
- Keep development and production keys separate.
- Verify APK signer continuity for privileged applications.

## Gate S5 - ADB and debugging

- Release adbd requires authentication.
- Root adbd service paths are absent from the release ramdisk.
- USB defaults exclude `adb` until the user enables developer options.
- Debug daemons, test services, vendor log collectors and permissive domains are excluded from the release product.

## Gate S6 - encryption and KeyMint

- Preserve the stock-backed FBE and metadata-encryption configuration.
- Validate wrapped-key mode, inline encryption, credential-encrypted and device-encrypted storage.
- Validate lock-screen creation, reboot unlock, recovery access and data preservation.
- Record KeyMint and boot-state outputs separately from software property checks.

## Gate S7 - environment-risk reporting

Release notes must distinguish:

- OS security posture;
- unlocked bootloader hardware state;
- root or module state;
- Google service configuration;
- application-specific and server-side risk decisions.

A passing software property check does not replace hardware attestation evidence.

## Gate S8 - signed OTA acceptance

- Whole-file OTA signature verifies.
- Payload file and metadata hashes match.
- Partition list matches the approved manifest.
- A/B update reaches the expected target slot.
- Rollback to the preserved slot succeeds in the controlled validation phase.
- The final published artifact, rather than a debug build, completes the acceptance matrix.
