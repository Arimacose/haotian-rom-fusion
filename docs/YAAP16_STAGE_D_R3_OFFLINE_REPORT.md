# YAAP 16 haotian Stage D r3：真机写入前离线交付报告

## 1. 当前结论与执行边界

Stage D r3 已完成以下离线工作：

- 修复 r2 真机启动阻塞暴露出的 SoundTrigger3 VINTF 缺位；
- 生成完整 YAAP 16 OTA 与 target-files；
- 完成 ROM 结构、签名、VINTF、AVB、文件系统、动态分区、SELinux、payload、APEX 和构建身份审计；
- 生成包含 `system`、`system_ext`、`product`、`vendor`、`odm` 的 upper5 多分区 DSU；
- 对 DSU ZIP 做独立的流式哈希、CRC、raw ext4、只读 `e2fsck`、AVB hashtree、manifest 等价性和源文件系统 root digest 审计；
- 从最终 DSU 的 `vendor.img` 再次提取并验证 SoundTrigger NDK 库与四个音频 VINTF fragment。

**离线阶段结论：通过。**

**真机阶段结论：尚未开始。** 按用户在 2026-08-14 设置的边界，本轮在任何 r3 真机代理开启、文件传输、DSI 擦除/安装/启用或重启之前暂停。离线通过不等于真机启动和完整功能矩阵通过，目标仍保持活动状态。

---

## 2. r2 启动失败的精确根因

第三次 DSU 验证已证明五个目标分区都由 DSU 动态映射并实际挂载：

| 分区 | 真机设备映射 | 挂载点 |
|---|---|---|
| system | `/dev/block/dm-9` | `/` |
| system_ext | `/dev/block/dm-10` | `/system_ext` |
| product | `/dev/block/dm-11` | `/product` |
| vendor | `/dev/block/dm-12` | `/vendor` |
| odm | `/dev/block/dm-13` | `/odm` |

r2 已经修复了上一轮 `android.hardware.soundtrigger3-V1-ndk.so` 缺失问题；库能够被动态链接，Audio Core 与 Audio Effect 也能注册。但随后出现第二层阻塞：

```text
Could not find android.hardware.soundtrigger3.ISoundTriggerHw/default
in the VINTF manifest. No alternative instances declared in VINTF.
```

直接后果为：

1. `libsoundtriggerhal.qti.so` 成功加载；
2. `audiohalservice.qti` 尝试注册 `android.hardware.soundtrigger3.ISoundTriggerHw/default`；
3. `servicemanager` 因设备 manifest 未声明该实例而返回 `status=-3`；
4. mandatory `sthal` 注册反复重试并使 `audiohalservice.qti` 周期性退出/重启；
5. `system_server` 停留在 `StartAudioService`；
6. `sys.boot_completed` 始终为空，启动动画持续运行。

失败证据位于：

- `D:\Codex\haotian-rom-fusion-build\logs\stage-d-dsu-runtime\20260814-third-yaap-upper5-r2\r2-stuck-logcat-all.txt`
- `D:\Codex\haotian-rom-fusion-build\logs\stage-d-dsu-runtime\20260814-third-yaap-upper5-r2\r2-stuck-dmesg.txt`
- `D:\Codex\haotian-rom-fusion-build\logs\stage-d-dsu-runtime\20260814-third-yaap-upper5-r2\r2-tombstones.tgz`
- `D:\Codex\haotian-rom-fusion-build\logs\stage-d-dsu-runtime\20260814-third-yaap-upper5-r2\r2-stuck-capture-summary.json`

这与此前“多重启一次导致 one-shot DSU 退出”的流程错误是两个彼此独立的问题：重新启用槽并只重启一次后，r2 确实进入了 YAAP；随后才暴露上述 VINTF 根因。

---

## 3. r3 源码修复

### 3.1 官方声明来源

官方 HyperOS 3.0.304 dump 中存在：

`D:\Codex\haotian-rom-fusion-build\stock-3.0.304-dump\vendor\etc\vintf\manifest\soundtrigger.qti.xml`

原始文件 SHA-256：

`ee90b3c8d28da16e0527b4645b29a6bb6269efa93aff0abc880b9fd375351c06`

核心声明为：

```xml
<hal format="aidl">
    <name>android.hardware.soundtrigger3</name>
    <fqname>ISoundTriggerHw/default</fqname>
</hal>
```

### 3.2 可重复生成方案

设备树修改：

1. 在 `proprietary-files.txt` 中把官方 `soundtrigger.qti.xml` 以 `EXTRACT_ONLY` 方式提取为唯一名称 `soundtrigger_haotian_stock.xml`；
2. 在 `extract-files.py` 的 `AUDIO_VINTF_FRAGMENTS` 映射中，把该 fragment 绑定到首选预编译模块 `libsoundtriggerhal.qti`；
3. 重新生成 `vendor/xiaomi/sm8750-common/Android.bp`；
4. 保留 r2 已修复的完整 ELF 依赖闭包，其中包含 `android.hardware.soundtrigger3-V1-ndk`。

两轮 `extract-files.py -m` 后生成的 `Android.bp` 哈希都为：

`9db420071dc68c6870a177c75b1a94249f70490df0d3ba63aebc3c8ab8b7f2c1`

说明生成过程幂等。

Soong 安装阶段会通过 `assemble_vintf` 把输入来源注释更新为实际 proprietary 路径，并把 manifest 元版本规范化为 `9.0`；规范化后的安装文件 SHA-256 为：

`938ee61487b12e7a4e73e36312e89da7ec1940fa52979b9aae5274831bdfc1e4`

XML 声明语义保持不变。

### 3.3 Git 证据

- 仓库：`https://github.com/Arimacose/device_xiaomi_sm8750-common.git`
- 分支：`agent/audio-vintf-soundtrigger-fix`
- r3 提交：`d9f4811de4278182e61119f1daaab7cea2971a9b`
- 提交标题：`audio: attach stock SoundTrigger3 VINTF fragment`
- 远端推送：完成
- 工作树：干净

---

## 4. 完整 ROM 构建结果

固定构建参数：

| 参数 | 值 |
|---|---|
| Product/variant | `yaap_haotian-bp4a-userdebug` |
| `TARGET_BUILD_GAPPS` | `true` |
| Build number | `haotian.staged.20260814.3` |
| Build epoch | `1786687200` |
| 完整构建命令 | `m -j16 bacon target-files-package` |
| 完整构建耗时 | 527 秒（8 分 47 秒） |
| 结果 | 成功 |

### 4.1 OTA

- WSL 路径：`/home/arima/android/yaap16/out/target/product/haotian/YAAP-16-HOMEMADE-haotian-20260814.zip`
- 大小：`4,836,798,323` 字节
- SHA-256：`c2b19d7ea13cc3e538219521f025dc6b1044666fa36917ed134d7356e8684bb6`

### 4.2 target-files

- WSL 路径：`/home/arima/android/yaap16/out/target/product/haotian/obj/PACKAGING/target_files_intermediates/yaap_haotian-target-files.zip`
- 大小：`21,038,189,277` 字节
- SHA-256：`45e1ebb4a42db8a016b13003a97a769b9f7332f64848c445b5bfdd8457f8edb8`

完整构建日志：

`D:\Codex\haotian-rom-fusion-build\logs\stage-d-r3-full-build.log`

日志 SHA-256：

`d6f38d555e2294564d0eea16151d2eb6f45b6f90eb5b8d9ea108ca5928dabc88`

---

## 5. ROM 离线审计结果

### 5.1 核心审计：14/14 通过

| 检查 | 结果 |
|---|---|
| 输入存在性与路径 | 通过 |
| OTA、target-files、各镜像哈希 | 通过 |
| OTA ZIP 结构、成员唯一性、CRC、streaming payload | 通过 |
| OTA 与 target-files 构建身份一致性 | 通过 |
| OTA whole-file 与 payload 签名 | 通过 |
| target-files ZIP CRC | 通过 |
| APK 签名清单 | 通过 |
| `check_target_files_vintf` | 通过 |
| `validate_target_files` | 通过 |
| AVB descriptor、footer、hashtree | 通过 |
| 文件系统类型与只读结构检查 | 通过 |
| 动态分区元数据 | 通过 |
| SELinux policy | 通过 |
| build number、epoch、fingerprint 等身份字段 | 通过 |

摘要：

`D:\Codex\haotian-rom-fusion-build\logs\stage-d-r3-integrity\core-summary.tsv`

SHA-256：`d0545c83f03fa54dbc11dc8f1dc037a4688f3a75c47f989ace97b712bf06aa45`

### 5.2 payload/APEX 审计：6/6 通过

| 检查 | 结果 |
|---|---|
| payload 提取 | 通过 |
| payload properties 重算一致性 | 通过 |
| payload 对 target-files 的签名与分区重放验证 | 通过 |
| payload 静态结构检查 | 通过 |
| payload 分区操作信息 | 通过 |
| APEX 清单与签名检查 | 通过 |

摘要：

`D:\Codex\haotian-rom-fusion-build\logs\stage-d-r3-integrity\payload-apex-summary.tsv`

SHA-256：`135ede5110e556e40d7ad8b57eaa46a702b34b767890f5ebfbd4cf52e9c56260`

### 5.3 音频 VINTF 端到端审计

以下四个唯一命名 fragment 在 target-files 目录、target-files ZIP 和 `vendor.img` 中逐字节一致：

1. `audioeffectservice_haotian_stock.xml`
2. `manifest_audiocorehal_haotian_stock.xml`
3. `manifest_audio_qti_services_haotian_stock.xml`
4. `soundtrigger_haotian_stock.xml`

验证的关键声明包括 Audio Core、Audio Effect、QTI PAL/AGM/ListenSoundModel，以及：

`android.hardware.soundtrigger3 / ISoundTriggerHw/default`

OTA payload 对 `vendor` 分区的重放哈希为：

`957ad319153e7ce806829a07be1086049dcce3b02c371166ce788021e7d437a3`

与 target-files 的 `vendor.img` 完全一致。

日志：`D:\Codex\haotian-rom-fusion-build\logs\stage-d-r3-integrity\audio-vintf-end-to-end.log`

### 5.4 SoundTrigger 依赖与 VINTF 闭包

以下层级全部通过：

- `proprietary-files.txt` 中不存在 `libsoundtriggerhal.qti.so;DISABLE_DEPS`；
- 生成的 `Android.bp` 同时引用 SoundTrigger V1 NDK 库和新 VINTF fragment；
- blob 的 ELF `DT_NEEDED` 包含 `android.hardware.soundtrigger3-V1-ndk.so`；
- SoundTrigger V1 NDK 库在 product out、target-files 目录、target-files ZIP、`vendor.img` 四层逐字节一致；
- 官方 manifest 输入与 proprietary 提取文件逐字节一致；
- 规范化后的 manifest 在 product out、target-files 目录、target-files ZIP、`vendor.img` 四层逐字节一致；
- payload vendor 重放、VINTF 主审计均通过。

日志：`D:\Codex\haotian-rom-fusion-build\logs\stage-d-r3-integrity\soundtrigger-closure.log`

---

## 6. r3 upper5 DSU 成品

### 6.1 主包

- 路径：`D:\Codex\haotian-rom-fusion-build\dsu\yaap16-staged-upper5-host304-soundtrigger-vintf-r3\YAAP-16-20260814-haotian-upper5-host304-soundtrigger-vintf-r3-mpDSU.zip`
- 大小：`5,206,968,898` 字节
- SHA-256：`e801e1edbef68d5d0cfc7936ac5730a040b72bccb1a1d2b4d28a29411dc8b056`
- ZIP 成员顺序：`system.img` → `system_ext.img` → `product.img` → `vendor.img` → `odm.img`
- 重复成员：无
- DSU 生成耗时：`1,648` 秒

### 6.2 配套文件

| 文件 | SHA-256 |
|---|---|
| `...mpDSU.zip.manifest.json` | `7006d5ad70ba37a5ad5b1b595e6840f16d953fd08ad5bdcf9cfed87535fbf882` |
| `...mpDSU.zip.sha256` | `43d842ea98049dd20b4c25c0dd791c012197d24069866310ee8244c89b48f32f` |
| `...mpDSU.zip.audit.json` | `8632ed6a21c5af540830327a96d257fda1bd57afabe6e26cf1614c2201c4f7a3` |

### 6.3 分区审计明细

源镜像 SHA-256 是完整 ROM target-files 中的镜像；staged SHA-256 是只重建 DSU 兼容 AVB footer 后写入 ZIP 的镜像。文件系统 root digest 保持不变。

| 分区 | 大小 | 源镜像 SHA-256 | DSU staged SHA-256 | ext4 root digest |
|---|---:|---|---|---|
| system | 1,137,987,584 | `0e34e3cc68c889d718e8e253ba82f5d23ab6e7c20d2fa50ec52279c3ad183a3d` | `e484e0b263dd4baaf4e1ee14a56d331038f53f8ee9b084e06a38f6ae8cbfb253` | `0e16136d91d4503e2f125fa0a62187db00106cb1` |
| system_ext | 552,861,696 | `782df345350b3a58e3be471456ab1b924de6e55e70bcaf4a0d658f3fb8989dbd` | `f4887972ffe1d76a54b9e03361345bde218847893bf79add76efd0e5c0171185` | `1fafc2b74ec69b931d3df8a06dbb4499aa2f650d` |
| product | 2,227,720,192 | `d034b0be2274be4b9c305dc10ec2d33127ed63de171fa532dc5bf17ba0a4b697` | `c65165eeea5670450957ebf4ed1ac13f394f6ebe334c43d3222adfcaaa40e3ad` | `55cdb7f43c94c390b23542dac8484c58391e8113` |
| vendor | 880,304,128 | `957ad319153e7ce806829a07be1086049dcce3b02c371166ce788021e7d437a3` | `18f8a49842456ccfca926b236e6331ab68c94265afacd10523d824227e778766` | `e2436834fae1ce29cabb55ed26ab367c0487e258` |
| odm | 5,036,703,744 | `04d2890c96adf3379fbcafb091909b4f2613529e3f17000c73207ef203afaf4d` | `36697e59153d2d7259cb7394821c7d311689875dfa60a0086a4e5ac570f0d573` | `30038b8d75c1c01ea6364a4789d93f410fd244c3` |

五个分区均满足：

- raw ext4；
- ZIP CRC 与流式 SHA-256 通过；
- 只读 `e2fsck` 通过；
- AVB Algorithm `NONE` footer 与 hashtree 验证通过；
- package manifest 与实际镜像一致；
- 源文件系统 root digest 未改变。

独立审计报告：

`D:\Codex\haotian-rom-fusion-build\dsu\yaap16-staged-upper5-host304-soundtrigger-vintf-r3\YAAP-16-20260814-haotian-upper5-host304-soundtrigger-vintf-r3-mpDSU.zip.audit.json`

### 6.4 最终 DSU vendor 内容复核

从最终 ZIP 的 `vendor.img` 中重新提取并确认：

- `android.hardware.soundtrigger3-V1-ndk.so` SHA-256 为 `11a3ecb090a2eabe6c940a03b1bc01bef95b95e94aa3b0ec0f804879d07fb6c0`；
- 四个音频 VINTF fragment 均存在且与 target-files 一致；
- `soundtrigger_haotian_stock.xml` 声明 `android.hardware.soundtrigger3 / ISoundTriggerHw/default`；
- 三个旧的冲突安装名以及 `soundtrigger.qti.xml` 旧名不在最终 vendor manifest 目录中。

日志：`D:\Codex\haotian-rom-fusion-build\logs\stage-d-r3-integrity\dsu-packed-vendor.log`

---

## 7. 有意省略的分区

| 省略项 | 原因 |
|---|---|
| `system_dlkm`、`vendor_dlkm` | DSU 继续使用真机已安装的第三方 6.6.143 内核。加载为 ROM 预编译 6.6.77 内核生成的模块分区会引入不必要的 KMI/模块不匹配。 |
| `boot`、`init_boot`、`vendor_boot`、`dtbo`、`recovery` | DSU 不接管启动链。 |
| `vbmeta`、`vbmeta_system` | 五个 DSU 镜像各自携带并通过验证的 Algorithm NONE hashtree footer；完整 OTA vbmeta 链还依赖被省略的 boot/dlkm 分区。 |
| firmware | HyperOS `OS3.0.304.0.WOBCNXM` 固件继续作为权威底层，不由 DSU 写入。 |

这正是 upper5 DSU 的测试边界，并不代表这些省略分区已经获得真机 ROM 刷入验收。

---

## 8. 真机边界状态

最后一次已确认的设备状态来自 r2 退出记录，时间为 `2026-08-14 16:42:19 +08:00`：

- 系统：`OS3.0.304.0.WOBCNXM`
- `sys.boot_completed=1`
- `ro.gsid.image_running=0`
- 手机全局代理：`:0`
- 临时 `192.168.41.222:17897` 中继监听数：`0`
- 原 Mihomo：`127.0.0.1:7897` 保持运行

证据：

`D:\Codex\haotian-rom-fusion-build\logs\stage-d-dsu-runtime\20260814-third-yaap-upper5-r2\r2-exit-proxy-rollback.txt`

此后没有为 r3 执行任何真机写入、代理开启、DSI 擦除/安装/启用或重启。本报告只陈述该时间点的最后确认状态，不把它冒充为后续实时查询结果。

---

## 9. 下一次恢复目标时的第一阶段

收到用户继续真机验收的指令后，按以下门槛恢复：

1. 只读复核当前设备仍在 HyperOS、ADB 唯一设备、底包与内核身份、存储、电量、旧 DSI 状态；
2. 清理仍安装但 disabled 的 r2 DSI，确认空间回收；
3. 建立临时 Mihomo Wi-Fi 全局代理，并分别验证 PC 上游、临时中继、手机 TCP 和手机三项代理设置；
4. 把**上述精确 SHA-256 的 r3 DSU**传输到设备，设备端重算哈希；
5. 安装 r3 槽；
6. 修正此前的流程错误：如果安装界面已经自动进入目标构建，监控器不得再重启；如果仍在 HyperOS，则只允许发出一次进入 DSU 的重启；
7. 先验证 `haotian.staged.20260814.3`、五个 `_gsi` 映射、`sys.boot_completed=1`、SoundTrigger/audio HAL 稳定和无重复 tombstone；
8. 再执行显示、触控、Wi-Fi、移动网络、蓝牙、音频输入输出、振动、传感器、定位、相机、指纹、USB、休眠唤醒、SELinux、GMS 和持续稳定性矩阵；
9. 退出 DSU 后清除手机代理、停止临时中继并再次确认 HyperOS。

在完成上述真机矩阵之前，不会把“兼容完整、核心功能全部可用”标记为已通过。
