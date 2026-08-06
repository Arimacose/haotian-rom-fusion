# LineageOS and EvolutionX fusion plan for haotian

## Objective

Build a maintainable Android 16 class-native ROM for `haotian` that preserves the official HyperOS 3.0.304 hardware baseline while combining the strongest verified parts of the two analyzed prebuilts.

The project optimizes for reproducibility, hardware correctness, enforceable security, signed releases, and reversible A/B validation.

## Architecture

```text
LineageOS 23.2 framework and build system
                 |
                 +-- haotian device tree
                 |     +-- reconstructed CS40L26 calibration loader
                 |     +-- stock-backed display configuration
                 |     +-- Goodix-first fingerprint integration
                 |
                 +-- sm8750-common
                 |     +-- common AIDL services
                 |     +-- audio/radio/power/thermal integration
                 |
                 +-- HyperOS 3.0.304 proprietary baseline
                 |     +-- firmware
                 |     +-- vendor / odm
                 |     +-- official boot chain and DTB/DTBO
                 |
                 +-- selected EvolutionX reference material
                       +-- camera integration deltas
                       +-- display/HDR curve deltas
                       +-- optional user-facing features after hardware gates
```

## Decision 1: keep the official 3.0.304 firmware stack coherent

The Lineage OTA contains 31 firmware partitions, of which 29 match neither the analyzed 3.0.302 nor 3.0.304 firmware set. The first fusion build therefore uses the complete 3.0.304 official stack and excludes the Lineage third-firmware set.

Gate:

- all firmware hashes must match the official 3.0.304 manifest;
- boot-chain images must come from the same fastboot package;
- no 3.0.302 or OS3.1 firmware image may appear in the first build manifest.

## Decision 2: port the Lineage vibrator behavior, not its full binary

Verified behavior to reproduce:

1. discover a supported CS40L26 force-feedback input device;
2. resolve the matching sysfs input directory;
3. read `vib_cal_f0`, `vib_cal_z`, and `vib_cal_q` from `/mnt/vendor/persist/haptics`;
4. write the values to `f0_stored`, `redc_stored`, and `q_stored`;
5. enable f0 and redc compensation;
6. initialize ownership for input0, input1, and input2 nodes;
7. preserve the device-specific persist values rather than packaging generic calibration data.

The first patch retains the public service name and ABI to reduce unrelated changes. A later cleanup may move it to `aidl/vibrator` and rename the binary after a source-level comparison with the developer implementation.

## Decision 3: use stock camera compatibility first

EvolutionX ships HyperOSCamera `6.4.000270.0`; Lineage ships MiuiCamera `6.4.000250.3` plus GoogleCameraGo. Their ODM camera trees share 610 paths and 606 are byte-identical.

Implementation order:

1. extract the stock 3.0.304 camera APK, provider libraries, permissions, properties and ODM configuration;
2. compare all camera paths with EvolutionX and Lineage;
3. retain the stock 3.0.304 ABI and provider stack;
4. apply only reviewed EvolutionX APK/configuration deltas;
5. test 4K60, portrait, depth, EIS/OIS, long exposure and lens switching as independent gates.

## Decision 4: replace the Lineage display curve

The distributed Lineage configuration uses a coarse low-brightness curve, a 2-nit floor, HBM at 4475 lux, and a broad fixed HDR ratio of 8. EvolutionX has a 52-point curve and a gradual HDR ratio but is based on another vendor identity.

Implementation order:

1. extract the official 3.0.304 panel configuration;
2. identify panel ID and exact display config path;
3. use stock brightness and HBM behavior as baseline;
4. evaluate EvolutionX deltas point by point;
5. keep minimum brightness, HDR, HBM and AOD as separate parameters;
6. require rendered luminance measurements or repeatable user-observation checkpoints before accepting deltas.

## Decision 5: Goodix-first fingerprint integration

The user's handset uses Goodix. Both prebuilts include Goodix and QCOM HAL paths, but the Lineage developer reports a QCOM issue.

The first build must:

- include the official 3.0.304 Goodix HAL and calibration-related configuration;
- retain the common Xiaomi AIDL service layout only where interfaces match;
- register exactly one active fingerprint instance for the device path;
- validate enrollment, authentication, screen-off unlock, UDFPS illumination, cancellation, lockout and reboot persistence.

QCOM remains a separate compatibility track and does not block the Goodix build.

## Decision 6: create a new production security profile

EvolutionX contributes useful feature and tuning material but its analyzed build enables debug-oriented properties. Lineage has better release-key and ADB properties but boots globally permissive. The fusion release inherits neither profile directly.

Required end state:

```text
TARGET_BUILD_VARIANT=user
ro.debuggable=0
ro.adb.secure=1
SELinux=enforcing
main vbmeta flags=0
complete chained AVB descriptors
coherent build and AVB identity
project-owned production keys
```

Development builds may retain diagnostic logging, but security gates are measured again on the signed release artifact.

## Phases

### Phase 0 - freeze evidence

- Record OTA and fastboot archive hashes.
- Record public source commits.
- Preserve comparison reports and machine-readable manifests.
- Keep raw binaries out of Git.

### Phase 1 - official 3.0.304 extraction

- Download and validate the official fastboot TGZ.
- Extract boot-chain and super images.
- Produce per-image SHA-256.
- Unpack `boot`, `init_boot`, `vendor_boot` and `dtbo`.
- Extract dynamic partitions from `super`.

### Phase 2 - kernel and KMI decision

- Compare official, Lineage/Evolution 6.6.77 and third-party 6.6.143.
- Compare banners, boot headers, config, KMI, exported symbols, module CRCs, DTB/DTBO and bootconfig.
- Select a reference kernel/module combination before feature integration.

### Phase 3 - minimal hardware bring-up

- Boot framework and vendor services.
- Verify module loading and service registration.
- Integrate the CS40L26 calibration loader.
- Integrate the Goodix path.
- Keep camera, touch and display deltas minimal.

### Phase 4 - camera and display

- Reconcile stock and EvolutionX camera integration.
- Replace the Lineage brightness/HDR configuration.
- Validate all lenses, recording modes, low brightness, HBM, HDR and AOD.

### Phase 5 - touch and power

- Start from stock touchfeature behavior.
- Introduce edge suppression only after a repeatable false-touch test.
- Validate suspend, thermal, charging, idle drain and wake sources.

### Phase 6 - enforcing and AVB

- Boot enforcing and resolve denials by labeled resource and least privilege.
- Eliminate global or broad permissive workarounds.
- Build and validate the full AVB chain with project keys.
- Verify FBE, metadata encryption, KeyMint and recovery behavior.

### Phase 7 - signed release acceptance

- Build a signed `user` OTA.
- Verify OTA whole-file signature, payload hashes and partition descriptors.
- Test the published artifact rather than a debug surrogate.
- Run A/B install, rollback and data-preservation drills.

## Integration gates

| Gate | Required evidence |
|---|---|
| firmware coherence | every selected firmware hash matches 3.0.304 |
| kernel/KMI | selected modules load with expected CRCs and no unresolved symbols |
| vibrator | persist values load once, nodes accept values, effects survive reboot |
| Goodix | service registration and full enrollment/authentication cycle |
| camera | lens/mode matrix with recorded outputs and logs |
| display | low-brightness, HDR, HBM and AOD observations |
| touch | edge, keyboard, gesture and gaming matrix |
| security | enforcing, user, AVB flags 0, secure ADB, coherent identity |
| OTA | signatures, hashes, A/B install and rollback verified |

## Rollback design

Before a later device phase, preserve the active HyperOS slot and prepare verified copies of:

```text
boot
init_boot
vendor_boot
dtbo
vbmeta
vbmeta_system
super or its logical partitions
critical firmware partitions
```

The first device test targets the inactive slot only after slot layout and rollback commands are reviewed. Static work in this repository performs no device-side action.
