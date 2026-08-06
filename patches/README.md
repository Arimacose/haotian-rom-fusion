# Patches

Patches are generated against pinned public source commits and validated with `git apply --check` in CI.

## 0001 - CS40L26 calibration loader

Target:

```text
repository: rep1ace/device_xiaomi_haotian
branch: lineage-23.2
base: 483ace84ff3f8ef9cf0438626ce221022d23f433
```

The patch reconstructs behavior verified in the distributed LineageOS 0704 vibrator ELF and init rc:

- read f0, redc and q calibration values from persist;
- resolve the sysfs directory for the selected CS40L26 input device;
- write stored calibration values and enable compensation;
- initialize ownership for the observed input0/input1/input2 nodes;
- preserve the existing public service name and AIDL ABI.

The patch contains no calibration value from a physical handset.

## 0002 - remove insecure ADB bring-up override

Target:

```text
repository: rep1ace/device_xiaomi_haotian
branch: lineage-23.2
base: 483ace84ff3f8ef9cf0438626ce221022d23f433
```

This removes the unconditional `WITH_ADB_INSECURE := true` product override.
Debug access for early bring-up is then an explicit build choice rather than a
property embedded in every haotian product.

## 0003 - production AVB profile

Target:

```text
repository: rep1ace/device_xiaomi_sm8750-common
branch: lineage-23.2
base: 6f633ec0919fdfe3f8d307e8ab7770c1c1a90696
```

This patch:

- changes main vbmeta flags from `3` to `0`;
- adds a main vbmeta signing algorithm and project-key path;
- replaces AOSP test-key paths for boot, recovery and `vbmeta_system`;
- leaves rollback-index values fixed for later reconciliation with the official
  3.0.304 boot-chain manifest.

The referenced `vendor/haotian/security/avb.pem` is local build input and is
excluded from this repository.

This patch establishes the signing and flags profile. The official extraction
later confirmed that release vbmeta must also describe `pvmfw`, `mi_ext`, and
`system_dlkm`; that partition/OTA integration remains in the security issue and
is a separate completion gate.
