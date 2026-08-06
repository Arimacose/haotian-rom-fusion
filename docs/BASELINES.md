# Baselines and provenance

Generated for the `haotian` fusion project on 2026-08-06.

## Selection rule

| Layer | Selected authority | Why |
|---|---|---|
| firmware and boot chain | HyperOS 3.0.304 official fastboot | User baseline and vendor authority |
| proprietary vendor/odm | HyperOS 3.0.304 | Avoid a mixed 3.0.302/3.0.304/third-firmware stack |
| vibrator service | LineageOS 23.2 20260704 behavior | Verified persist calibration loader and sysfs ownership |
| camera | Stock 3.0.304 first, EvolutionX as comparison | EvolutionX camera APK is newer, but stock compatibility remains authoritative |
| display | Stock 3.0.304 curve, then EvolutionX deltas | Lineage three-point curve has low-brightness and HDR risks |
| fingerprint | Stock Goodix blobs plus Lineage common AIDL structure | User device uses Goodix |
| kernel reference | Official 3.0.304, shared 6.6.77, third-party 6.6.143 | Required three-way KMI decision |
| security | New production profile | Neither analyzed prebuilt meets the intended release gates |

## Official HyperOS 3.0.304 fastboot package

```text
URL: https://bkt-sgp-miui-ota-update-alisgp.oss-ap-southeast-1.aliyuncs.com/OS3.0.304.0.WOBCNXM/haotian_images_OS3.0.304.0.WOBCNXM_20260528.0000.00_16.0_cn_f685dbac4d.tgz
Expected bytes: 12202675840
Content-Type: application/x-gtar-compressed
Accept-Ranges: bytes
ETag: A3388C0571D61A1BE119D49E30D24F47-400
Last-Modified: 2026-06-11 10:10:48 GMT
OSS CRC64-ECMA: 13677892784823728727
```

Expected local path:

```text
D:\Codex\haotian-evox-0603-audit\downloads\stock-3.0.304-fastboot\haotian_images_OS3.0.304.0.WOBCNXM_20260528.0000.00_16.0_cn_f685dbac4d.tgz
```

The `.part` file is resumable. Final SHA-256 and archive-member verification are written after the expected byte count is reached.

## HyperOS 3.0.304 firmware-only package

```text
Path: D:\Codex\haotian-evox-0603-audit\downloads\stock-3.0.304-firmware\fw_haotian_haotian-ota_full-OS3.0.304.0.WOBCNXM-user-16.0-8a448bc623.zip
Bytes: 225962906
SHA-256: 4032667c4b846cd5fb630e6bb29b21b6eaf37810c62a972e1fea35d1fca210ab
MD5: 00896864d04b81c8749c056b27b9aa92
ZIP members: 38
ZIP CRC: passed
Firmware images: 31
```

This package establishes official 3.0.304 firmware hashes but does not contain `boot`, `init_boot`, `vendor_boot`, `dtbo` or `super`.

## EvolutionX 0603

```text
Path: D:\Codex\haotian-evox-0603-audit\downloads\EvolutionX-16.0-20260603-haotian-11.7-Unofficial.zip
Bytes: 5715602972
SHA-256: 7a3a739607251c7cafe5aee2c2e4590ffbb7c6366fb7fae01124a41ce0bb8894
MD5: 9de3831a5f65ae3cdf3be1706d0ee376
Payload SHA-256: 59b57e7cce7ed2e640e8fef2e6ab6252048305e903c6c3212461275ff3580bce
SDK: 36
SPL: 2026-05-01
Vendor base identity: OS3.0.302.0.WOBCNXM
```

Security-relevant properties from the artifact:

```text
build type: userdebug
tags: test-keys
ro.debuggable: 1
ro.adb.secure: 0
main vbmeta flags: 3
SELinux: globally enforcing with several named permissive domains
```

## LineageOS 23.2 20260704

```text
Path: D:\Codex\haotian-evox-0603-audit\downloads\lineageos-23.2-20260704\lineage-23.2-20260704-UNOFFICIAL-haotian.zip
Bytes: 4538160145
SHA-256: 3f2308e8df0a82b7a5feef2dab5b40c75897242a9c3d98d87387e8cc2d3e5191
MD5: 2c9f298b70e6fa5c92db391aab929a71
Payload SHA-256: 7c243beba7b082c97921164259d26b36f265da7b35288b58ef8d8559be9c376c
SDK: 36
SPL: 2026-06-01
Advertised vendor identity: OS3.1.260309
```

Security-relevant properties from the artifact:

```text
build type: userdebug
tags: release-keys
ro.debuggable: 0
ro.adb.secure: 1
main vbmeta flags: 3
SELinux bootconfig: globally permissive
```

## Shared Lineage/Evolution kernel

```text
Kernel bytes: 36456960
Kernel SHA-256: 99485b0132e3aa28f4e965119591c8149fe3c20e7e0fd10d753ef014a582472e
Banner: Linux 6.6.77 android15-8, 4K pages, Clang 18
Relationship: byte-identical between the two prebuilts
```

The five inspected haptic modules and `Hapticsconfig.xml` are also identical. The Lineage vibration improvement therefore comes from the service and init integration.

## Pinned public source

| Repository | Branch | Commit |
|---|---|---|
| `Evolution-X/manifest` | `bka` | `0035c57e03e828999cd0c2be02ff64607c3ba649` |
| `rep1ace/device_xiaomi_haotian` | `lineage-23.2` | `483ace84ff3f8ef9cf0438626ce221022d23f433` |
| `rep1ace/device_xiaomi_sm8750-common` | `lineage-23.2` | `6f633ec0919fdfe3f8d307e8ab7770c1c1a90696` |

Both local heads match the current remote branch heads at the time of this snapshot. Exact GitHub code searches for the distributed calibration-loader strings returned no public result, so the first patch in this repository reconstructs the observed behavior against the pinned public haotian tree.
