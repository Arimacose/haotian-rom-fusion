# haotian YAAP 16 AOSP-first Bring-up

本仓库管理 Xiaomi 15 Pro（设备代号 `haotian`）的 YAAP 16 源码适配、可复现 manifest、静态证据、自动化检查与后续发布门禁。

## 当前活动路线

- **平台基座**：YAAP `sixteen`，AOSP `android-16.0.0_r4`；
- **产品名称**：`yaap_haotian`；
- **硬件基线**：HyperOS `OS3.0.304.0.WOBCNXM`；
- **源码根目录**：`/home/arima/android/yaap16`（WSL `Ubuntu-ROMBuild`）；
- **管理分支**：`agent/yaap16-platform-bringup`；
- **当前边界**：第一版完整 A/B 开发 OTA 与 upper5 多分区 DSU 已完成构建和离线审计；真机安装与运行验证尚未启动。

EvolutionX、LineageOS 与 DerpFest 的历史拆包和对比仍作为适配证据保留。其中的硬件实现可以按模块审查后迁移；它们不再作为当前 ROM 的产品平台基座。

## 已完成

- [x] YAAP 16 完整源码同步；
- [x] 去重 local manifest 与 1150-project resolved manifest；
- [x] `lineage_haotian` → `yaap_haotian` 产品迁移；
- [x] 设备树、common、kernel、YAAP、health AIDL 与 health sepolicy fork；
- [x] SM8750 audio/display/data/sepolicy 与 Xiaomi hardware 源码闭环；
- [x] 3.0.304 proprietary vendor 树落位；
- [x] stock `libsoundtriggerhal.qti` 清单、ELF、Soong module 与 product package 闭环；
- [x] 可重复 kernel-header 归档；
- [x] 1150 个 Repo 项目 manifest/revision 审计；
- [x] 111 项静态预检：110 pass、0 fail、1 个历史阶段 pending；
- [x] 固定 `TARGET_BUILD_GAPPS=true` 与 `yaap_haotian-bp4a-userdebug`；
- [x] `m -j16 nothing` 首次 graph 通过，并在设备树提交态复验通过；
- [x] 确认 graph 阶段没有生成 `.img/.zip/.bin` 产品文件。
- [x] 固定同一构建图执行 `m -j16 bacon target-files-package`，生成完整 A/B OTA 与 target-files；
- [x] 核心完整性门禁 14/14 通过：VINTF、AVB、SELinux、文件系统、动态分区、签名和跨产物一致性均有独立日志；
- [x] Payload/APEX 门禁 6/6 通过，45 个 payload 分区重放一致，38 个 APEX/CAPEX 通过双重验证；
- [x] 生成 `system + system_ext + product + vendor + odm` upper5 DSU，并通过独立重新解压、哈希、ext4、AVB 和 root digest 审计；
- [x] Stage C 全程保持真机零写入，运行验证状态固定为 `not_started`。

## 当前 profile 与发布决策

1. **Google profile**：首次 graph 已固定 `TARGET_BUILD_GAPPS=true`；
2. **开发签名**：本地 `userdebug` AVB 开发键已落位，私钥在管理 Git 之外；
3. **生产签名**：AVB、APK、OTA key 及 rollback/chained partition 策略留给 release-hardening gate。

## 核心路径

```text
D:\Codex\haotian-rom-fusion
D:\Codex\haotian-rom-fusion-build\stock-3.0.304-dump
D:\Codex\haotian-rom-fusion-build\source\vendor\xiaomi
/home/arima/android/yaap16
```

大文件、官方镜像、proprietary blobs、构建输出、私钥和每机校准数据保留在 Git 仓库之外；Git 只保存源码修改、manifest、脚本、哈希、证据和报告。

## 静态预检

```powershell
wsl -d Ubuntu-ROMBuild -- bash -lc "python3 `
  /mnt/d/Codex/haotian-rom-fusion/scripts/Validate-YaapPrebuild.py `
  --source /home/arima/android/yaap16 `
  --resolved-manifest /mnt/d/Codex/haotian-rom-fusion/manifests/resolved/yaap16-haotian-20260812.xml `
  --output /mnt/d/Codex/haotian-rom-fusion/evidence/yaap16-prebuild-validation.json `
  --gapps-profile gapps"
```

预期结果：

```json
{"result":"pass","checks":111,"passed":110,"failed":0,"pending":1,"compile_started":true}
```

## 文档入口

- [`docs/YAAP16_STAGE_C_FIRST_ROM_REPORT.md`](docs/YAAP16_STAGE_C_FIRST_ROM_REPORT.md)：第一版完整 OTA、45 分区 payload、14/14 核心审计、6/6 Payload/APEX 审计、upper5 DSU、风险与真机前门禁；
- [`evidence/yaap16-stage-c-first-rom.json`](evidence/yaap16-stage-c-first-rom.json)：Stage C 产物、哈希、提交、门禁、日志及运行边界的机器可读证据；
- [`manifests/resolved/yaap16-haotian-stage-c-20260813.xml`](manifests/resolved/yaap16-haotian-stage-c-20260813.xml)：生成 Stage C 产物时固定的完整 resolved manifest；
- [`docs/YAAP16_PREBUILD_AUDIT.md`](docs/YAAP16_PREBUILD_AUDIT.md)：本阶段完整审计、提交、模块闭环、验证结果与风险边界；
- [`docs/YAAP16_BUILD_BOOTSTRAP.md`](docs/YAAP16_BUILD_BOOTSTRAP.md)：可复现同步、vendor staging、kernel headers、预检及下一阶段 build gate；
- [`docs/YAAP16_SOONG_GRAPH_REPORT.md`](docs/YAAP16_SOONG_GRAPH_REPORT.md)：首次固定 GApps/userdebug graph 的迭代、修正、哈希与边界；
- [`manifests/haotian-yaap16.xml`](manifests/haotian-yaap16.xml)：活动 local manifest；
- [`manifests/resolved/yaap16-haotian-20260812.xml`](manifests/resolved/yaap16-haotian-20260812.xml)：固定 1150 项目 revision；
- [`evidence/yaap16-source-baseline.json`](evidence/yaap16-source-baseline.json)：源码、主机、LFS、vendor 与工作树基线；
- [`evidence/yaap16-prebuild-validation.json`](evidence/yaap16-prebuild-validation.json)：111 项机器可读检查；
- [`evidence/yaap16-soong-graph.json`](evidence/yaap16-soong-graph.json)：12 次 graph 迭代、最终产物哈希与 acceptance 结果；
- [`docs/OFFICIAL_3_0_304_REPORT.md`](docs/OFFICIAL_3_0_304_REPORT.md)：官方硬件基线报告；
- [`docs/EVOLUTIONX_DSU_BRINGUP.md`](docs/EVOLUTIONX_DSU_BRINGUP.md)：历史 EvolutionX DSU 验证记录；
- [`patches/README.md`](patches/README.md)：早期可移植 patch 证据，进入 YAAP 前逐项重放校验。

## 关键哈希

```text
Stage C full A/B OTA:
ebc06db809ea760069375e93e4f30f564fadec8f5c0fa7740da2ad42512b3902

Stage C upper5 DSU:
d8a9f0417cef780ea63878c9d9505e3819690e44859cecc40e237f682cec0b04

Stage C resolved manifest:
8cc70a712a5b1bc1cc3239c973d19b4cceef1888d1dc21487fba81b2cbbaa3d0

resolved manifest:
c1264cbe2cae0bf6c83cf181efbe7ac8e8674a50b21c2e0cd13a7eb33158a78b

kernel headers:
5466a76ca2c4b0dca9a6f02b60daccf772b01d876b4d952730dd38442b97f46f

stock libsoundtriggerhal.qti.so:
387afadf222ca499c924c17ba9966bd1750ee1cad2a1f4f543d328c7098ef553
```

## 远端

- 管理仓库：<https://github.com/Arimacose/haotian-rom-fusion>
- YAAP manifest：<https://github.com/yaap/manifest>
- haotian device fork：<https://github.com/Arimacose/device_xiaomi_haotian>
- SM8750 common fork：<https://github.com/Arimacose/device_xiaomi_sm8750-common>
- kernel fork：<https://github.com/Arimacose/device_xiaomi_haotian-kernel>
- health interfaces fork：<https://github.com/Arimacose/hardware_lineage_interfaces>
- health sepolicy fork：<https://github.com/Arimacose/device_lineage_sepolicy>
