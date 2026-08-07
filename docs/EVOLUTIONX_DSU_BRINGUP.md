# EvolutionX direct multi-partition DSU bring-up

## Active direction

The active ROM platform is now EvolutionX `bka`. LineageOS is retained only as
historical comparison evidence; it is not the ROM base and no LineageOS image is
present in this DSU artifact.

The first runtime artifact is deliberately narrower than a flashable ROM. It
boots three EvolutionX upper partitions over the installed HyperOS 3.0.304
hardware stack:

```text
EvolutionX 0603: system + system_ext + product
HyperOS 3.0.304 host: vendor + odm + mi_ext + firmware
Installed host: boot + vendor_boot + DTB/DTBO + 6.6.143 kernel + DLKM
DSU sandbox: temporary userdata
```

This profile answers the first useful question: whether the EvolutionX Android
framework, SystemUI, settings, apps and HyperOSCamera integration can operate
against the verified 3.0.304 hardware implementation without flashing a slot.

## Static DSU support evidence

The official 3.0.304 image contains:

- `system/bin/gsid`;
- `system/bin/gsi_tool`;
- `system/priv-app/DynamicSystemInstallationService`;
- logical, first-stage-mounted `system`, `system_ext`, `product`, `vendor`,
  `odm`, `system_dlkm` and `vendor_dlkm` entries in `fstab.qcom`;
- GSI AVB key paths on the `system` fstab entry.

AOSP supports ZIP-based multi-partition DSU from Android 11. The ZIP members are
partition images at the archive root. This profile uses exactly:

```text
system.img
system_ext.img
product.img
```

No README, manifest or script is placed inside the ZIP; all audit metadata is a
sidecar so the DSU service sees only partition images.

## Why the first profile is `upper3`

Including EvolutionX 0603 `vendor` and `odm` would reproduce its 3.0.302-derived
hardware stack. That would immediately reintroduce the already measured
302/304 mixed-stack variable. The host is already HyperOS 3.0.304, so leaving
`vendor`, `odm`, `mi_ext` and firmware on the host isolates the compatibility
boundary we intend to test.

`vendor_dlkm` and `system_dlkm` are also omitted. DSU keeps the installed boot
kernel; this device currently runs a third-party 6.6.143 kernel. Replacing module
partitions with the EvolutionX 6.6.77-era sets would create a separate KMI and
module-load experiment before the upper Android stack has even booted.

## Host SPL gate and AVB footer rebuild

The EvolutionX upper images advertise `2026-05-01` in their AVB property
descriptors. Official HyperOS 3.0.304 advertises `2026-06-01`. AOSP DSU applies a
security-patch rollback check, so the unmodified 0603 images can be rejected as
older than the host.

The builder therefore performs a test-only footer transformation on copies:

1. verify the source size and SHA-256;
2. record the source AVB descriptors and filesystem root digest;
3. remove the old AVB footer;
4. rebuild a standalone SHA-256 hashtree footer with the same salt and partition
   size;
5. change only the partition AVB security-patch property to `2026-06-01`;
6. omit FEC because the local Windows AVB toolchain does not include the AOSP
   `fec` helper;
7. verify the rebuilt hashtree;
8. require the source and staged root digests to be identical.

The ext4 filesystem payload stays unchanged. The sidecar manifest records that
the runtime build properties still originate from the 0603 image; the SPL
override is an installer-gate fixture, not a production security claim.

The staged images use `Algorithm: NONE`. This is an unlocked-bootloader debug
profile and is not a release-signing design. A production artifact needs project
AVB keys accepted by the first-stage ramdisk, coherent rollback indices, FEC as
selected by the product policy and a complete signed chain.

## Reproducible build

Run from the repository root:

```powershell
python .\scripts\Build-MultiPartitionDsu.py `
  --config .\configs\evolutionx-dsu-upper3.json `
  --avbtool D:\Codex\haotian-evox-0603-audit\tools\avb\avbtool.py `
  --output-dir D:\Codex\haotian-evox-0603-audit\dsu `
  --clean
```

The builder validates the source images, rebuilds footers, creates a Zip64 DSU
archive with fixed member timestamps, reopens the ZIP, checks its CRCs, hashes
every decompressed member and writes:

```text
<package>.zip
<package>.zip.sha256
<package>.zip.manifest.json
```

Staged images are removed after successful verification unless
`--keep-staging` is supplied. This avoids retaining another 4.86 GiB image copy.

## Generated artifact

The first artifact has been built twice from clean staging. Both runs produced
the same byte-for-byte package:

```text
D:\Codex\haotian-evox-0603-audit\dsu\evolutionx-0603-upper3-host304\EvolutionX-16.0-20260603-haotian-upper3-host304-mpDSU.zip
```

```text
Size:    2,848,637,046 bytes
SHA-256: a0afebb0e8c03bfa68e2834ddd78afdc3c69eb6602485cbd248ad20d8f39e901
```

The raw member total is 5,223,079,936 bytes. ZIP validation reopened the package,
passed every CRC and hashed every decompressed member:

| Member | Raw bytes | Compressed bytes | SHA-256 |
|---|---:|---:|---|
| `system.img` | 913,694,720 | 483,239,108 | `333f3a8adc7296d9c36b03c63dc8b4bf6c422cd2ed31c46c785cbed22e50543f` |
| `system_ext.img` | 1,006,436,352 | 445,199,595 | `a94c2614763849722981c5c2ebc9c2ad8c839b40876ad2b4a150da1cf36f3caa` |
| `product.img` | 3,302,948,864 | 1,920,197,867 | `80e3a28cda97d744d5120a4fbb33b658c88280f26a627896532417c4557372e9` |

The complete local manifest and checksum are beside the ZIP. A compact,
non-proprietary evidence record is tracked at
`evidence/evolutionx-upper3-dsu.json`. Runtime validation remains
`not_started`; no device command was issued while producing this artifact.

## Runtime scope

The first boot is intended to test:

1. boot completion and SystemUI stability;
2. touch, rotation, display refresh modes and brightness control;
3. USB debugging visibility in the DSU instance;
4. Wi-Fi, Bluetooth, mobile network, audio input/output and sensors;
5. Goodix enrollment, authentication and FOD illumination;
6. HyperOSCamera launch, all physical lenses, photo, 30/60 fps video, HDR and
   portrait;
7. vibration, charging state, sleep/wake and thermal service registration;
8. EvolutionX settings and feature stability.

Results apply to `EvolutionX upper3 + HyperOS 3.0.304 host + installed 6.6.143
kernel`. They do not establish the behavior of the original 0603 vendor/odm,
the stock 6.6.77 module set, a production AVB chain or banking/game integrity.

## First-session operating constraints

- Allocate at least 25 GiB of free `/data` space for 4.86 GiB of raw DSU images,
  a 12-16 GiB sandbox userdata and installer overhead.
- Keep sticky mode off for the first session.
- Record the host slot, verified-boot state, DSU service state and free space
  before installation.
- Reboot back to the host after the first bounded test session and discard the
  DSU only after logs have been copied.
- Device commands begin in a later explicitly confirmed runtime-validation
  phase; this build phase performs no ADB, reboot, slot or partition operation.

## Gate to the next package

If `upper3` reaches the launcher and the core hardware services register, the
next DSU profile can add one variable at a time:

1. official 3.0.304 `vendor` and `odm` explicitly packaged for a self-contained
   five-partition profile;
2. a 3.0.304-rebased EvolutionX vendor/odm tree;
3. the official-coherent 6.6.77 boot and DLKM set in a later flashable test
   artifact;
4. production identity, SELinux and signing hardening after hardware bring-up.
