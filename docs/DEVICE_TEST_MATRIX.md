# Controlled device acceptance matrix

This matrix is prepared for a later A/B validation phase. The current project phase remains offline and performs no device-side commands.

## Entry conditions

- Official 3.0.304 archive, extracted images and hashes verified.
- Active and inactive slots identified.
- Current HyperOS boot-chain and logical-partition rollback material preserved.
- Fusion images pass offline AVB, filesystem and manifest checks.
- Stop conditions and slot-recovery procedure reviewed.

## Boot and storage

| Test | Pass evidence |
|---|---|
| first boot | boot animation, SystemUI, launcher and setup complete |
| second boot | no new critical service failures |
| FBE | device-encrypted and credential-encrypted storage mount correctly |
| metadata encryption | userdata and metadata state match the approved fstab |
| slot state | expected slot is active and rollback slot remains intact |
| recovery | recovery starts and sees the expected encrypted state |

## Vibrator

| Test | Pass evidence |
|---|---|
| calibration loader | logs show f0, redc and q loaded from persist |
| sysfs | stored values and compensation flags reflect the loader |
| boot persistence | values remain correct after cold and warm reboot |
| effects | click, tick, thud, notification, alarm and long vibration work |
| amplitude | light, medium and strong levels remain ordered |
| repeated effects | no stuck state after rapid cancellation and replay |

## Goodix fingerprint

| Test | Pass evidence |
|---|---|
| service | AIDL instance and vendor HAL register once |
| enrollment | full enrollment completes after reboot and clean setup |
| authentication | lock-screen success rate recorded over repeated attempts |
| screen off | UDFPS wakes and authenticates from the intended display state |
| illumination | HBM/UDFPS overlay aligns with the sensor |
| cancellation | canceled sessions exit cleanly |
| lockout | timed and permanent lockout transitions follow Android behavior |

## Camera

| Lens or mode | Required checks |
|---|---|
| main | preview, photo, video, focus, OIS/EIS |
| ultrawide | preview, photo, video, lens transition |
| telephoto | preview, photo, video, stabilization |
| front | photo, video, rotation and beauty pipeline |
| portrait | depth map, subject separation, saved result |
| night | capture completion and saved image |
| 4K60 | codec profile, sustained recording and audio sync |
| slow motion | advertised rates and saved playback |
| third-party API | Camera2 enumeration and representative application capture |

## Display

| Test | Pass evidence |
|---|---|
| minimum brightness | readable and stable in a dark room |
| auto brightness | smooth transitions across recorded lux checkpoints |
| HBM | enters and exits at intended ambient-light thresholds |
| HDR | SDR and HDR samples avoid broad darkening or abrupt tone changes |
| AOD | brightness, refresh behavior and burn-in movement |
| UDFPS interaction | fingerprint illumination does not corrupt global brightness |

## Touch

| Test | Pass evidence |
|---|---|
| edge gestures | repeated back gesture on both sides |
| keyboard edges | corner and edge keys register without false touches |
| grip | portrait and landscape grip false-touch observations |
| gaming | multi-touch, high report rate, charging and thermal scenarios |
| screen off/on | touch resumes after AOD and suspend cycles |

## Connectivity and power

- Dual SIM, mobile data, 5G, VoLTE, VoWiFi and emergency-call path.
- Wi-Fi roaming, hotspot, Bluetooth audio/calls and NFC.
- GNSS cold/warm start and sensor rotation.
- Charging negotiation, battery reporting and thermal throttling.
- Deep sleep, idle drain and wake-source review.

## Application environment

Record results by exact package version and test date for:

- bank and payment applications;
- securities and finance applications;
- strong anti-cheat games;
- DRM and media services;
- Google service and Play Integrity configuration selected for the build.

Application results are evidence for that exact release and configuration, not a permanent property of the ROM family.

## Exit conditions

- No blocker in boot, storage, Goodix, telephony or rollback.
- Vibration calibration survives reboots.
- Camera and display limitations are documented with reproducible steps.
- Signed release posture matches the security gates.
- Original HyperOS slot remains recoverable until the fusion release completes repeated cold boots.
