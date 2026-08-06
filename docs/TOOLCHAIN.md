# Local toolchain provenance

Large and executable tooling remains under the D-drive audit root and is referenced by pinned path and SHA-256.

## Android boot image tools

```text
unpack_bootimg.py
source: AOSP platform/system/tools/mkbootimg
local: D:\Codex\haotian-evox-0603-audit\tools\mkbootimg\unpack_bootimg.py
```

## AVB

```text
avbtool.py
source: AOSP platform/external/avb
local: D:\Codex\haotian-evox-0603-audit\tools\avb\avbtool.py
```

## Payload extraction

```text
payload-dumper-go 1.3.0
local: D:\Codex\haotian-evox-0603-audit\tools\payload-dumper-go-1.3.0\payload-dumper-go.exe
```

## Dynamic partition tools

Pinned source repository:

```text
repository: https://github.com/Rprop/aosp15_partition_tools
commit: 5e92a5d504de33414318ced8bad5507440bb8c30
declared AOSP base: android-15.0.0_r25
local: D:\Codex\haotian-evox-0603-audit\tools\aosp15_partition_tools-5e92a5d
```

The repository documents its build inputs as AOSP `system/extras/partition_tools`, `system/core/libsparse`, and `external/e2fsprogs/contrib/android`. The upstream AOSP implementation is maintained in `platform/system/extras/partition_tools`.

| Tool | Bytes | SHA-256 |
|---|---:|---|
| `lpunpack.exe` | 1991680 | `dc53c92ee00ba5774fa5cc38d98afa979ebc711d398e97de445d941b0b3dc58d` |
| `lpdumps.exe` | 3684352 | `1dc8385534cd9a849750e42be04ce0af2af1ce0c89074e8b88947cbd36035d23` |
| `simg2img.exe` | 525824 | `5d840c8352d3790712b68077ab5e224d190737dd6add80541e6a871b6b205546` |

Validation strategy:

1. pin the tool repository commit and local SHA-256;
2. record the `lpdumps` metadata before extraction;
3. hash every extracted logical partition;
4. identify each filesystem independently;
5. reconcile official firmware items with the separately verified 3.0.304 firmware package;
6. preserve raw images outside Git.

## Filesystem inspection

WSL2 Ubuntu packages installed for read-only filesystem inspection:

```text
android-sdk-libsparse-utils  1:34.0.4-1build3
erofs-utils                  1.7.1-1build2
```

| WSL tool | SHA-256 |
|---|---|
| `/usr/bin/simg2img` | `f26366409fd82fdf3b0125e30db784caa5199cb42211f92abfc2de9d6f56c3a3` |
| `/usr/bin/fsck.erofs` | `9df25cc289bbd04f1995383aa6a5a235757ef895a6085b26d0b63eb45718a448` |
| `/usr/bin/dump.erofs` | `9b4741d29779acb3a8e8eb938293b72755d9a5b413ed96d085678c7c0424ffba` |

The environment also contains `e2fsck` and `debugfs` for ext4 inspection. All mount and extraction paths remain under the D-drive audit work directory.
