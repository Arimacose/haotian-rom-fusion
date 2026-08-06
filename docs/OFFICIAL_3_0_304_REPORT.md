# haotian HyperOS 3.0.304 官方包解包与融合基线报告

> 生成时间：2026-08-06（Asia/Shanghai）
>
> 范围：静态下载、校验、解包、分区/内核/AVB 比较
>
> 真机状态：本轮未执行 ADB、fastboot、刷写、重启、切槽或分区读取

## 1. 结论摘要

1. 官方 fastboot 包已完整到达 D 盘，文件长度为 `12,202,675,840` 字节，SHA-256 为 `74f6af63f67f6e09b3f997c8f4503ac4275fe1d11bc3771a9ddd6521c83a0eef`。
2. TGZ 目录检查和路径检查通过；fastboot `images` 目录共 100 个文件，其中 18 个 `.img`、40 个 firmware 类载荷。
3. `super.img` 是 Android sparse image，转换后的逻辑 super 总大小为 `11,811,160,064` 字节；已提取 16 个 A/B 条目，其中 8 个 `_a` 分区有内容，8 个 `_b` 条目为空。
4. 官方 8 个有效 dynamic 分区全部采用 EROFS/LZ4。EvolutionX 的七个主分区为 ext4；LineageOS 是 system/product/system_ext 为 ext4、vendor/odm/dlkm 为 EROFS 的混合布局。
5. 官方 firmware-only ZIP 的 31 项固件与 fastboot 目录逐项对齐：5 项原始文件完全相同，25 项是同一载荷加 4 KiB 零填充容器，`vm-bootsys` 经 sparse-to-raw 归一化后相同，未匹配项为 0。
6. 最关键的新结论：官方 3.0.304、EvolutionX 0603、LineageOS 0704 的 boot kernel **逐字节相同**，均为 36,456,960 字节，SHA-256 均为 `99485b0132e3aa28f4e965119591c8149fe3c20e7e0fd10d753ef014a582472e`。
7. 三套完整 boot 容器并不相同，差异来自各自签名、AVB footer/描述符与启动配套内容，而不是 kernel 字节。
8. 官方 main vbmeta 为 RSA-4096、flags `0`，并覆盖 `pvmfw`、`mi_ext`、`system_dlkm`；两个类原生成品的 main vbmeta 均为 flags `3`，且都缺少这三项官方描述符。融合版需同时修正 flags 与描述符覆盖，二者缺一都会令 production AVB 门禁停留在未完成状态。
9. 第一版融合内核选择已收敛为官方一致的 6.6.77 kernel/module/DTB/DTBO 组合；第三方 6.6.143 放入后续实验轨道，在完整镜像、模块和 KMI 证据到位后再评估。

## 2. 官方制品身份与下载校验

| 项目 | 实测值 |
|---|---|
| 版本 | `OS3.0.304.0.WOBCNXM` |
| 设备 | `haotian` |
| fastboot 包 | `haotian_images_OS3.0.304.0.WOBCNXM_20260528.0000.00_16.0_cn_f685dbac4d.tgz` |
| 文件长度 | `12,202,675,840` |
| SHA-256 | `74f6af63f67f6e09b3f997c8f4503ac4275fe1d11bc3771a9ddd6521c83a0eef` |
| HTTP ETag | `A3388C0571D61A1BE119D49E30D24F47-400` |
| OSS CRC64-ECMA | `13677892784823728727` |
| 平台安全补丁文本 | `2026-02-01` |
| anti version | `1` |
| userdata build stamp | `20260528.0000.00` |
| 包内 build number | `OS3.0.304.0.WOBCNXM` |

下载器从 curl 的连续断点 `6,197,964,800` 字节处切换到 aria2 1.37.0，使用 16 条 HTTP range 连接续传；aria2 平均速度为 6.1 MiB/s。完成判据不是稀疏写入后的逻辑文件长度，而是 `.aria2` 位图全部完成并自动消失，然后再执行精确长度、SHA-256 与 tar 目录验证。

本地路径：

```text
D:\Codex\haotian-evox-0603-audit\downloads\stock-3.0.304-fastboot\haotian_images_OS3.0.304.0.WOBCNXM_20260528.0000.00_16.0_cn_f685dbac4d.tgz
```

## 3. 关键镜像清单

| 文件 | 字节 | SHA-256 |
|---|---:|---|
| `boot.img` | 100663296 | `ad8c9b89c96ff5473e17cfd0fa18b3f45d8dbeafa23f4846fe45469a9b6b4d09` |
| `init_boot.img` | 8388608 | `249e133a7c12e6bb269a642529a4484d729c53103475361ab8db24b08a9c2c36` |
| `vendor_boot.img` | 100663296 | `45c61737b372b4ce300ef70d0228760995010509cf874243ddd6b62af186cad7` |
| `dtbo.img` | 18874368 | `602f91eb634ad49d70c59d45a071358f37e02ded68db563efb9b25b4d7dfa804` |
| `recovery.img` | 104857600 | `89a0193ce6f6708102b969581e044fa26dea38c20f723d224887c3c2ba301c38` |
| `vbmeta.img` | 12288 | `c73f8e19d1677a4a200de5a06cfb6c08dcb06a31d3853bad48c5a709f89e8363` |
| `vbmeta_system.img` | 4096 | `84fb6279e41424b2c48efedba7bfdc99bfa6e0206b03885ffe35225f60448bae` |
| `super.img` | 10550233492 | `17c49682f8373ef1743a9ba6dfde8c26fbae5e8f31e1f9b783d9a246d89a8dc5` |
| `persist.img` | 33554432 | `4cacdb3c6b9e0a389caf4b91cd07b96580d8714e1803cb33b5efbc32d4d02018` |
| `pvmfw.img` | 1048576 | `1cd5c1e394d98777e7a4e9247a14c6ab1962c0b5fd7524e10f69129b4e5bf449` |

`persist.img` 仅作为官方空白/出厂镜像证据留存；振动补丁继续读取每台设备自身 `/mnt/vendor/persist/haptics` 校准值，仓库中不保存具体校准数据。

## 4. super 与 dynamic partition

### 4.1 super 元数据

| 项目 | 值 |
|---|---:|
| block device | `super` |
| raw 总大小 | `11,811,160,064` |
| used size | `10,583,613,440` |
| block size | `4096` |
| alignment | `1,048,576` |
| A/B group maximum size | `11,800,674,304` |

### 4.2 有效 `_a` 分区

| 分区 | 字节 | 文件系统 | SHA-256 |
|---|---:|---|---|
| `mi_ext_a` | 110481408 | EROFS/LZ4 | `cd53ba9131835cb4ed2786c2d0a16a2bc58d5990299aba6da8dad98f7fd40b3b` |
| `odm_a` | 3873234944 | EROFS/LZ4 | `b66d57940c4f7084022c9b49efcb1a770eb8a226eda4af9248c051a8946489e3` |
| `product_a` | 4089835520 | EROFS/LZ4 | `028104e6911e76c45137f68593ecf8e225c108deaecb436d0357baba1ada586d` |
| `system_a` | 912228352 | EROFS/LZ4 | `abdb77adfa054da804c85dcace84a25f640d51e7427a1df98d9252a70210e9e5` |
| `system_dlkm_a` | 15212544 | EROFS/LZ4 | `5665e9fc92f0ae4b3058cdbcf8d18cc0601076f44f789a905bd4c72813438b3a` |
| `system_ext_a` | 709976064 | EROFS/LZ4 | `a2f65950db86ae0e27a644596186cd1c85123f0da1ee6d5004aa343d6fcc35c3` |
| `vendor_a` | 794562560 | EROFS/LZ4 | `89e7b50a40d967aa9bd2ed84fb1431f7992119bef2d13476bc3f66865ef490ad` |
| `vendor_dlkm_a` | 78082048 | EROFS/LZ4 | `d81b8f909752a8925e07b0f0cc4e2518ac1d6f798e737b25ce4807ed4c2e1163` |

八个对应 `_b` 条目大小为 0，符合 fastboot 工厂包只在一侧填充逻辑分区的布局。本轮将它们记录为布局证据，不把零长度条目误判为缺包。

### 4.3 EROFS 文件级清单

八个有效分区已全部通过 `fsck.erofs --extract` 只读展开并逐文件计算 SHA-256：

| 指标 | 结果 |
|---|---:|
| 普通文件 | 16071 |
| 符号链接 | 768 |
| 总条目 | 16839 |
| 普通文件逻辑字节 | 14865416815 |
| 全量 manifest 字节 | 4057735 |
| 全量 manifest SHA-256 | `3be59c7e12d920c324eff94e4c3b41cf1533cbcd48d3c77f08d6ac0ea86fddeb` |

按路径关键字生成的候选集合包括 2,584 个 camera、484 个 display、31 个
fingerprint、53 个 haptics、199 个 touch 和 589 个 kernel module 条目。
这些计数用于缩小比较范围，不等同于最终 proprietary 选取结果；最终清单仍以
两份设备树 proprietary 列表、ELF 依赖和运行时注册关系为准。

## 5. 31 项官方 firmware 交叉验证

对比对象：

- fastboot `images` 目录中的 `.elf/.mbn/.bin/.melf/.fv/.img`；
- 已通过 ZIP CRC 的 3.0.304 firmware-only 包 `firmware-update/*.img`。

归一化结果：

| 类型 | 数量 | 解释 |
|---|---:|---|
| 原始字节完全相同 | 5 | 两个包直接携带相同文件 |
| 同一载荷 + ZIP 侧零填充 | 25 | fastboot 文件是有效载荷，firmware ZIP `.img` 补齐到 4 KiB 边界 |
| sparse/raw 归一化相同 | 1 | fastboot `vm-bootsys.img` 是 Android sparse，转 raw 后 SHA-256 与 firmware ZIP 相同 |
| 未匹配 | 0 | 31 项全部建立等价关系 |

`vm-bootsys` 归一化后的 raw SHA-256 为 `0232530df51b4677268d071cb4d796832a347831ef3afd9ecb833b07c4943a3c`。

这个结果将 3.0.304 firmware-only 包与完整 fastboot 包连接成同一官方固件基线，也证明首版融合无需引入 LineageOS OTA 中那组不同来源的 31 项 firmware。

## 6. kernel 与 boot-chain 比较

### 6.1 kernel 三方结论

| 基线 | Kernel 字节 | SHA-256 | Banner |
|---|---:|---|---|
| 官方 3.0.304 | 36456960 | `99485b0132e3aa28f4e965119591c8149fe3c20e7e0fd10d753ef014a582472e` | Linux 6.6.77 android15-8, 4K, Clang 18 |
| EvolutionX 0603 | 36456960 | 同上 | 同上 |
| LineageOS 0704 | 36456960 | 同上 | 同上 |

因此：

- LineageOS 的振动修复确实位于用户空间 vibrator service/init 权限与 persist 校准加载，不在 kernel 字节；
- EvolutionX 的相机、显示、HDR 与边缘触控表现也不由 kernel 差异直接造成；
- 初始融合可沿用官方一致 6.6.77，减少 KMI、模块 CRC、DTB 与电源管理变量；
- 用户当前 6.6.143 第三方内核在收到完整 artifact 后做独立分支评估。

### 6.2 boot 容器

官方、EvolutionX、LineageOS 的 `boot/init_boot/vendor_boot/dtbo/recovery/vbmeta` 完整文件哈希均不同。Kernel 相同并不代表 boot-chain 可互换；后续仍需逐项比较：

- boot header、签名与 AVB footer；
- init_boot ramdisk；
- vendor_boot ramdisk fragments、bootconfig、DTB；
- dtbo overlay 数量、ID 与内容；
- vendor_ramdisk/system_dlkm/vendor_dlkm 模块集合、vermagic、CRC 和加载顺序。

已完成的下一层静态结果：

| 项目 | 官方 3.0.304 | EvolutionX 0603 | LineageOS 0704 |
|---|---|---|---|
| vendor_boot bootconfig 字节 | 204 | 201 | 263 |
| protected VM | `true` | `0` | `true` |
| SELinux bootconfig | 未写入 permissive | 未写入 permissive | `androidboot.selinux=permissive` |
| vendor_boot DTB 字节 | 4109344 | 4109544 | 4109248 |
| DTBO entry 数量 | 1 | 1 | 1 |
| DTBO entry 字节 | 546163 | 546065 | 546159 |

三套 vendor_boot DTB 与 DTBO entry 哈希均不同。公开 common 树当前把 protected VM
设为 `0`，与 EvolutionX 0603 一致；LineageOS 0704 成品则与官方一样设为 `true`，
说明 0704 成品在这部分也领先或偏离当前公开提交。第一版将以官方 bootconfig/DTB/DTBO
为权威，再逐项移植类原生必需的 ramdisk 变更。

## 7. AVB 实测

| 项目 | 官方 3.0.304 | EvolutionX 0603 | LineageOS 0704 |
|---|---|---|---|
| main vbmeta algorithm | SHA256_RSA4096 | SHA256_RSA4096 | SHA256_RSA2048 |
| main vbmeta flags | `0` | `3` | `3` |
| boot rollback index | `1769904000` | `1769904000` | `1780272000` |
| boot key SHA-1 | `de5be2a5…f809` | `2597c218…f011` | `cdbb7717…617d` |
| chained partitions | boot/recovery/vbmeta_system | 同结构 | 同结构 |

官方 main vbmeta 描述的分区集合包含：

```text
boot, recovery, vbmeta_system, dtbo, init_boot, pvmfw, vendor_boot,
mi_ext, odm, system_dlkm, vendor, vendor_dlkm
```

EvolutionX 与 LineageOS main vbmeta 都少了：

```text
pvmfw, mi_ext, system_dlkm
```

当前 `0003-sm8750-production-avb-profile.patch` 已把 flags 收敛到 `0`、加入主 vbmeta RSA-4096 与项目 key 路径，并移除 AOSP test-key 路径。下一轮还要把 `pvmfw/mi_ext/system_dlkm` 的构建、OTA 分区策略和描述符关系补齐，再把 AVB Gate S3 标记为完成。

官方 boot rollback index `1769904000` 与平台安全补丁 `2026-02-01` 对应，也验证了公共 sm8750 树中现有 rollback timestamp 的来源。

## 8. 对融合方案的直接影响

### 8.0 proprietary 路径覆盖

两份公共设备树清单合计 4,786 个条目：

| 清单 | 条目 | 原始路径命中 | 项目补丁后命中 |
|---|---:|---:|---:|
| `device_xiaomi_haotian` | 3011 | 3011 | 3011 |
| `device_xiaomi_sm8750-common` | 1775 | 1774 | 1775 |
| 合计 | 4786 | 4785 | 4786 |

唯一原始路径差异是：

```text
清单路径: mi_ext/product/app/SoterService/SoterService.apk
3.0.304: product/app/SoterService/SoterService.apk
```

`0004-sm8750-3.0.304-soterservice-source.patch` 已把 common 清单指向官方
3.0.304 的真实 product 路径。值得注意的是，两份清单头部说明来源为 OS3.0.5，
但 haotian 3.0.304 仍提供全部 4,786 个项目所需路径；这为直接生成首版
proprietary tree 提供了很强的完整性证据。路径命中仍不替代 ELF 依赖、符号、
版本与服务注册检查。

### 8.1 平台与设备源

- 平台固定 EvolutionX `bka`，对应 0603 成品的 `BP4A.251205.006`；
- 设备与 common 源固定 LineageOS 23.2 公共提交；
- 以补丁方式引入 0704 振动行为、ADB 收敛和 AVB 起始 profile；
- 官方 3.0.304 dynamic partitions 作为 proprietary 路径、版本和 ABI 的权威提取源。

### 8.2 相机

官方 `odm/vendor/product/mi_ext` 已进入只读 EROFS 展开流程。相机融合将从官方 3.0.304 提取 APK、provider、权限、属性和配置，再与 EvolutionX 6.4.000270.0、LineageOS 6.4.000250.3 对照。4K60、人像、深度、EIS/OIS 和镜头切换分别设门禁，避免只以“相机能打开”作为结论。

### 8.3 显示与触控

官方 display 配置与 panel identity 将从 odm/vendor/product/mi_ext 中定位。亮度下限、HDR ratio、HBM、AOD 和 edge suppression 分开比较；EvolutionX 的细曲线作为候选增量，官方曲线保持初始权威。

### 8.4 Goodix

Goodix HAL、权限、服务实例与校准相关文件从官方 3.0.304 路径提取。第一版只激活与该设备传感器匹配的实例；QCOM 指纹兼容保留为独立 issue，不阻塞 Goodix 路线。

## 9. 已生成证据

Git 仓库内的小型、可审阅证据：

```text
evidence/official-image-manifest.json
evidence/official-super-partition-manifest.json
evidence/official-firmware-crosscheck.json
evidence/boot-chain-crosscheck.json
evidence/official-avb-comparison.json
evidence/kernel-three-way-comparison.json
evidence/kernel-three-way-comparison.md
```

D 盘完整证据与大型文件：

```text
D:\Codex\haotian-evox-0603-audit\downloads\stock-3.0.304-fastboot
D:\Codex\haotian-evox-0603-audit\work\stock-3.0.304-fastboot\extracted
D:\Codex\haotian-evox-0603-audit\work\stock-3.0.304-fastboot\super-partitions
D:\Codex\haotian-evox-0603-audit\work\stock-3.0.304-fastboot\filesystems
```

大型 TGZ、IMG、EROFS 展开树、proprietary blobs 与签名私钥继续留在 D 盘，不进入 Git 历史。

## 10. 下一步执行顺序

1. 对官方/EvolutionX/LineageOS 的 vendor_boot ramdisk 与模块做三方差异；
2. 用官方文件树运行两份 proprietary 列表，生成缺失/命中/版本差异报告；
3. 收敛 `pvmfw/mi_ext/system_dlkm` 的 AVB 和 OTA 描述符策略；
4. 将官方 camera/display/Goodix 配置与两份类原生成品逐路径对照；
5. 准备 6.6.77 prebuilt kernel tree 和 3.0.304 proprietary tree；
6. 在 EvolutionX `bka` 完整源树上执行首个 `userdebug` 编译；
7. 编译通过后再进入 production `user`、项目签名、完整 AVB 与 A/B 验收。
