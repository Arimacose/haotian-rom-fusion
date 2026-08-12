# haotian YAAP 16 预编译阶段审计报告

> 审计日期：2026-08-12（Asia/Shanghai）
> 当前阶段：源码闭环与静态预检
> 编译状态：未启动，源码根目录中没有 `out/`
> 真机状态：本阶段没有执行 ADB、Fastboot、重启、刷写或分区操作

## 1. 结论摘要

本阶段已把 haotian 的活动产品路线从历史 EvolutionX 试验线迁移为 **YAAP 16 + AOSP-first** 路线，并完成首轮编译之前能够静态完成的源码闭环：

1. YAAP `sixteen` 源码已完整同步并锁定为 **1148 个唯一项目**；平台基准为 `android-16.0.0_r4`。
2. haotian 产品名已从 `lineage_haotian` 迁移为 `yaap_haotian`，产品继承链进入 `vendor/yaap/config/common_full_phone.mk`。
3. HyperOS `OS3.0.304.0.WOBCNXM` 继续作为 firmware、vendor/odm proprietary、boot chain、内核/DTB/DTBO 的权威硬件基线。
4. 补齐了 SM8750 音频、显示、Data IPA、厂商 sepolicy、Xiaomi hardware 等 13 个源项目；Lineage 名称只保留在硬件兼容接口、策略和 CAF 项目仓库命名中，不构成产品平台基座。
5. 恢复了设备树已经引用、而 YAAP 上游缺位的 charging-control health AIDL 与最小策略集合。
6. 音频模块闭环完成：`libaudiohalvendorextn`、`qtiaudiohalvendorextn` 由 Qualcomm commonsys 源码提供；`libsoundtriggerhal.qti` 从 3.0.304 stock vendor 精确提取并生成 Soong 模块。
7. 两棵 proprietary vendor staging 树与 D 盘权威副本逐文件校验和差异均为 0。
8. 内核、DTBO 与确定性 kernel-header 归档通过固定 SHA-256、条目数和权限检查。
9. 最终静态验证为 **102 checks / 100 pass / 0 fail / 2 pending**。两项 pending 都是首次构建前的显式产品决策：AVB 私钥落位与 GApps/MicroG profile 选择。

这表示源码已进入“允许准备首次构建”的状态；它仍不是“已成功构建”或“已通过真机验收”的结论。

## 2. 审计边界与证据等级

### 2.1 本次实际执行

- 检查 WSL、Repo、Git LFS、Java、Python 与资源配置；
- 核验已同步源码、resolved manifest 和所有关键项目提交；
- 创建并推送 haotian 所需的 YAAP 设备树分支；
- 同步局部缺失依赖项目；
- 生成并校验 proprietary vendor 树中的 Sound Trigger HAL；
- 生成确定性 kernel header 归档；
- 对 1148 个 Repo 工作树执行只读清洁度审计；
- 执行 Python/XML/JSON/Git/哈希/文件树级静态检查；
- 更新管理仓库的 manifest、脚本、证据与文档。

### 2.2 本次明确保持未执行

- `source build/envsetup.sh`；
- `lunch`；
- Soong bootstrap、Ninja、`m yaap` 或镜像生成；
- ADB、Fastboot、DSU 安装、槽位切换、重启和刷写；
- 银行、金融、游戏、相机、指纹、振动、显示、通话等运行时验收。

### 2.3 证据解释

- **实测**：命令产生了可复核输出、哈希或机器可读证据。
- **源码闭环**：被设备树显式引用的关键项目和模块已经在源码树中定位。
- **待编译确认**：只有 Soong 完整解析或真实构建才会暴露的条件依赖、生成模块和链接问题。
- **待运行确认**：需要后续受控 DSU/真机阶段验证的 HAL、SELinux、传感器与应用兼容性。

## 3. 当前工作对象

| 对象 | 路径或值 | 状态 |
|---|---|---|
| WSL 发行版 | `Ubuntu-ROMBuild` | 可用 |
| YAAP 源码根目录 | `/home/arima/android/yaap16` | 已同步 |
| 管理仓库 | `D:\Codex\haotian-rom-fusion` | `agent/yaap16-platform-bringup` |
| 官方 3.0.304 dump | `D:\Codex\haotian-rom-fusion-build\stock-3.0.304-dump` | 只读输入 |
| proprietary 权威 staging | `D:\Codex\haotian-rom-fusion-build\source\vendor\xiaomi` | 已核验 |
| WSL proprietary staging | `/home/arima/android/yaap16/vendor/xiaomi` | 与 D 盘内容一致 |
| resolved manifest | `D:\Codex\haotian-rom-fusion\manifests\resolved\yaap16-haotian-20260812.xml` | 1148 项目 |
| 构建输出 | `/home/arima/android/yaap16/out` | 不存在 |

WSL 当前配置为 24 GB RAM、28 个逻辑处理器、32 GB swap；基线采集时源码工作区为 `201,557,383,874` 字节，WSL 文件系统可用空间为 `817,546,805,248` 字节。

## 4. 平台与产品迁移

### 4.1 平台选择

活动平台是 YAAP 官方 `sixteen` manifest，其初始化来源为：

```text
https://github.com/yaap/manifest.git
branch: sixteen
AOSP tag: android-16.0.0_r4
```

YAAP 上游 manifest 自带 AOSP/YAAP 平台主体、GMS、MicroG、主题和常规 Qualcomm 公共项目。haotian local manifest 只替换需要维护的 fork，并添加设备专属或 SM8750 缺失项目。

### 4.2 产品定义

`device/xiaomi/haotian` 已完成以下迁移：

- `lineage_haotian.mk` → `yaap_haotian.mk`；
- `PRODUCT_NAME := yaap_haotian`；
- 继承 `vendor/yaap/config/common_full_phone.mk`；
- 注册 `user`、`userdebug`、`eng` 三种 lunch choice；
- 保留 Xiaomi 15 Pro 型号 `2410DPN6CC` 与 3.0.304 stock identity；
- 移除产品定义对 `vendor/lineage/config` 的平台继承。

这条继承链决定了 ROM 的平台行为来自 YAAP/AOSP；设备树中残留的 `org.lineageos.*`、`vendor.lineage.*` 或 Lineage 仓库名属于 ABI/服务兼容标识。

## 5. Git 分支与固定提交

### 5.1 自主管理 fork

| 源码路径 | 分支 | 固定提交 | 本阶段作用 |
|---|---|---|---|
| `vendor/yaap` | `haotian-16` | `32d6a6d1016b98d6435c5ce674ae7c236dc5acb7` | YAAP 平台 fork |
| `device/xiaomi/haotian` | `yaap-16` | `534e15a4b4fc49672826e2c99d1fcad1d64e5802` | YAAP 产品迁移 |
| `device/xiaomi/sm8750-common` | `yaap-16` | `dfd356f8146b7343b079a88ea2d106ef8deb0027` | YAAP identity + stock Sound Trigger HAL 清单 |
| `device/xiaomi/haotian-kernel` | `yaap-16` | `802915cc6b269c3bf577327c4c165c3117852ff5` | 官方一致的 prebuilt kernel 组合 |
| `hardware/lineage/interfaces` | `haotian-16` | `28295cf95f2b055ebd2cf912f469f70f0558eb24` | 最小 charging-control health AIDL |
| `device/lineage/sepolicy` | `haotian-16` | `4aa6646b41042e19d9238034ed202d9a6b1a5ed9` | 对应最小 SELinux policy surface |

### 5.2 固定的 SM8750/厂商依赖

| 类别 | 源码路径 | 固定提交 |
|---|---|---|
| sepolicy | `device/qcom/sepolicy_vndr/sm8750` | `b5c02660d4e410403385bbdd33185ae3261c7ec8` |
| audio | `hardware/qcom-caf/sm8750/audio/agm` | `853c0f6afd242b506636c9af47cb4ed64a4056f0` |
| audio | `hardware/qcom-caf/sm8750/audio/graphservices` | `62591b81ddb14cb1ddecf2a8e7162f2082456793` |
| audio | `hardware/qcom-caf/sm8750/audio/pal` | `39f7cccd8bbd3e51b71431e574fb38651be23cae` |
| audio | `hardware/qcom-caf/sm8750/audio/primary-hal` | `443dec4613a7e5dbc997eb2d7b087f0f07ae5258` |
| data | `hardware/qcom-caf/sm8750/data-ipa-cfg-mgr` | `5c754092b8e85dd72904b9a5c62a687bae9ce627` |
| data | `hardware/qcom-caf/sm8750/dataipa` | `c6206833bd59478caaa0a69e9d71f1bbfa866a96` |
| display | `hardware/qcom-caf/sm8750/display/core` | `20cf597e21bdd31af4e3a55660e991e22f69bf8b` |
| display | `hardware/qcom-caf/sm8750/display/hal` | `4b74f47925c54e95c805275832a65830af0431b6` |
| display | `hardware/qcom-caf/sm8750/display/intf` | `19b5c055b40bc3d7af4309662eea98c7e7a72cee` |
| Xiaomi HAL | `hardware/xiaomi` | `892a1cded9c7bf89adf4700af5dfca099ec54782` |
| audio extension | `vendor/qcom/opensource/commonsys/audio` | `af06e9427170c7cf089a2f8306dec026d20aba0c` |
| audio interface | `vendor/qcom/opensource/commonsys-intf/audio` | `7d983f8254cb84c0460e2460bd4fca1cc10a0899` |

## 6. 音频依赖闭环

### 6.1 根因

对设备树 `PRODUCT_PACKAGES` 和源码模块名进行静态交叉检查后，最后剩余的三个直接音频依赖是：

- `libaudiohalvendorextn`；
- `qtiaudiohalvendorextn`；
- `libsoundtriggerhal.qti`。

前两个属于 Qualcomm commonsys audio 源码模块，第三个是 Xiaomi/Qualcomm stock vendor HAL。

### 6.2 处理结果

1. local manifest 加入 `android_vendor_qcom_opensource_audio` 与 `android_vendor_qcom_opensource_audio-commonsys-intf`；
2. 前两个模块分别在 `vendor/qcom/opensource/commonsys/audio/hal_adapter/Android.bp` 中获得定义；
3. common proprietary 清单加入：

```text
vendor/lib64/hw/libsoundtriggerhal.qti.so;DISABLE_DEPS
```

4. 从 3.0.304 stock vendor dump 提取该 ELF，并由 `extract-utils` 生成：
   - `cc_prebuilt_library_shared { name: "libsoundtriggerhal.qti" }`；
   - `sm8750-common-vendor.mk` 的 `PRODUCT_PACKAGES` 条目；
   - `relative_install_path: "hw"`、`soc_specific: true`、`check_elf_files: false`。

### 6.3 可核验值

| 项目 | 值 |
|---|---|
| 文件大小 | `242,232` 字节 |
| 3.0.304 源 SHA-256 | `387afadf222ca499c924c17ba9966bd1750ee1cad2a1f4f543d328c7098ef553` |
| WSL staging SHA-256 | `387afadf222ca499c924c17ba9966bd1750ee1cad2a1f4f543d328c7098ef553` |
| 模块声明 | 已生成 |
| product package | 已生成 |
| D 盘 ↔ WSL 内容差异 | `0` |

这里的 `DISABLE_DEPS` 是设备树延续 stock vendor HAL 的明确选择：Soong 保留预编译 ELF，不依据当前开源树重新推导其完整 NEEDED 图；真实加载与服务注册仍归入后续运行时验收。

## 7. Charging Control 兼容层

common 设备树引用 `vendor.lineage.health-service.default` 和 `hal_lineage_health_default`，而 YAAP `hardware_lineage_interfaces` 上游分支没有对应 `health/` 子树。为保持充电控制、夜间充电等硬件功能，当前 fork 只导入：

- `vendor.lineage.health` AIDL；
- 默认 charging-control service；
- 必需的 public attribute；
- service type/context；
- default domain 与 executable file context。

没有导入 Lineage Settings、SystemUI、Updater、SDK 或产品继承链。因此它是设备 HAL ABI 兼容层，而不是 Lineage 平台基座。

## 8. Proprietary vendor 树

| 树 | 文件数 | 总字节数 | D 盘 ↔ WSL checksum delta |
|---|---:|---:|---:|
| `vendor/xiaomi/haotian` | 3046 | 5,465,316,231 | 0 |
| `vendor/xiaomi/sm8750-common` | 1780 | 782,226,259 | 0 |
| **合计** | **4826** | **6,247,542,490** | **0** |

比较命令使用 `rsync -rHnci --delete`：递归、保留硬链接语义、checksum dry-run，并排除时间戳差异。该结果证明 WSL 构建输入和 D 盘 staging 的文件内容一致。

vendor 树暂时作为本地 proprietary 输入，不进入普通 Git 仓库。后续若创建专用 LFS 仓库，需要重新记录 LFS pointer、对象完整性和 resolved manifest revision。

## 9. 内核与 kernel headers

| 输入 | SHA-256 |
|---|---|
| `kernel` | `99485b0132e3aa28f4e965119591c8149fe3c20e7e0fd10d753ef014a582472e` |
| `dtbo.img` | `602f91eb634ad49d70c59d45a071358f37e02ded68db563efb9b25b4d7dfa804` |
| `prebuilt_kernel_headers.tar.gz` | `5466a76ca2c4b0dca9a6f02b60daccf772b01d876b4d952730dd38442b97f46f` |

header 归档有 1099 个 tar 条目，普通文件权限统一为 `0644`、目录统一为 `0755`，并同时保留大小写敏感的 `xt_CONNMARK.h` 与 `xt_connmark.h`。重复运行生成相同 SHA-256，避免 Windows staging 把普通文件统一成 `0755` 所造成的非内容差异。

## 10. 最终静态验证

机器可读结果：

```json
{
  "result": "pass",
  "checks": 102,
  "passed": 100,
  "failed": 0,
  "pending": 2,
  "compile_started": false
}
```

覆盖范围包括：

- resolved manifest 项目数与路径唯一性；
- 19 个关键源码项目的 manifest revision、实际 HEAD 和清洁状态；
- YAAP 产品名、继承链、lunch choices、bp4a release config 和 stock identity；
- health AIDL、service 与 SELinux policy token；
- 两棵 vendor 树的文件数、总字节数和必要生成文件；
- 三个关键音频模块、Sound Trigger proprietary 清单、生成模块、product package 与 ELF 哈希；
- kernel、DTBO、header archive SHA-256；
- header tar 条目、大小写文件对和规范化权限；
- AVB、GApps profile 与本阶段编译边界。

另外，`repo forall -j8` 对 1148 个项目执行 `git status --porcelain=v1` 后没有发现脏工作树。`repo status` 输出的两行仅表示 haotian 与 common 当前位于本地 `yaap-16` 分支。

## 11. 剩余两项构建前决策

### P1：GApps 或 YAAP 默认 MicroG 路线

YAAP 的当前逻辑是：

- `TARGET_BUILD_GAPPS=true`：继承 `vendor/google/gms/config.mk`；
- 其他情况：继承 `vendor/microg/microg.mk`，并启用 vanilla 应用与 overlay。

这会影响初始设置、Play 服务、Play Integrity、推送、备份、金融/游戏应用兼容性以及产物体积。选择应在首次 build graph 生成之前固定，并写入本地 build profile；当前审计把它保留为产品决策，而不是源码缺失。

### P2：AVB 私钥与发布 profile

`vendor/haotian/security/avb.pem` 当前尚未落位。私钥继续保存在管理仓库之外。首次 bring-up build 可以先使用明确标识的测试签名；任何可分发的 `user` 产物需要完整固定 AVB key、APK key、OTA key、rollback index 和 chained partition 描述。

## 12. 尚待后续阶段证明的事项

1. Soong 对全部 Android.bp/Android.mk 的实际模块图解析；
2. SELinux policy 编译与 neverallow；
3. VINTF manifest/matrix 合并后的兼容性；
4. 全量 ELF link 与 namespace；
5. system、system_ext、product、vendor、odm 的分区体积；
6. OTA target-files 与动态分区描述；
7. Goodix 指纹、振动、相机、通话音频、Sound Trigger、显示/HDR、触控边缘、亮度和传感器运行状态；
8. 银行、金融、游戏和 Play Integrity 相关应用环境表现。

## 13. 下一阶段执行顺序

用户允许启动编译后，按以下门顺序推进：

1. 固定 GApps/MicroG profile；
2. 固定首次构建 variant（建议 bring-up 用 `userdebug`，发布候选再切 `user`）；
3. 再跑 resolved manifest、Repo clean、LFS fsck、vendor checksum 与本脚本；
4. 先生成完整 Soong graph，处理命名、namespace、sepolicy、VINTF 和 ELF 问题；
5. 执行首个 `m yaap` 构建并保存完整日志、失败模块、峰值磁盘用量和产物哈希；
6. 编译通过后进行镜像静态审计；
7. 另开受控 DSU/真机验收阶段，先记录槽位、分区哈希、回滚材料和验收矩阵。

## 14. 交付物与哈希

| 文件 | SHA-256 |
|---|---|
| `manifests/haotian-yaap16.xml` | `edc6c66e7f8661ab6f8f5b1bb207bac9dc9a3f593a42d475056527ba17c887fb` |
| `manifests/resolved/yaap16-haotian-20260812.xml` | `88a1d09b88295fd1dffb2cd3d65006a2abc29fb2368f36c538b297af2068d2ca` |
| `evidence/yaap16-source-baseline.json` | `dd955a1ce092078967bfd770734401c6f3810b8fbe9fcd56b77587197f770f84` |
| `evidence/yaap16-prebuild-validation.json` | `d43b45a49267fa6d93fad1240ba1e2a91e423fe62772f0dab9f9d8c1667c74aa` |

对应绝对路径均位于：

```text
D:\Codex\haotian-rom-fusion
```

## 15. 参考来源

- YAAP 官方 manifest 与构建入口：<https://github.com/yaap/manifest>
- YAAP 官方设备树示例：<https://github.com/yaap/device_oneplus_waffle>
- LineageOS Android 16 项目片段参考：<https://github.com/LineageOS/android/blob/lineage-23.2/snippets/lineage.xml>
- LineageOS Xiaomi hardware：<https://github.com/LineageOS/android_hardware_xiaomi>
- haotian 维护者音频说明：<https://github.com/rep1ace/lineage-docs/blob/main/subsystems/audio.md>
- haotian 通话音频审计：<https://github.com/rep1ace/lineage-docs/blob/main/audits/2026-05-25-call-audio-xiaomi-services.md>
