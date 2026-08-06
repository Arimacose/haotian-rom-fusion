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
