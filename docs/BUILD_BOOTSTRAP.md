# EvolutionX `bka` build bootstrap for haotian

## Why `bka`

The analyzed EvolutionX 0603 artifact identifies itself as EvolutionX `16.0`
with Android build ID `BP4A.251205.006`. The EvolutionX `bka` manifest uses the
`bp4a` lunch family, while its newer `cnb` branch uses `cp2a`. Reproducing the
0603 feature baseline therefore starts from `bka`; moving to `cnb` is a later,
separately measured platform migration.

This selection creates the intended fusion boundary:

- EvolutionX `bka` supplies the Android 16 platform and Evolution features;
- the pinned LineageOS 23.2 haotian/sm8750 trees supply the public device source;
- the reconstructed patches supply the Lineage 0704 vibration behavior and a
  release-oriented security profile;
- HyperOS 3.0.304 supplies firmware, proprietary components, boot-chain facts,
  display/camera authority and the official kernel comparison point.

## Host layout

Run the Android build inside Linux on a case-sensitive filesystem. The source,
download cache, ccache and output may live in a WSL2 virtual disk stored on D,
while the audit artifacts stay under:

```text
D:\Codex\haotian-evox-0603-audit
```

The Git project itself remains:

```text
D:\Codex\haotian-rom-fusion
```

The reproducible proprietary staging root is already populated on D:

```text
D:\Codex\haotian-rom-fusion-build\source
D:\Codex\haotian-rom-fusion-build\source\vendor\xiaomi\haotian
D:\Codex\haotian-rom-fusion-build\source\vendor\xiaomi\sm8750-common
```

## Initialize and sync

```bash
mkdir -p ~/android/evolution-haotian
cd ~/android/evolution-haotian

repo init -u https://github.com/Evolution-X/manifest -b bka --git-lfs
git -C .repo/manifests checkout 0035c57e03e828999cd0c2be02ff64607c3ba649
mkdir -p .repo/local_manifests
cp /mnt/d/Codex/haotian-rom-fusion/manifests/haotian-bka.xml \
  .repo/local_manifests/haotian.xml
repo sync -c -j"$(nproc --all)" --force-sync --no-clone-bundle --no-tags
repo manifest -r -o resolved-haotian-bka.xml
```

The local manifest pins exact commits rather than following moving device-tree
heads. The resolved manifest records every project commit used by the sync.
Updating the platform or either device tree requires an explicit manifest and
evidence change.

## Apply the fusion patch stack

```bash
git -C device/xiaomi/haotian am \
  /mnt/d/Codex/haotian-rom-fusion/patches/0001-haotian-cs40l26-calibration-loader.patch
git -C device/xiaomi/haotian am \
  /mnt/d/Codex/haotian-rom-fusion/patches/0002-haotian-disable-adb-insecure.patch
git -C device/xiaomi/sm8750-common am \
  /mnt/d/Codex/haotian-rom-fusion/patches/0003-sm8750-production-avb-profile.patch
git -C device/xiaomi/sm8750-common am \
  /mnt/d/Codex/haotian-rom-fusion/patches/0004-sm8750-3.0.304-soterservice-source.patch
```

## Inputs still staged locally

The two proprietary trees can be regenerated directly from the verified 3.0.304
EROFS and firmware inputs:

```powershell
powershell.exe -ExecutionPolicy Bypass -File `
  D:\Codex\haotian-rom-fusion\scripts\Generate-ProprietaryTree.ps1

# Re-run source, patch, list-output and tree-size checks without recopying blobs
powershell.exe -ExecutionPolicy Bypass -File `
  D:\Codex\haotian-rom-fusion\scripts\Generate-ProprietaryTree.ps1 `
  -SkipExtraction
```

The completed generation contains 3,046 files in `vendor/xiaomi/haotian` and
1,779 files in `vendor/xiaomi/sm8750-common`, totaling 6,247,299,804 bytes.
All 3,011 device entries, 1,775 common entries and 31 firmware entries have an
output file. Copy these two generated directories into the case-sensitive full
Android source tree before building:

```bash
mkdir -p vendor/xiaomi
cp -a /mnt/d/Codex/haotian-rom-fusion-build/source/vendor/xiaomi/haotian \
  vendor/xiaomi/
cp -a /mnt/d/Codex/haotian-rom-fusion-build/source/vendor/xiaomi/sm8750-common \
  vendor/xiaomi/
```

Before the first compile, place or generate these source-tree paths without
committing their binary contents to this Git project:

```text
device/xiaomi/haotian-kernel
vendor/xiaomi/haotian
vendor/xiaomi/sm8750-common
vendor/haotian/security/avb.pem
```

The local manifest now pins Crisp-los kernel prebuilt commit
`802915cc6b269c3bf577327c4c165c3117852ff5`. Its kernel, DTB concatenation,
DTBO, vendor-ramdisk modules, vendor-DLKM modules, both system-DLKM layouts and
load lists match official 3.0.304. Clone it only inside the case-sensitive
Linux build filesystem because its generated kernel headers contain names that
collide on a case-insensitive Windows checkout. The proprietary tree generation
stage is complete; the full Soong/ELF/VINTF checks run after it enters the
platform source. The AVB private key is local-only; its public-key digest and
signing policy are the reviewable evidence.

The selected public repository contains the generated `kernel-headers/` tree
but not the archive referenced by `TARGET_PREBUILT_KERNEL_HEADERS`. Generate it
deterministically after `repo sync`:

```bash
bash /mnt/d/Codex/haotian-rom-fusion/scripts/Prepare-KernelHeaders.sh \
  device/xiaomi/haotian-kernel
```

The helper verifies the pinned commit and checks that both uppercase and
lowercase netfilter header names survived checkout before writing
`device/xiaomi/haotian-kernel/prebuilt_kernel_headers.tar.gz`. The archive uses
sorted paths, fixed ownership and timestamps, and `gzip -n`, so identical input
produces identical output.

The helper was executed twice against a D-drive directory with Windows
per-directory case sensitivity enabled. Both runs produced:

```text
bytes: 1826624
SHA-256: 43315426829f37bb0665349a7574d46e896ece8e11d184aada3d3a3a7ff0bc43
```

## Configure and build

```bash
source build/envsetup.sh
lunch lineage_haotian-bp4a-userdebug
m evolution
```

The first successful `userdebug` compile establishes source completeness and
does not satisfy the release gate. The acceptance artifact is rebuilt as
`lineage_haotian-bp4a-user`, signed with the project identity, inspected for AVB
flags and descriptors, then run through the A/B test matrix.

## Pre-build gates

1. official 3.0.304 archive and every selected image have recorded hashes;
2. vendor extraction has zero missing mandatory blobs: 4,817/4,817 list outputs;
3. kernel, modules, DTB and DTBO resolve to pinned commit `802915c`, and the
   deterministic prebuilt-header archive passes `gzip -t`;
4. all four patches pass against their pinned commits;
5. `WITH_ADB_INSECURE` is absent;
6. main vbmeta uses flags `0` and no AOSP test-key path remains;
7. main vbmeta describes `pvmfw`, `mi_ext`, and `system_dlkm` consistently with
   the selected OTA and dynamic-partition layout;
8. proprietary blobs, output files and private keys remain outside Git.
