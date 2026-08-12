# YAAP 16 haotian 首次 Soong graph 报告

## 1. 结论

本轮已按固定配置完成首次 YAAP 16 / haotian 构建图闭合，并在源码提交后再次复验：

- 固定环境：`TARGET_BUILD_GAPPS=true`
- 固定首次 variant：`yaap_haotian-bp4a-userdebug`
- 图校验命令：`m -j16 nothing`
- 首次通过：attempt 11，357 秒
- 提交态复验：attempt 12，415 秒
- 最终退出码：`0`
- 最终标记：`Successfully read the makefiles.` 与 `build completed successfully`

本轮覆盖 Soong、Kati/Make、packaging graph 和最终 Ninja 对 `nothing` 目标的读取/一致性校验。它没有进入模块大规模编译、镜像组装、OTA 打包、DSU 或真机阶段。

## 2. 执行边界

| 项目 | 结果 |
|---|---|
| WSL 发行版 | `Ubuntu-ROMBuild` |
| 源码根目录 | `/home/arima/android/yaap16` |
| 产品 | `yaap_haotian` |
| Android / release config | Android 16 / `bp4a` |
| build variant | `userdebug` |
| GApps profile | `TARGET_BUILD_GAPPS=true` |
| 并发 | `-j16` |
| `out` 实际规模 | 9,939,209,013 字节，`du -sh` 报告约 9.4 GiB |
| 产品目录中的 `.img/.zip/.bin` | 0 |
| DSU / 真机动作 | 0 |

`m nothing` 仍会生成很大的 Soong/Kati 图与模块元数据，因此 `out` 达到约 9.4 GiB；这部分不是 ROM 镜像或 OTA 成品。

## 3. 最终通过证据

- 日志：`D:\Codex\haotian-rom-fusion-build\logs\yaap16-soong-graph-first-20260812-attempt12.log`
- 状态：`D:\Codex\haotian-rom-fusion-build\logs\yaap16-soong-graph-first-20260812-attempt12.status`
- 日志 SHA-256：`77a59d23ac69a55c7288810928bda182bd3374be05e899aa94a3b130622471c3`
- 状态内容：`result=passed`、`exit_code=0`、`elapsed_seconds=415`
- 结构化证据：`D:\Codex\haotian-rom-fusion\evidence\yaap16-soong-graph.json`

提交态复验从已提交的 `device/xiaomi/sm8750-common` 开始，最终依次完成：

1. 产品配置解析；
2. Blueprint bootstrap；
3. Android.bp 全树分析；
4. `build.yaap_haotian.ninja` 生成；
5. Kati Make 模块图；
6. packaging graph；
7. 最终 Ninja `nothing` 目标。

## 4. 迭代记录

| Attempt | 结果 | 秒 | 本次暴露或确认的事项 |
|---:|---|---:|---|
| 1 | envsetup_failed | - | wrapper used set -u while build/envsetup.sh expects unset shell variables |
| 2 | failed | 34 | SM8750 pickup link pointed into sepolicy_vndr instead of YAAP hardware_qcom-caf_common |
| 3 | failed | 52 | missing touch AIDL plus libvmmem headers/source and namespace visibility |
| 4 | failed | 37 | source display composer selected AIDL V2 while the preferred stock service selected V3 |
| 5 | failed | 39 | local development AVB input vendor/haotian/security/avb.pem was absent |
| 6 | failed | 39 | device matrix referenced a second Qualcomm AIDL matrix file absent from the YAAP common project |
| 7 | failed | 58 | arm64 libprotobuf-cpp-lite-21.12-vendorcompat provider was absent |
| 8 | failed | 60 | arm64 libprotobuf-cpp-full-21.12-vendorcompat provider was absent |
| 9 | failed | 262 | XiaomiEuicc required the separate EuiccPolicy project, which was absent from the manifest |
| 10 | failed | 298 | telephony-ext was injected as a boot jar by both YAAP qcom-common and the Xiaomi common device tree |
| 11 | passed | 357 | passed after source fixes |
| 12 | passed | 415 | passed again from the committed device-tree state |

attempt 11 是源码修正后的第一次通过；attempt 12 是提交、推送设备树后的复验。两次连续通过排除了“只在未提交临时工作树上成立”的情况。

## 5. 为闭合图实施的修改

### 5.1 Manifest 与项目依赖

1. 将 SM8750 pickup 链接改挂到已有 YAAP `hardware_qcom-caf_common` 项目：
   - `os_pickup_audio-ar.mk -> hardware/qcom-caf/sm8750/audio/Android.mk`
   - `os_pickup_qssi.bp -> hardware/qcom-caf/sm8750/Android.bp`
   - `os_pickup.mk -> hardware/qcom-caf/sm8750/Android.mk`
2. 加入 `LineageOS/android_vendor_qcom_opensource_libvmmem`，满足 `libvmmem_headers` 与 `libvmmem`。
3. 从上游接口树补回 touch AIDL，生成 `vendor.lineage.touch-V1-ndk`。
4. 加入 `LineageOS/android_packages_apps_EuiccPolicy`，满足 `XiaomiEuicc` 的基础策略应用依赖。

resolved manifest：

- 路径：`D:\Codex\haotian-rom-fusion\manifests\resolved\yaap16-haotian-20260812.xml`
- 项目条目：1,150
- 有效 path/name：1,150，均唯一
- SHA-256：`c1264cbe2cae0bf6c83cf181efbe7ac8e8674a50b21c2e0cd13a7eb33158a78b`

### 5.2 Display Composer 版本统一

HyperOS 3.0.304 的 stock composer service 与 VINTF 片段使用 Composer3 AIDL V3；YAAP Qualcomm common 的回退值原为 V2。设备公共 BoardConfig 现固定：

```make
SOONG_CONFIG_qtidisplay_composer_version := v3_3
```

这样 source defaults 与优先使用的 stock composer prebuilt 只选择一套稳定 AIDL 版本。

### 5.3 VINTF matrix 来源

设备树原先同时引用本地 matrix 和 YAAP common 项目中不存在的第二份 `compatibility_matrix_aidl.xml`。比对确认本地文件承载同一组 AIDL 要求后，`DEVICE_MATRIX_FILE` 只保留设备树维护的本地 matrix。

### 5.4 3.0.304 arm64 protobuf vendorcompat

`liboischannel.so` 和 `libsnsapi-full.so` 分别声明对 21.12 lite/full SONAME 的依赖，而 AOSP vendorcompat 预置只有 32 位 provider。现从已验证的 HyperOS 3.0.304 dump 提取匹配的 64 位库并生成 `prefer: true` 的 arm64 prebuilt：

| Blob | 字节 | SHA-256 | stock/staged |
|---|---:|---|---|
| `libprotobuf-cpp-lite-21.12.so` | 591,952 | `5853fe986d2183b0c6a7ae4f8fc5090ab093bad079ac589bbe4295edad1f12c2` | 一致 |
| `libprotobuf-cpp-full-21.12.so` | 2,295,512 | `a11b1833ab6a4e5d954acaec3e9435a067501b65520a9769df338fc0137da4c9` | 一致 |

Git 只记录 proprietary 清单；实际 blob 留在 `D:\Codex\haotian-rom-fusion-build` 与 WSL proprietary staging。

### 5.5 CLO telephony boot jar 去重

YAAP `hardware/qcom-caf/common/common.mk` 已注入共享 CLO telephony 包和 `telephony-ext` boot jar；Xiaomi common 又注入相同集合，导致同一 `boot-telephony-ext.oat` 出现两条 Ninja 生成规则。设备树现只保留 Xiaomi 专属的 `xiaomi-telephony-stub`，共享 CLO 集合由 YAAP qcom-common 单点负责。

### 5.6 本地开发 AVB 输入

图生成要求 `vendor/haotian/security/avb.pem` 存在。本轮生成了仅用于本地 `userdebug` 的 RSA-4096 开发键：

- 公钥 DER SHA-256：`6675a91da7b5245391e2732edfde29360a753d60fb6ecc37e247593e94f38899`
- 指纹记录：`D:\Codex\haotian-rom-fusion-build\logs\yaap16-local-development-avb-public-fingerprint.txt`
- 私钥权限：`0600`
- 私钥位置在管理 Git 之外

生产签名、完整 AVB chain 与发布密钥仍属于后续 release-hardening gate。

## 6. 已发布源码提交

| Repository | Commit | 内容 |
|---|---|---|
| `Arimacose/hardware_lineage_interfaces` | `ca560522cee3977861002372d1408cd7bb690198` | 恢复 touch control AIDL |
| `Arimacose/device_xiaomi_sm8750-common` | `8b35416` | Composer/VINTF/telephony graph 对齐 |
| `Arimacose/device_xiaomi_sm8750-common` | `dbfb9fc` | 两项 arm64 protobuf vendorcompat 清单 |

管理仓库另有 manifest graph-closure 提交 `d7fb475`；最终报告/证据提交在本报告完成后产生。

## 7. 核心图文件

| 文件 | 字节 | SHA-256 |
|---|---:|---|
| `/home/arima/android/yaap16/out/soong/build.yaap_haotian.ninja` | 366,139,168 | `e9e75775fbf15c0c434d161b5bd9f8bb0b6aa7e1886d4b1bb5cd4164ea094eea` |
| `/home/arima/android/yaap16/out/build-yaap_haotian.ninja` | 1,183,828,043 | `7f8f416bfab75d284c43d6e0141bc2f28658b766551d2b9b1667456bf268998d` |
| `/home/arima/android/yaap16/out/build-yaap_haotian-package.ninja` | 57,818 | `68a391f870674ac0358bda957f4b1cff71e072ec2f372df13b0e82fe0bf0f388` |
| `/home/arima/android/yaap16/out/soong/soong.yaap_haotian.variables` | 849,735 | `54d15e766d31990c21a3a07ee00d1e54d45f84afdb584007b0cca6f6eab62503` |
| `/home/arima/android/yaap16/out/soong/Android-yaap_haotian.mk` | 447,925,750 | `97cf1a05c9532034096063bb26d2a19bb0e955ec9a3ac44a3efdd69ea122c5ba` |
| `/home/arima/android/yaap16/out/soong/installs-yaap_haotian.mk` | 114,986,798 | `9cf7aecca90c593d11667a328de6963f12a6ca2e8f3046cd6a3e2a362e531ac1` |

其中 `out/build-yaap_haotian.ninja` 约 1.18 GB，`out/soong/build.yaap_haotian.ninja` 约 366 MB。这解释了只做 graph 仍会产生显著磁盘与内存开销。

## 8. 剩余非致命警告

最终 attempt 12 没有 `FAILED` 或 `error:` 行，仍有两组 install-rule override 警告：

1. `vendor/etc/vintf/manifest/bluetooth_audio.xml`
2. `vendor/etc/wifi/wpa_supplicant.conf`

每组表现为“新命令覆盖、旧命令忽略”。它们没有形成同一路径的 Ninja 双生成规则，因而本次图校验通过。下一阶段在模块编译前应追踪各自的两个安装来源，选定 stock 或 source 单一所有者，以降低后续打包歧义。

另有一个图卫生观察：`PRODUCT_SOONG_NAMESPACES` 输出仍包含 `hardware/qcom-caf/sun`。本轮没有因它报错；后续可核对其来源是否应为 `hardware/qcom-caf/sm8750`，再以独立变更处理。

## 9. 本次通过证明了什么

已证明：

- 固定 GApps profile 与固定 bp4a userdebug variant 可完成产品解析；
- 当前 manifest 能提供图阶段已解析到的项目；
- Android.bp 模块名、变体、AIDL 版本与显式依赖在本轮范围内闭合；
- Make/Kati 的 required-module 与 boot-jar 规则闭合；
- packaging graph 可生成；
- Ninja 能读取最终图并完成 `nothing` 目标；
- 提交态可以重复得到同一通过结论。

尚未覆盖：

- C/C++/Rust/Java/Kotlin 模块的实际全量编译；
- SELinux policy 编译与 neverallow 结果；
- VINTF assemble/check、ELF check、linker namespace 与 ABI 的完整构建期校验；
- boot/vendor_boot/dtbo/super/system/vendor/product 等镜像生成；
- OTA、签名、AVB chain、增量包；
- 开机、RIL、相机、指纹、振动、亮度、HDR、边缘触控、GMS 登录与应用环境；
- DSU、fastboot、recovery 或真机写入。

因此本轮结论是“源码与产品构建图已闭合”，不是“ROM 已可刷入”或“硬件功能已验证”。

## 10. 下一阶段建议门槛

下一阶段若继续保持离线，可从低成本模块编译门开始，而不是直接完整 ROM：

1. 清理 Bluetooth Audio VINTF 与 `wpa_supplicant.conf` 两组安装所有权警告；
2. 核对 `hardware/qcom-caf/sun` namespace 来源；
3. 编译小型关键模块集合：touch AIDL、fingerprint service、health service、EuiccPolicy、libvmmem、display composer service；
4. 进入 SELinux/VINTF/ELF 静态 gate；
5. 再决定是否启动完整 `m yaap` 或目标 images。

每一道门都应保持日志、退出码、输出哈希和回滚提交；DSU/真机阶段继续独立隔离。

## 11. 回滚点

- 设备公共树 graph 对齐前：`dfd356f8146b7343b079a88ea2d106ef8deb0027`
- graph 对齐提交：`8b35416`
- protobuf 清单提交：`dbfb9fc599f7e2ff7e3c5add6b9c8f38185db90a`
- 管理 manifest graph-closure：`d7fb475`
- 所有构建输出只在 `/home/arima/android/yaap16/out`；清理或迁移 `out` 不影响源码提交与 D 盘日志证据。
