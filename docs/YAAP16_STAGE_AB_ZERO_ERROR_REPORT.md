# YAAP 16 haotian Stage A / Stage B 零错误验收报告

## 1. 结论

在固定构建配置 `TARGET_BUILD_GAPPS=true`、`yaap_haotian-bp4a-userdebug`、`-j16` 下，本轮 Stage A 与 Stage B 已达到约定验收门槛：

- **Stage A：passed，真实诊断 0。**
- **Stage B：8/8 组 passed，1,983/1,983 个唯一模块，真实 error 0。**
- **最终 aggregate：passed，1,983 个目标，`ninja: no work to do.`。**
- **模块解析缺失：0；最终产品显式包缺失：0；组间目标重叠：0。**
- **声明安装输出：2,141 个，缺失 0。**
- **关键硬件模块：20/20 在矩阵中，声明产物均存在。**
- **最终预构建/输出状态校验：111/111 passed，0 failed，0 pending。**
- **真机操作：0。** 本阶段没有执行 ADB、fastboot、刷写、重启或分区修改。

这里的“零错误”按可复核的编译失败语义计数，包括 `FAILED:`、`fatal error:`、编译器 `error:`、链接器错误、未定义引用、Ninja failure 与非零退出。Stage B 仍记录上游 warning，并在第 7 节单独分类；warning 没有被伪装成 error，也没有从日志中删除。

## 2. 验收对象与固定配置

| 项目 | 固定值 |
|---|---|
| 源码根目录 | `/home/arima/android/yaap16` |
| 产品 | `yaap_haotian` |
| Variant | `yaap_haotian-bp4a-userdebug` |
| GApps | `TARGET_BUILD_GAPPS=true` |
| 并发 | `-j16` |
| 设备平台标识 | `sun` |
| Qualcomm 源码家族 | `sm8750` / UM 6.6 |
| 真机阶段 | 排除在本次 Stage A/B 之外 |

## 3. 根因与正式修正

Stage B 第 1 组 attempt1 曾在 68% 暴露唯一真实致命错误：`librmnetctl` 被传入 `USE_OLD_RMNET_DATA`，继而包含当前 6.6 内核头中不存在的 `linux/rmnet_data.h`。根因不是缺一个头文件，而是 YAAP Qualcomm common 没有把 `sun` 归入 UM 6.6，导致 RMNET、display、gralloc、AudioReach、SMMU、UBWCP、IPA、thermal 与 sepolicy 同时落入错误平台分支。

正式修正集中在 Qualcomm common，而不是继续堆叠设备树 namespace workaround：

1. `UM_6_6_FAMILY := sun`；
2. `sun -> QCOM_HARDWARE_VARIANT=sm8750`；
3. 加入 QSSI/UM、DRM PP、gralloc4、AudioReach、SMMU proxy、UBWCP、完整 gralloc handle 与 HEIF usage 选择；
4. 关闭旧 RMNET 路径，启用 SM8750 IPA namespace；
5. 选择现代 thermal、bootctrl、QSSI display 与 SM8750 vendor sepolicy；
6. 从设备树删除临时 `QCOM_SOONG_NAMESPACE` override 和显式 namespace workaround。

同一轮 CAF 冲突消解还删除了会与 CAF 源码模块争用安装路径的 stock `wpa_supplicant.conf`，并把 Xiaomi 需要的设置并入 overlay。旧提取树为 1,782 文件、785,115,017 字节；新树为 1,781 文件、785,114,883 字节。逐文件哈希对比证明净变化正好是 **-1 文件、-134 字节**，与提交 `47b3def` 的重命名、fixup 和删除操作一致，属于经过证明的基线迁移而不是数据缺位。

源码提交：

- Qualcomm common：[`0ff3569410bc824df84dfe5e81bfdaf4b776a7f8`](https://github.com/Arimacose/hardware_qcom-caf_common/commit/0ff3569410bc824df84dfe5e81bfdaf4b776a7f8)
- sm8750-common：[`6ad7ca1d69c6433064846d34692c05169ee8b186`](https://github.com/Arimacose/device_xiaomi_sm8750-common/commit/6ad7ca1d69c6433064846d34692c05169ee8b186)

## 4. Stage A 验收

Stage A attempt5 状态：

| 检查项 | 结果 |
|---|---:|
| Graph exit code | 0 |
| Graph elapsed | 398 秒 |
| warning/error/FAILED 诊断 | 0 |
| PRODUCT_SOONG_NAMESPACES | 17 |
| 唯一 namespace | 17 |
| 重复 namespace | 0 |
| 六项缺失 provider | 6/6 resolved |

当前变量已经由生成后的 `soong.yaap_haotian.variables` 和 dumpvars 证明：

- `TARGET_BOARD_PLATFORM=sun`
- `QCOM_HARDWARE_VARIANT=sm8750`
- `QCOM_SOONG_NAMESPACE=hardware/qcom-caf/sm8750`
- `TARGET_USES_QCOM_AUDIO_AR=true`
- `TARGET_USES_DRM_PP=true`
- `rmnetctl.old_rmnet_data=false`
- `qtidisplay.composer_version=v3_3`
- `qtidisplay.gralloc4=true`
- `qtidisplay.drmpp=true`
- `qtidisplay.smmu_proxy=true`
- `qtidisplay.ubwcp_headers=true`
- 三个 gralloc handle 能力开关均为 `true`
- `device/qcom/sepolicy_vndr/sm8750` 及 `generic/vendor/sun`、`qva/vendor/sun` 均进入 vendor sepolicy 目录

Stage A 权威审计：`D:\Codex\haotian-rom-fusion-build\logs\yaap16-stage-a-final-audit-attempt5-20260813.json`。

## 5. Stage B 矩阵与分组结果

当前 `module-info.json` 含 75,848 个条目；冻结矩阵选择 1983 个唯一模块：

| 解析来源 | 模块数 |
|---|---:|
| Stock prebuilt | 1792 |
| Platform glue | 121 |
| CAF/QTI source | 42 |
| Xiaomi device source | 28 |

| 构建组 | 目标 | 用时（秒） | 真实 error | Warning | 日志 SHA-256 前缀 |
|---|---:|---:|---:|---:|---|
| `01-device-core` | 836 | 526 | 0 | 347 | `452a7fef336ec3ca…` |
| `02-power-health-boot` | 120 | 1593 | 0 | 450 | `17bd77670194840b…` |
| `03-biometric-sensors` | 48 | 396 | 0 | 12 | `d175aa141177c598…` |
| `04-audio-bluetooth` | 115 | 805 | 0 | 70 | `4e3184df07d02ef6…` |
| `05-display-graphics` | 108 | 599 | 0 | 4 | `11a5e24132fe31aa…` |
| `06-camera-media` | 358 | 606 | 0 | 6121 | `a318b0d0b483ee2b…` |
| `07-connectivity-radio` | 316 | 533 | 0 | 21 | `db59b8b357b2f045…` |
| `08-security-nfc-misc` | 82 | 428 | 0 | 1 | `14ee086de3bc76ed…` |

八组用时合计 5486 秒（91 分 26 秒）。最终 aggregate 复验：

- target count：1983
- exit code：0
- true diagnostic：0
- warning：0
- `ninja: no work to do.`：`true`
- target SHA-256：`494b154765ab9ac0f009e232212a0093a03563b3945f8ac21ba00ba8f01c7784`

## 6. 关键硬件适配深度

下表不是只检查模块名存在；每一项都同时要求：位于 1,983 模块矩阵中、provider 可解析、声明安装输出由当前构建生成。

| 关键模块 | Provider | 声明输出 | 通过 |
|---|---|---:|---:|
| `android.hardware.biometrics.fingerprint-service.xiaomi.sm8750` | `device/xiaomi/sm8750-common/fingerprint` | 3 | 是 |
| `android.hardware.vibrator-service.xiaomi-sm8750` | `device/xiaomi/haotian/vibrator` | 3 | 是 |
| `android.hardware.sensors-service.xiaomi-sm8750-multihal` | `device/xiaomi/sm8750-common/sensors/multihal` | 2 | 是 |
| `audiohalservice.qti` | `vendor/xiaomi/sm8750-common` | 1 | 是 |
| `android.hardware.bluetooth@aidl-service-qti` | `vendor/xiaomi/sm8750-common` | 1 | 是 |
| `vendor.qti.hardware.display.composer-service` | `vendor/xiaomi/sm8750-common` | 1 | 是 |
| `vendor.qti.camera.provider-service_64` | `vendor/xiaomi/haotian` | 1 | 是 |
| `android.hardware.media.c2-mi-service` | `vendor/xiaomi/sm8750-common` | 1 | 是 |
| `android.hardware.wifi-service` | `hardware/interfaces/wifi/aidl/default` | 2 | 是 |
| `ipacm` | `hardware/qcom-caf/sm8750/data-ipa-cfg-mgr/ipacm` | 3 | 是 |
| `qcrilNrd` | `vendor/xiaomi/sm8750-common` | 1 | 是 |
| `android.hardware.gnss-aidl-service-qti` | `vendor/xiaomi/sm8750-common` | 1 | 是 |
| `android.hardware.security.keymint-service-qti` | `vendor/xiaomi/sm8750-common` | 1 | 是 |
| `android.hardware.gatekeeper-service-qti` | `vendor/xiaomi/sm8750-common` | 1 | 是 |
| `android.hardware.nfc-service-st` | `vendor/xiaomi/sm8750-common` | 1 | 是 |
| `android.hardware.secure_element-service.qti` | `vendor/xiaomi/sm8750-common` | 1 | 是 |
| `android.hardware.boot-service.qti` | `hardware/qcom-caf/bootctrl/aidl` | 3 | 是 |
| `android.hardware.thermal-service.qti` | `hardware/qcom-caf/thermal` | 3 | 是 |
| `android.hardware.health-service.qti` | `vendor/qcom/opensource/healthd-ext/aidl` | 3 | 是 |
| `android.hardware.power-service-qti` | `vendor/qcom/opensource/power` | 3 | 是 |

覆盖范围包括：启动控制、power/health/thermal、汇顶设备所使用的 fingerprint service 路径、传感器、触控、振动、AudioReach/AIDL audio、Bluetooth、Composer3 V3、gralloc4/DRM PP/SMMU/UBWCP、相机 provider/CamX/CHI、媒体 C2、Wi-Fi、IPA/modern RMNET、GNSS、RIL、IMS/UIM/eSIM 依赖、KeyMint、Gatekeeper、QSEE/Soter、Secure Element、DRM 与 NFC。

## 7. Warning 说明

Stage B 8 组共记录 7026 条 warning：

| 分类 | 数量 | 判断 |
|---|---:|---|
| assembler/compiler unused argument | 6070 | Android 上游汇编编译命令的未使用参数提示，集中在 camera/media codec 闭包 |
| deprecated API | 227 | 平台源码弃用 API 提示 |
| 其他上游 warning | 729 | Java/metalava/工具链及第三方源码提示 |

这些 warning 均未伴随 `FAILED:`、fatal error、链接失败或非零退出。Stage A 本身为 0 warning/error 诊断；最终 aggregate 为 0 warning、0 error。

## 8. 输出与边界审计

- 1,983 个选定模块中，1,972 个具有直接 `installed` 输出字段。
- 11 个模块属于 APEX/框架容器或 mountpoint/phony 类型，没有独立 `installed` 字段；它们仍在构建图中并由 aggregate 验证。
- 共检查 2,141 个声明安装输出，`lexists` 缺失数为 0。
- 其中 57 个输出是 staging symlink；55 个在尚未组装/挂载的输出树中表现为 dangling link。symlink 节点已生成，其目标来自最终分区或运行时挂载，这不等同于构建产物缺失。

本报告证明 Stage A 配置/依赖图和 Stage B 全硬件矩阵的源码解析、编译、链接、预编译 ELF 检查及输出闭合。完整 ROM 镜像打包、VINTF 运行时注册、SELinux 运行时行为，以及指纹录入、相机、人像、振动触感、HDR、亮度、电话和数据网络的设备行为属于后续阶段；本轮遵守指令，没有触碰真机。

## 9. Manifest 与远端可复现性

- 受管 local manifest：`D:\Codex\haotian-rom-fusion\manifests\haotian-yaap16.xml`
- local manifest SHA-256：`e9d8ad1fb1ea3abd56c92d2b31e3f6a30ea982b06cee00c640d2ffe9d5f747b5`
- resolved manifest：`D:\Codex\haotian-rom-fusion-build\logs\yaap16-resolved-manifest-after-um66-20260813.xml`
- resolved manifest SHA-256：`5808c75f70a8fdaee603654d4104ea4643d2837fc9679c472ba0fcfcf69abc35`
- resolved project 数：1150
- 重复 project path：0
- Qualcomm common 项目保留 manifest identity `hardware_qcom-caf_common`，remote 为 `arimacose`，revision 固定到 `0ff3569410bc824df84dfe5e81bfdaf4b776a7f8`；SM8750 三个 pickup linkfile 均保留。
- GitHub API 已验证两个远端分支 SHA 与本地 HEAD 完全一致。

## 10. 权威证据

- 汇总 JSON：`D:\Codex\haotian-rom-fusion\evidence\yaap16-stage-ab-zero-error.json`
- 原始总审计：`D:\Codex\haotian-rom-fusion-build\logs\yaap16-stage-ab-zero-error-final-20260813.json`
- 原始总审计 SHA-256：`f1269ecab209f5352d3adb10a086c648aae435cd6bcebb6c29c918b9cddf9854`
- Stage B matrix：`D:\Codex\haotian-rom-fusion-build\logs\stage-b-matrix\yaap16-stage-b-hardware-matrix.json`
- 分组日志/状态/目标快照：`D:\Codex\haotian-rom-fusion-build\logs\stage-b-builds`
- modern RMNET 审计：`D:\Codex\haotian-rom-fusion-build\logs\stage-b-librmnetctl-after-um66-audit-20260813.json`
- 最终预构建/输出状态校验：`D:\Codex\haotian-rom-fusion-build\logs\yaap16-prebuild-validation-after-stage-ab-20260813.json`
- 预构建校验 SHA-256：`d9729feea877bbb3e991b43841bc3819f86e860d9f489c3036981b9059ff102a`
- 预构建校验摘要：`111/111 passed`、`0 failed`、`0 pending`、`expected_output_state=present`
- vendor 基线逐文件对比：`D:\Codex\haotian-rom-fusion-build\logs\sm8750-common-vendor-tree-delta-20260813.json`
- vendor 基线对比 SHA-256：`702e47924de666133ad1734aa4b00096a12c2c07234c459701e0548729a80f68`

机器审计最终字段：`result=passed`、`failures=[]`；预构建验证最终字段：`result=pass`、`failed=0`、`pending=0`。
