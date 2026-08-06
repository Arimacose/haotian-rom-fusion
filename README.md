# haotian ROM Fusion

为 Xiaomi 15 Pro（设备代号 `haotian`）建立可持续维护的类原生 ROM 适配仓库。

本项目不把某一份成品 ROM 当作唯一真值，而是按层选择三套基线中的优势：

- **HyperOS 3.0.304**：官方 firmware、boot chain、DTB/DTBO、vendor/odm proprietary 组件和每机校准数据的权威基线；
- **LineageOS 23.2 20260704**：CS40L26 振动校准恢复、较清晰的设备服务分层，以及 haotian/sm8750 公共设备树；
- **EvolutionX 16.0 20260603**：`bka/BP4A` 平台与 Evolution 功能基座、HyperOSCamera 集成、细化显示曲线和 HDR/HBM 调校素材。

## 当前结论

1. LineageOS 与 EvolutionX 的 boot kernel 逐字节相同，均为 Linux `6.6.77 android15-8`。
2. LineageOS 的振动修复位于用户空间 HAL：读取 `persist/haptics` 中每机校准值并写入 CS40L26 sysfs，同时处理节点所有权。
3. EvolutionX 的相机版本较新，显示曲线更细，但其 0603 成品为 `userdebug/test-keys`，且调试与 ADB 属性偏宽松。
4. LineageOS 0704 成品采用私有 release keys 并收敛调试属性，但 bootconfig 仍是全局 SELinux permissive。
5. 第一版融合构建继续以官方 HyperOS `OS3.0.304.0.WOBCNXM` 为底层，不混入 LineageOS 携带的第三固件集合。
6. 0603 成品的系统 Build ID 为 `BP4A.251205.006`，因此首个可复现源码构建固定 EvolutionX `bka`，而不是已经转向 `CP2A` 的 `cnb`。
7. 三份 `vendor_boot` 都带 434 个模块；EvolutionX 与 LineageOS 的 404 个模块逐字节相同但与官方 3.0.304 不同，首版必须保持 kernel、DTB/DTBO、模块与加载元数据成组一致。
8. 官方 3.0.304 proprietary tree 已实际生成：4,786 个分区路径与 31 个 firmware 输出全部命中，最终两棵 vendor tree 共 4,825 个文件、6,247,299,804 字节。

## 仓库边界

GitHub 只保存源码补丁、构建配置、哈希与比较结果、自动化脚本、测试矩阵、发布门禁和回滚说明。

以下内容只保留在 D 盘本地工作区：

- OTA、TGZ、ZIP、IMG、BIN、APK、APEX、KO；
- proprietary blobs；
- 解包目录和构建输出；
- AVB、APK、OTA 和平台签名私钥；
- 每台设备独有的 persist、校准值和用户数据。

## 本地目录

```text
D:\Codex\haotian-rom-fusion
D:\Codex\haotian-evox-0603-audit\downloads
D:\Codex\haotian-evox-0603-audit\work
D:\Codex\haotian-evox-0603-audit\reports
```

## 项目状态

- [x] EvolutionX 0603 OTA 完整静态拆包
- [x] LineageOS 23.2 0704 OTA 完整静态拆包
- [x] HyperOS 3.0.302/3.0.304 的 31 个 firmware 分区比较
- [x] LineageOS 振动修复机制定位
- [x] 私有 GitHub 仓库和可审阅 Git 基线
- [x] HyperOS 3.0.304 官方 12.2 GB fastboot 包完成下载、长度与 SHA-256 校验
- [x] 提取官方 boot、init_boot、vendor_boot、dtbo、vbmeta、super 和 8 个有效逻辑分区
- [x] 只读展开 8 个官方 EROFS，生成 16,071 个文件、768 个符号链接的全量哈希清单
- [x] 官方/Lineage/Evolution boot kernel 三方比较：三者逐字节相同
- [x] 官方/Lineage/Evolution DTBO、bootconfig 与 vendor ramdisk 模块的完整静态差异
- [ ] `pvmfw/mi_ext/system_dlkm` 的 AVB 与 OTA 描述符策略收敛
- [x] CS40L26 校准 loader、ADB 收敛、production AVB 与 3.0.304 Soter 路径补丁生成并通过静态应用检查
- [ ] 四个补丁在 EvolutionX `bka` 完整源树中编译验证
- [x] 两份 proprietary 列表对 3.0.304 文件树达到 4,786/4,786 路径覆盖
- [x] 生成 3.0.304 proprietary tree，验证 4,817/4,817 列表输出及 Goodix/相机/Soter/IMS 关键 fixup
- [ ] 在完整 EvolutionX 源树完成 Soong 模块图、全量 ELF 依赖、VINTF 与服务注册检查
- [ ] 相机、Goodix、触控、显示和 enforcing 融合
- [ ] production user、AVB、签名、OTA 与 A/B 回滚门禁

## 快速开始

```powershell
# 续传并校验官方 fastboot 包
pwsh -File .\scripts\Invoke-OfficialFastbootDownload.ps1

# 提取 fastboot 包并生成关键镜像清单
pwsh -File .\scripts\Extract-OfficialFastboot.ps1

# 提取 super 动态分区并生成逻辑分区哈希
pwsh -File .\scripts\Extract-SuperPartitions.ps1

# 重建三方基线清单
python .\scripts\Build-BaselineManifest.py --config .\configs\baselines.json

# 官方 boot 到位后运行内核比较
python .\scripts\Compare-KernelBaselines.py --config .\configs\baselines.json

# 从官方 EROFS 与 firmware 生成两棵 vendor tree；重复核验时加 -SkipExtraction
powershell.exe -ExecutionPolicy Bypass -File .\scripts\Generate-ProprietaryTree.ps1
```

## 文档

- [`docs/BASELINES.md`](docs/BASELINES.md)：已固定制品、哈希、来源和证据等级；
- [`docs/FUSION_PLAN.md`](docs/FUSION_PLAN.md)：分层融合方案与实施顺序；
- [`docs/SECURITY_AND_RELEASE_GATES.md`](docs/SECURITY_AND_RELEASE_GATES.md)：安全和发布门禁；
- [`docs/DEVICE_TEST_MATRIX.md`](docs/DEVICE_TEST_MATRIX.md)：后续受控 A/B 真机验收矩阵；
- [`docs/TOOLCHAIN.md`](docs/TOOLCHAIN.md)：本地工具来源、固定提交和 SHA-256；
- [`docs/BUILD_BOOTSTRAP.md`](docs/BUILD_BOOTSTRAP.md)：EvolutionX `bka` 初始化、固定清单、补丁和首编译门禁；
- [`docs/OFFICIAL_3_0_304_REPORT.md`](docs/OFFICIAL_3_0_304_REPORT.md)：官方 fastboot、super、firmware、kernel 与 AVB 实测报告；
- [`patches/README.md`](patches/README.md)：当前可回移补丁栈及目标提交。

## 远端

私有仓库：`https://github.com/Arimacose/haotian-rom-fusion`

里程碑：`Fusion v0.1 bring-up`

工作流已拆分为 GitHub Issues `#1` 至 `#7`：官方包、内核/KMI、振动、相机/显示、Goodix/硬件、安全加固、签名 A/B 验收。
