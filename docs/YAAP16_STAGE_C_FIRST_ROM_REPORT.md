# YAAP 16 / haotian Stage C：第一版完整 ROM、OTA 与 upper5 DSU 报告

> 报告日期：2026-08-13
> 设备：Xiaomi 15 Pro（`haotian`）
> ROM：YAAP 16 / Android 16 / AOSP `android-16.0.0_r4`
> 构建形态：`yaap_haotian-bp4a-userdebug`，`TARGET_BUILD_GAPPS=true`
> 底包与固件基线：HyperOS `OS3.0.304.0.WOBCNXM`
> 当前结论：**第一版完整 A/B OTA 已构建并通过离线完整性门禁；五分区 DSU 已生成并通过独立二次审计；真机运行验证尚未开始。**

## 1. 结论摘要

本阶段完成了以下实际产物和验证工作：

1. 在同一个冻结构建图中同时生成 `bacon` OTA 与 `target-files-package`，消除了先后单独执行导致时间戳、AVB 摘要或镜像内容漂移的问题。
2. 生成了完整 A/B OTA，payload 覆盖 **45 个分区**，包含 Android 上层、启动链、动态分区、内核模块分区和随底包继承的固件分区。
3. 对最终 OTA、target-files 目录和 target-files ZIP 做跨产物一致性校验；目录与 ZIP 中的 16 个最终镜像逐字节一致。
4. 通过 OTA 整包签名、payload 签名、payload 属性、45 分区 payload 重放、VINTF、AVB、文件系统、动态分区、SELinux、APK/APEX 签名清单和构建身份检查。
5. 生成 `system + system_ext + product + vendor + odm` 五分区 DSU，覆盖目前在不替换真机内核前提下可合理测试的最大用户空间/HAL 范围。
6. 对 DSU ZIP 独立重新解压全部五个成员，再次校验 ZIP CRC、成员 SHA-256、raw ext4、只读 `e2fsck`、AVB hashtree、AVB 属性以及源镜像 root digest 不变。
7. 将适配源代码提交推送到各自 GitHub fork，并在管理仓库保存构建、审计、DSU 和固定 manifest 的可复现配置。
8. 整个阶段没有执行 `adb`、`fastboot`、reboot、DSU 安装、OTA sideload 或任何真机写入操作。

本版本是**测试构建**，不是生产发布版。它使用 `userdebug`、AOSP testkey 和本地 AVB 开发密钥，并含 9 个精确核对过的 userdebug-only permissive SELinux domain。它适合进入受控真机 bring-up，不适合作为银行、金融、反作弊网游或高完整性日用环境的正式发行版本。

## 2. 固定构建元组

| 项目 | 固定值 |
|---|---|
| 源码根目录 | `/home/arima/android/yaap16` |
| WSL 发行版 | `Ubuntu-ROMBuild` |
| 产品 | `yaap_haotian` |
| lunch | `yaap_haotian-bp4a-userdebug` |
| Android SDK | 36 |
| YAAP 版本 | `16-HOMEMADE-haotian-20260813` |
| GApps | `TARGET_BUILD_GAPPS=true` |
| 并发 | `-j16` |
| 构建目标 | `bacon target-files-package` |
| 固定时间戳 | `BUILD_DATETIME=1786625277` |
| 固定增量号 | `BUILD_NUMBER=haotian.stagec.20260813.1` |
| 固定构建账户 | `BUILD_USERNAME=android-build` |
| 固定构建主机 | `BUILD_HOSTNAME=haotian-builder` |
| 最终构建耗时 | 1493 秒（24 分 53 秒） |
| 最终构建结果 | `exit_code=0` |

最终 OTA 内嵌 metadata、磁盘上的 `ota_metadata`、target-files 目录和 target-files ZIP 中的 `SYSTEM/build.prop` 均确认：

```text
post-build-incremental=haotian.stagec.20260813.1
post-timestamp=1786625277
ro.build.version.incremental=haotian.stagec.20260813.1
ro.build.date.utc=1786625277
```

## 3. 最终交付产物

### 3.1 完整 A/B OTA

Windows 可访问副本：

```text
D:\Codex\haotian-rom-fusion-build\release\yaap16-stagec-20260813\YAAP-16-HOMEMADE-haotian-20260813.zip
```

WSL 原始构建产物：

```text
/home/arima/android/yaap16/out/target/product/haotian/YAAP-16-HOMEMADE-haotian-20260813.zip
```

| 项目 | 值 |
|---|---|
| 大小 | 4,836,470,722 字节 |
| SHA-256 | `ebc06db809ea760069375e93e4f30f564fadec8f5c0fa7740da2ad42512b3902` |
| OTA 类型 | A/B full OTA |
| payload 大小 | 4,836,462,377 字节 |
| payload SHA-256 | `9c1997555814a34f57ea7686b8f5ce8acfe237d4c5b2fd06c37ac6b512dff701` |
| payload 格式版本 | 2 |
| payload manifest 长度 | 298,830 字节 |
| payload 分区数 | 45 |
| OTA SPL | `2026-05-05` |

Windows 副本不是未验证的额外拷贝：复制后重新计算的 SHA-256 与 WSL 原产物相同。

### 3.2 target-files

```text
/home/arima/android/yaap16/out/target/product/haotian/obj/PACKAGING/target_files_intermediates/yaap_haotian-target_files.zip
```

| 项目 | 值 |
|---|---|
| 大小 | 21,037,181,176 字节 |
| SHA-256 | `343e701ac85c76e581354fb63966335549c2d53bcd92f92305a6e5b5b6c6a537` |
| ZIP CRC | 通过 |
| `validate_target_files` | 通过 |
| `check_target_files_vintf` | `COMPATIBLE` |

target-files 保留在 WSL ext4 构建盘内，因为它是约 20 GB 的后续增量 OTA、签名和诊断输入；没有再复制一份到 D 盘占用空间。

### 3.3 upper5 多分区 DSU

```text
D:\Codex\haotian-rom-fusion-build\dsu\yaap16-stagec-upper5-host304\YAAP-16-20260813-haotian-upper5-host304-mpDSU.zip
```

配套文件：

```text
D:\Codex\haotian-rom-fusion-build\dsu\yaap16-stagec-upper5-host304\YAAP-16-20260813-haotian-upper5-host304-mpDSU.zip.sha256
D:\Codex\haotian-rom-fusion-build\dsu\yaap16-stagec-upper5-host304\YAAP-16-20260813-haotian-upper5-host304-mpDSU.zip.manifest.json
D:\Codex\haotian-rom-fusion-build\dsu\yaap16-stagec-upper5-host304\YAAP-16-20260813-haotian-upper5-host304-mpDSU.zip.audit.json
```

| 项目 | 值 |
|---|---|
| ZIP 大小 | 5,206,856,553 字节 |
| ZIP SHA-256 | `d8a9f0417cef780ea63878c9d9505e3819690e44859cecc40e237f682cec0b04` |
| 原始五镜像总量 | 9,835,122,688 字节 |
| 构建耗时 | 1884 秒（31 分 24 秒） |
| 独立二次审计耗时 | 146 秒 |
| ZIP 成员 | `system.img`、`system_ext.img`、`product.img`、`vendor.img`、`odm.img` |
| 运行验证状态 | `not_started` |

## 4. OTA payload 的 45 个分区

最终 payload 包含：

```text
abl
aop
aop_config
bluetooth
boot
cpucp
cpucp_dtb
devcfg
dsp
dtbo
featenabler
hyp
idmanager
imagefv
init_boot
keymaster
modem
modemfirmware
multiimgqti
odm
pdp
pdp_cdb
product
pvmfw
qupfw
recovery
shrm
soccp_dcd
soccp_debug
spuservice
system
system_dlkm
system_ext
tz
uefi
uefisecapp
vbmeta
vbmeta_system
vendor
vendor_boot
vendor_dlkm
vm-bootsys
xbl
xbl_config
xbl_ramdump
```

这说明该 ZIP 不是只有 `system` 的 GSI，也不是只包含上层动态分区的简化包；它是包含启动链、内核配套分区和继承固件的完整 A/B payload。

需要特别注意：完整 OTA 中的 `boot`/`vendor_boot`/`system_dlkm`/`vendor_dlkm` 与构建树预编译的 **6.6.77** 内核栈配套。若后续真正刷入完整 OTA，它会替换当前真机的第三方 **6.6.143** 内核环境；这与 DSU 路径保留现有内核的行为不同。

## 5. 源码适配与已推送提交

### 5.1 Qualcomm/Xiaomi VINTF 与 Thermal 修复

| 仓库 | 分支 | 最终提交 | 作用 |
|---|---|---|---|
| `Arimacose/device_xiaomi_sm8750-common` | `yaap-16` | `45f6a6be34b9d4f51b624c79243c6fc49a547bc6` | 使用 `+=` 合并设备 FCM，避免覆盖 YAAP device matrix |
| `Arimacose/hardware_qcom-caf_common` | `haotian-16` | `8385f582e3c12a69d9d2783e42c75052ce37a3e0` | 同步 sun/SM8750 Qualcomm framework matrix，并保留 YAAP 独有 HAL |
| `Arimacose/hardware_qcom-caf_thermal` | `haotian-16` | `d516438050624590cff3163c88885725030a382c` | 将 Thermal HAL 升至 AIDL V2 能力，消除已废弃 V1 要求 |
| `Arimacose/vendor_yaap` | `haotian-16` | `97076c263cea2d4c89b4e108c8da8c5b299ca30d` | Pixel app sepolicy、Lineage Health AIDL matrix、冻结时间戳版本号 |

`vendor_yaap` 中本阶段的关键提交链：

```text
7fd0612  config: partition Pixel app sepolicy correctly
130a9af  config: declare Lineage health AIDL v2
97076c2  config: derive YAAP version from BUILD_DATETIME
```

固定 resolved manifest：

```text
D:\Codex\haotian-rom-fusion\manifests\resolved\yaap16-haotian-stage-c-20260813.xml
SHA-256: 8cc70a712a5b1bc1cc3239c973d19b4cceef1888d1dc21487fba81b2cbbaa3d0
```

### 5.2 构建迭代与根因闭环

| 尝试 | 结果 | 根因 | 处理 |
|---|---|---|---|
| attempt 1 | 前端超时，未进入 Ninja | 编排工具等待窗口不足 | 保留状态并改为后台长任务 |
| attempt 2 | 失败 | Pixel/Flipendo seapp/SELinux 分区归属错误 | 将 Pixel app sepolicy 按 system_ext/product 正确分区 |
| attempt 3 | 失败 | Thermal V1 已废弃，Qualcomm 通用 FCM 项不足，Lineage Health 未声明 | 引入 Thermal V2、补齐 Qualcomm matrix、声明 Health AIDL |
| attempt 4 | 失败 | Xiaomi common 使用 `:=` 覆盖 YAAP device FCM | 改为 `+=` 合并所有 matrix |
| attempt 5 | 成功 | 完整 OTA 首次生成 | 随后发现 target-files 单独生成会引入时间戳漂移 |
| frozen attempt 1 | 成功 | 同一图生成 OTA + target-files | 固定 epoch/build number，作为最终产物 |

## 6. 最终离线完整性门禁

### 6.1 核心审计：14/14 通过

最终严格失败语义审计包含：

1. 输入路径与大小存在性；
2. OTA、target-files ZIP 和全部最终镜像 SHA-256；
3. OTA 必需成员、重复成员、CRC、streaming payload 存储方式和 metadata；
4. OTA/target-files 目录/target-files ZIP 的冻结 epoch、增量号和镜像一致性；
5. OTA whole-file signature 与 A/B payload signature；
6. target-files ZIP CRC；
7. 274 个 APK/APEX 的签名清单读取；
8. VINTF 兼容性；
9. `validate_target_files`；
10. AVB footer、root vbmeta、三个 chain descriptor 和全部下游镜像；
11. 七个动态分区 raw ext4 只读文件系统检查；
12. 动态分区容量、Virtual A/B 和 `super_empty` liblp 元数据；
13. SELinux userdebug 精确 permissive allowlist 与预编译策略摘要；
14. 构建身份和 OTA metadata。

最终状态：

```text
D:\Codex\haotian-rom-fusion-build\logs\stage-c-integrity\core-final.status
failed_checks=0
```

### 6.2 payload/APEX 审计：6/6 通过

| 检查 | 结果 |
|---|---|
| payload 提取大小和 SHA-256 | 通过 |
| 内嵌 properties 与重新生成 properties | 完全一致 |
| payload 重放到临时 45 分区并逐个与 target-files 比较 | 45/45 通过 |
| `paycheck` 静态完整性与 payload 签名 | 通过 |
| payload manifest 信息解析 | 通过 |
| APK 签名 + `host_apex_verifier` | 38/38 APEX/CAPEX 通过 |

Android 16 源码中的 `paycheck.py` 仍会探测已经从当前 protobuf 删除的旧 ChromeOS 字段 `old_kernel_info`/`old_rootfs_info`。审计脚本只在 `out/` 临时副本中加入“字段不在 active descriptor 时视为不存在”的窄兼容处理，不修改 ROM 源码；原脚本与临时兼容副本的 SHA-256 均写入检查日志。

最终状态：

```text
D:\Codex\haotian-rom-fusion-build\logs\stage-c-integrity\payload-apex-final.status
failed_checks=0
```

## 7. VINTF 结果

`check_target_files_vintf` 的最终结果为：

```text
COMPATIBLE
```

已验证的关键修复包括：

- Thermal AIDL V2；
- Qualcomm sun/SM8750 通用 framework compatibility matrix；
- YAAP 独有 `vendor.kineticsxr.hardware.nordic` 与 `vendor.qti.vst`；
- Lineage Health AIDL `1-2`，包括 `IChargingControl` 和 `IFastCharge`；
- Xiaomi device matrix、Qualcomm common matrix 和 YAAP device matrix 同时进入最终 `compatibility_matrix.device.xml`；
- 构建内核版本/配置被 VINTF 工具读取为 `6.6.77` / kernel level `202404`。

此结果证明**静态 manifest/matrix/kernel 配置契约一致**，不证明每个 HAL 在真机上都能启动、注册或正确完成业务调用。

## 8. AVB、签名与启动链

### 8.1 AVB

- root `vbmeta.img`：`SHA256_RSA4096`；
- `boot.img`：`SHA256_RSA4096`，rollback location 3；
- `recovery.img`：`SHA256_RSA4096`，rollback location 1；
- `vbmeta_system.img`：`SHA256_RSA4096`，rollback location 2；
- root vbmeta 正确链到 `boot`、`recovery` 和 `vbmeta_system`；
- `vbmeta_system` 覆盖 `system`、`system_dlkm`、`system_ext`、`product`；
- root vbmeta 还包含/验证 `dtbo`、`init_boot`、`vendor_boot`、`odm`、`vendor`、`vendor_dlkm`；
- 动态分区使用 SHA-1 dm-verity hashtree 与 FEC，这是当前设备树/底包继承配置，不是 SHA-256 文件哈希强度的描述；
- root vbmeta digest：`7f42f56fced973e6c57d04f37341bda058b5796d2c53694573539ec60e2c260a`。

AVB 开发私钥路径：

```text
/home/arima/android/yaap16/vendor/haotian/security/avb.pem
SHA-256: 23a5dc1bf38853f49f0021c2af4f094095ddd8f91b869a586555f81443fdc2c0
```

私钥没有提交到管理仓库；`.gitignore` 明确排除密钥格式。

### 8.2 OTA/APK 签名

- OTA whole-file signature：通过；
- A/B payload signature：通过；
- OTA/APK 默认开发证书：AOSP `testkey`；
- 证书 SHA-256：`a4384ba815b9499a5ce349b4e33c1755278873fe2eac150a068823f526e6dbde`；
- whole-file testkey 证书路径触发的是旧 SHA-1 digest 流程；
- APK/APEX 签名清单共读取 274 项，其中 262 个 APK、12 个未压缩 APEX；压缩 CAPEX 另由 APEX 审计覆盖。

因此该 OTA 是**结构完整、签名自洽的开发 OTA**。它不等于 Xiaomi stock recovery 信任的官方 OTA；第一次安装需要与 testkey/自定义 AVB 链相匹配的安装路径。后续真机方案必须在执行前单独确认恢复环境、当前槽位、可回退镜像和 userdata 风险。

## 9. SELinux 结果与准确边界

最终预编译 policy 的 system/system_ext/product mapping 摘要与 ODM 侧预编译摘要完全一致，neverallow 构建门禁已通过。

该 `userdebug` policy 不是“零 permissive domain”。离线解析得到以下 9 个域：

```text
su
qti-testscripts
backuptool
vendor_pdt_app
vendor-qti-testscripts
aoncameraservice_app
vendor_hal_debugutils_default
vendor_cta_app
vendor_logkit_app
```

其中：

- `su`、`qti-testscripts`、`backuptool` 明确处于 `userdebug_or_eng` 条件；
- Qualcomm `generic/vendor/test` 和 `qva/vendor/test` 目录只在 `TARGET_BUILD_VARIANT=userdebug|eng` 时进入 vendor policy；
- 最终门禁不是要求其为空，而是要求它**精确等于上述已审查 allowlist**，出现任何新增或缺失域都会失败；
- 正式 `user` release gate 必须重新构建并要求 permissive domain 数为 0。

因此本版本可以用于 bring-up，但 SELinux 隔离强度低于正式 user 发行版。

## 10. 文件系统与动态分区

七个动态分区均为 raw ext4，并通过只读 `e2fsck -fn`：

| 分区 | 镜像大小（字节） | SHA-256 |
|---|---:|---|
| system | 1,137,766,400 | `221c2e73ab55bbe3c2562acf487a44cb7dc42bcb25c2765ecdef8074b577e059` |
| system_ext | 552,861,696 | `c8af6c30fe76ec81092a9e1e2f5aa7fbd668e1de8eda2a7246322854937e049f` |
| product | 2,227,720,192 | `63a261cc9b54b870240268cc48e7b567a78f5d4d13fac000f150ddd2230bde99` |
| vendor | 880,070,656 | `e10f923ca170e43486cf03ad94eea5b70123a79b9d651b9dc1b92091c5f49ed2` |
| odm | 5,036,703,744 | `6a4af705833404e1b9f3d3897d1d7a3d7f7ec3567c283f3eb6d8806ebd988edb` |
| system_dlkm | 13,127,680 | `9ead3e251160f715dfcce66c414eb6645206b837ba02c390ce1c864bcb446fd7` |
| vendor_dlkm | 180,912,128 | `c295f3001de3511a58c553fcc216aae3bf4a19fea55efb60f989ecb40c57aea2` |

动态分区参数：

| 项目 | 值 |
|---|---:|
| super 大小 | 11,811,160,064 |
| qti dynamic group 大小 | 11,809,841,488 |
| 七镜像合计 | 10,029,162,496 |
| group 剩余 | 1,780,678,992 |
| Virtual A/B | true |
| COW 压缩 | LZ4 |
| COW 版本 | 3 |

`super_empty.img` 是 5,288 字节的**最小 liblp metadata image**，不是可由 `lpunpack` 当作完整 super 数据镜像展开的文件。独立解析验证了：

- geometry SHA-256；
- header SHA-256；
- tables SHA-256；
- metadata slot count 3；
- Virtual A/B flag；
- 14 个 A/B 逻辑分区名；
- `default`、`qti_dynamic_partitions_a`、`qti_dynamic_partitions_b` 三个组；
- `super` 块设备大小与对齐。

## 11. 构建身份与 Android 完整性风险

实际构建属性：

```text
ro.build.type=userdebug
ro.build.tags=test-keys
ro.build.flavor=yaap_haotian-userdebug
ro.yaap.device=haotian
```

同时，ROM 对外 fingerprint 被设备树设置为：

```text
Xiaomi/haotian/haotian:16/BP2A.250605.031.A3/OS3.0.304.0.WOBCNXM:user/release-keys
```

这会形成“stock-looking fingerprint + 实际 userdebug/test-keys”的身份分裂。它可能帮助部分兼容性判断，但不会把开发 ROM 变成可信 stock 环境，也不构成 Play Integrity、Key Attestation 或应用风控通过保证。

对银行、金融、支付、反作弊网游和强完整性应用，本版本风险等级应视为**高**，原因包括：

- bootloader 已解锁；
- `userdebug` / `test-keys`；
- 本地开发 AVB key；
- 9 个 userdebug permissive SELinux domain；
- ROM fingerprint 与实际签名/构建类型不一致；
- 真机硬件 attestation、Play Integrity verdict 和应用侧风控尚未测量；
- DSU 本身也可能被应用识别为动态系统或非 stock 环境。

本阶段没有对任何完整性伪装模块、Zygisk/KernelSU 隐藏链或银行应用通过率作出新的真机结论。

## 12. `validate_target_files` 的非阻断警告

官方验证工具返回 0，但报告了以下需要后续 release-hardening 清理的警告：

1. `SYSTEM/build.prop` 中 `ro.yaap.device=haotian` 重复两次，值相同；
2. `VENDOR/build.prop` 中 `dalvik.vm.dex2oat64.enabled=true` 重复两次，值相同；
3. ODM 中三个 display/video 属性各重复两次，值相同；
4. 工具尝试从 boot ramdisk 读取 build props 时遇到空 cpio 或 WSL 非特权设备节点创建警告；
5. `PRODUCT/etc/vintf` 不存在，最终 framework VINTF 来自 SYSTEM/SYSTEM_EXT，检查结果仍为 `COMPATIBLE`。

这些重复属性目前没有值冲突，因此没有阻止 target-files 验证或 OTA 构建。为保持已冻结产物的可追溯性，本阶段没有在审计后修改属性并重建；它们已列入下一版清理项。

## 13. upper5 DSU 设计

### 13.1 为什么选择五分区

DSU 包包含：

```text
system
system_ext
product
vendor
odm
```

这能同时测试 YAAP framework/product、Xiaomi/Qualcomm vendor HAL、odm camera/厂商服务和相关 SELinux/VINTF 组合，比只替换 `system/system_ext/product` 的 upper3 DSU 更接近完整 ROM。

### 13.2 为什么没有加入 dlkm 和启动链

未加入：

- `system_dlkm`、`vendor_dlkm`：真机 DSU 期间仍运行当前第三方 6.6.143 内核，而 ROM 模块分区与 6.6.77 配套；加入会制造内核模块/KMI 不匹配；
- `boot`、`init_boot`、`vendor_boot`、`dtbo`、`recovery`：DSU 不接管启动链；
- `vbmeta`、`vbmeta_system`：五个 DSU 镜像使用各自独立、已验证的 Algorithm NONE hashtree footer；
- firmware：继续由已安装 HyperOS 3.0.304 提供，DSU 不写入固件分区。

因此 upper5 是在“保留当前内核/固件且不刷写”约束下的最大合理 profile，而不是机械地把所有动态分区塞进 ZIP。

### 13.3 DSU SPL footer 处理

源 ROM：

- system/system_ext/product AVB SPL：`2026-05-05`；
- vendor AVB SPL：`2026-02-01`；
- odm：没有 security_patch property；
- HyperOS 3.0.304 host SPL：`2026-06-01`。

为避免 host 对 DSU 上层分区的 SPL 降级判断，构建器仅将 system/system_ext/product 的 AVB property descriptor 改为 `2026-06-01`。它没有修改 ext4 内容，三者的 hashtree root digest 与源镜像完全相同。vendor 的 `2026-02-01` 原样保留，odm 不新增不存在的 SPL 属性。

这只是测试安装兼容处理，不代表 ROM 实际获得了 2026-06-01 的安全补丁。DSU manifest 明确记录了 source/staged SPL、源/目标哈希和 root digest。

### 13.4 DSU 成员哈希

| 成员 | 解压大小 | 压缩大小 | 解压后 SHA-256 |
|---|---:|---:|---|
| system.img | 1,137,766,400 | 469,406,507 | `89ee2614e2440189f008ae63b202cadba49231c7aced5ac515c7ca41bedb64e9` |
| system_ext.img | 552,861,696 | 221,249,554 | `74509805a1a43d6b33647a2180b2521b48db4c18cb86e334a2b3162857e97336` |
| product.img | 2,227,720,192 | 1,013,124,300 | `39280a4de33712a8886d47a90feb4bc905d40fc2946676b57d91df7bad711cb0` |
| vendor.img | 880,070,656 | 479,390,840 | `550f9b27090bdab49a3e27dc9cce692dced32a13f84378c1cc27d624253d8cda` |
| odm.img | 5,036,703,744 | 3,023,684,622 | `2c6ecbee9c86ea4ff69834b35ea65459c3568eb7416840924e195ca93196f270` |

独立审计结果：

```text
ZIP sidecar match: passed
exact member order: passed
duplicate members: false
ZIP CRC and decompressed hashes: passed
raw ext4: passed
e2fsck -fn: passed
AVB hashtrees: passed
AVB manifest equivalence: passed
source hashes: passed
source root digests unchanged: passed
runtime_validation: not_started
```

## 14. 尚待真机验证的项目

离线构建和结构检查无法证明以下运行行为：

- 首次开机、SystemUI、SetupWizard、GApps 登录；
- 汇顶指纹录入、解锁、熄屏唤醒和多次重启后的稳定性；
- 振动马达幅度、波形、通知/触感映射；
- HyperOS 相机、60 fps 录像、人像模式和相机 provider 稳定性；
- HDR 亮度、最低亮度、自动亮度和边缘误触；
- 通话、短信、5G/VoLTE/VoWiFi、双卡、Wi-Fi、蓝牙、GNSS、NFC；
- 音频路由、麦克风、扬声器、USB、充电、快充与温控；
- suspend/resume、功耗、发热、长时间稳定性；
- Play Integrity、Key Attestation、银行/金融/支付/网游应用行为；
- DSU 退出、回到 HyperOS 和数据隔离是否符合预期。

这些项目保持为 `not_started`，没有用“编译通过”代替“真机适配完成”。

## 15. 下一真机门禁（当前停在执行前）

收到明确指令后，下一步应先做只读 preflight，而不是立即刷入：

1. 确认设备序列号、当前槽位、HyperOS 3.0.304、bootloader 状态、当前 6.6.143 内核和可用空间；
2. 确认真机没有残留 DSU、OTA merge 或 snapshot 状态；
3. 备份当前 boot/init_boot/vendor_boot/dtbo/vbmeta/vbmeta_system 与关键数据恢复路径；
4. 先验证本地 DSU ZIP 与 sidecar SHA-256；
5. 首次只安装 upper5 DSU，不写 boot chain；
6. 设置单次启动/可撤销测试门禁并验证返回 HyperOS 的路径；
7. 按“启动 → 显示触控 → 通信 → 音频 → 指纹 → 振动 → 相机 → 传感器 → 完整性应用”顺序收集证据；
8. 任一早期关键门禁失败就终止后续高风险测试并返回 HyperOS。

本报告交付时停在第 1 步执行前，等待用户下一条真机指令。

## 16. 日志与证据索引

### 构建

```text
D:\Codex\haotian-rom-fusion-build\logs\stage-c-builds\yaap16-stage-c-frozen-release-attempt1.status
D:\Codex\haotian-rom-fusion-build\logs\stage-c-builds\yaap16-stage-c-frozen-release-attempt1.log
D:\Codex\haotian-rom-fusion-build\logs\stage-c-builds\yaap16-stage-c-pinned-manifest.xml
D:\Codex\haotian-rom-fusion-build\logs\stage-c-builds\stage-c-source-push-verified-2.log
```

### ROM/OTA 完整性

```text
D:\Codex\haotian-rom-fusion-build\logs\stage-c-integrity\core-final.status
D:\Codex\haotian-rom-fusion-build\logs\stage-c-integrity\core-summary.tsv
D:\Codex\haotian-rom-fusion-build\logs\stage-c-integrity\payload-apex-final.status
D:\Codex\haotian-rom-fusion-build\logs\stage-c-integrity\payload-apex-summary.tsv
D:\Codex\haotian-rom-fusion-build\logs\stage-c-integrity\artifact-sha256.txt
D:\Codex\haotian-rom-fusion-build\logs\stage-c-integrity\artifact_coherence.log
D:\Codex\haotian-rom-fusion-build\logs\stage-c-integrity\vintf.log
D:\Codex\haotian-rom-fusion-build\logs\stage-c-integrity\validate_target_files.log
D:\Codex\haotian-rom-fusion-build\logs\stage-c-integrity\avb.log
D:\Codex\haotian-rom-fusion-build\logs\stage-c-integrity\selinux.log
D:\Codex\haotian-rom-fusion-build\logs\stage-c-integrity\payload_signature_verify.log
D:\Codex\haotian-rom-fusion-build\logs\stage-c-integrity\payload_static_check.log
D:\Codex\haotian-rom-fusion-build\logs\stage-c-integrity\apex-results.tsv
```

### DSU

```text
D:\Codex\haotian-rom-fusion-build\logs\stage-c-dsu\yaap16-upper5-attempt1.status
D:\Codex\haotian-rom-fusion-build\logs\stage-c-dsu\yaap16-upper5-attempt1.log
D:\Codex\haotian-rom-fusion-build\logs\stage-c-dsu\yaap16-upper5-independent-audit.status
D:\Codex\haotian-rom-fusion-build\logs\stage-c-dsu\yaap16-upper5-independent-audit.log
```

### 管理仓库可复现入口

```text
D:\Codex\haotian-rom-fusion\scripts\Build-YAAP16StageC.sh
D:\Codex\haotian-rom-fusion\scripts\Audit-YAAP16StageC-Core.sh
D:\Codex\haotian-rom-fusion\scripts\Audit-YAAP16StageC-PayloadApex.sh
D:\Codex\haotian-rom-fusion\scripts\Build-MultiPartitionDsu.py
D:\Codex\haotian-rom-fusion\scripts\Audit-MultiPartitionDsu.py
D:\Codex\haotian-rom-fusion\configs\yaap16-dsu-upper5.json
D:\Codex\haotian-rom-fusion\evidence\yaap16-stage-c-first-rom.json
```

## 17. 最终判定

### 已达到

- 第一版 YAAP 16 haotian 完整 ROM 构建完成；
- 完整 A/B OTA 生成；
- OTA 与 target-files 同图、同 epoch、同 build number；
- VINTF、AVB、payload、APEX、APK 签名清单、动态分区和文件系统离线门禁通过；
- 五分区 DSU 生成并独立复核；
- 适配源码与复现配置进入 Git 管理；
- 没有触碰真机。

### 尚未达到

- 真机 boot success；
- 指纹、振动、相机等硬件运行闭环；
- `user`/release-keys 生产构建；
- 零 permissive SELinux policy；
- 正式 OTA/AVB 密钥、rollback policy 与密钥轮换方案；
- 银行/金融/网游环境可用性与完整性认证；
- 当前第三方 6.6.143 内核与完整 OTA 策略的最终选择。

因此，本阶段状态应标记为：

```text
OFFLINE_BUILD_AND_AUDIT = PASSED
DSU_PACKAGE = PASSED
DEVICE_RUNTIME_VALIDATION = NOT_STARTED
PRODUCTION_RELEASE_READY = NO
```
