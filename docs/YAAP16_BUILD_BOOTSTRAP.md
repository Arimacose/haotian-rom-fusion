# haotian YAAP 16 可复现构建入口

> 本文记录从已验证状态恢复到“首次构建命令之前”的全部步骤。
> 2026-08-12 本轮只执行到静态预检，文末的 build gate 命令仅作为下一阶段入口。

## 1. 固定环境

### Windows / WSL

```text
WSL distribution: Ubuntu-ROMBuild
source root:       /home/arima/android/yaap16
management repo:   D:\Codex\haotian-rom-fusion
vendor staging:    D:\Codex\haotian-rom-fusion-build\source\vendor\xiaomi
stock dump:        D:\Codex\haotian-rom-fusion-build\stock-3.0.304-dump
```

`C:\Users\arima\.wslconfig` 当前资源配置：

```ini
[wsl2]
memory=24GB
processors=28
swap=32GB
swapFile=D:\\WSL\\wsl-swap.vhdx
localhostForwarding=true

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
```

### 工具版本

```text
Repo:     2.66 (launcher 2.65)
Git:      2.43.0
Git LFS:  3.4.1
Python:   3.12.3
Java:     OpenJDK 21.0.11
```

Repo 版本应在源码根目录内查看：

```bash
cd ~/android/yaap16
~/bin/repo version
```

## 2. 新工作区初始化

已有 `/home/arima/android/yaap16` 时跳过本节，直接进入第 3 节。

```bash
mkdir -p ~/android/yaap16 ~/.repo/local_manifests
cd ~/android/yaap16

~/bin/repo init \
  -u https://github.com/yaap/manifest.git \
  -b sixteen \
  --git-lfs

mkdir -p .repo/local_manifests
cp /mnt/d/Codex/haotian-rom-fusion/manifests/haotian-yaap16.xml \
  .repo/local_manifests/haotian-yaap16.xml
```

manifest 下载入口：

- YAAP 官方 manifest：<https://github.com/yaap/manifest>
- haotian local manifest：<https://github.com/Arimacose/haotian-rom-fusion/blob/agent/yaap16-platform-bringup/manifests/haotian-yaap16.xml>

## 3. 完整同步或增量恢复

本机此前遇到过 AOSP/Google 上游 `RESOURCE_EXHAUSTED`，因此采用低网络并发、较高 checkout 并发和多次 fetch retry：

```bash
cd ~/android/yaap16

~/bin/repo sync \
  -c \
  --force-sync \
  --optimized-fetch \
  --prune \
  --no-tags \
  --no-clone-bundle \
  --retry-fetches=10 \
  --no-interleaved \
  --jobs-network=2 \
  --jobs-checkout=8
```

Repo 从 `(0/1150)` 重新显示计数表示重新遍历项目，不等于重新下载全部对象。已存在的 Git object、pack 和 checkout 会复用；只有缺失或 revision 变化的内容进入网络 fetch。

同步后锁定 resolved manifest：

```bash
cd ~/android/yaap16
~/bin/repo manifest -r \
  -o /mnt/d/Codex/haotian-rom-fusion/manifests/resolved/yaap16-haotian-20260812.xml
```

预期：

```text
projects:       1150
unique paths:   1150
SHA-256:        c1264cbe2cae0bf6c83cf181efbe7ac8e8674a50b21c2e0cd13a7eb33158a78b
```

## 4. proprietary vendor 树落位

权威 staging 已位于 D 盘，复制到 WSL 时保留符号链接与硬链接语义：

```bash
cd ~/android/yaap16
mkdir -p vendor/xiaomi

rsync -aH --delete \
  /mnt/d/Codex/haotian-rom-fusion-build/source/vendor/xiaomi/haotian/ \
  vendor/xiaomi/haotian/

rsync -aH --delete \
  /mnt/d/Codex/haotian-rom-fusion-build/source/vendor/xiaomi/sm8750-common/ \
  vendor/xiaomi/sm8750-common/
```

只读内容复核：

```bash
for n in haotian sm8750-common; do
  rsync -rHnci --delete \
    "/mnt/d/Codex/haotian-rom-fusion-build/source/vendor/xiaomi/$n/" \
    "vendor/xiaomi/$n/"
done
```

预期没有输出。最终树规模：

```text
haotian:        3046 files / 5,465,316,231 bytes
sm8750-common:  1780 files /   782,226,259 bytes
```

## 5. kernel header 归档

```bash
cd ~/android/yaap16

bash /mnt/d/Codex/haotian-rom-fusion/scripts/Prepare-KernelHeaders.sh \
  device/xiaomi/haotian-kernel
```

预期输出：

```text
prebuilt_kernel_headers.tar.gz
SHA-256: 5466a76ca2c4b0dca9a6f02b60daccf772b01d876b4d952730dd38442b97f46f
tar entries: 1099
file modes: 0644
directory modes: 0755
```

该归档是本地生成输入，已由 `.git/info/exclude` 排除在 kernel Git 提交之外。

## 6. Git LFS 与工作树检查

```bash
cd ~/android/yaap16

git -C external/rust/android-crates-io lfs fsck
git -C vendor/google/gms lfs fsck
git -C vendor/microg lfs fsck

~/bin/repo forall -j8 -c '
  s=$(git status --porcelain=v1)
  if [ -n "$s" ]; then
    echo "DIRTY:$REPO_PATH"
    printf "%s\n" "$s"
  fi
'
```

预期三个 LFS 仓库均显示 `Git LFS fsck OK`，全项目工作树检查没有 `DIRTY:` 输出。

`repo status` 可能显示以下两行本地分支标识；其后没有文件状态行时工作树仍是清洁的：

```text
project device/xiaomi/haotian/                  branch yaap-16
project device/xiaomi/sm8750-common/            branch yaap-16
```

## 7. 静态预检

从 PowerShell 调用：

```powershell
wsl -d Ubuntu-ROMBuild -- bash -lc "python3 `
  /mnt/d/Codex/haotian-rom-fusion/scripts/Validate-YaapPrebuild.py `
  --source /home/arima/android/yaap16 `
  --resolved-manifest /mnt/d/Codex/haotian-rom-fusion/manifests/resolved/yaap16-haotian-20260812.xml `
  --output /mnt/d/Codex/haotian-rom-fusion/evidence/yaap16-prebuild-validation.json `
  --gapps-profile gapps"
```

预期：

```json
{"result":"pass","checks":111,"passed":110,"failed":0,"pending":1,"compile_started":true}
```

当前一项 pending：

1. `execution.compile_skipped`：`out` 已因首次 graph 产生，因此纯 prebuild 阶段断言不再适用。

GApps 已通过 `--gapps-profile gapps` 记录；本地开发 AVB 输入已存在，生产密钥策略仍在 release-hardening gate。

## 8. GApps profile 固定方式

YAAP 源码中的实际条件：

```make
ifeq ($(TARGET_BUILD_GAPPS),true)
    $(call inherit-product-if-exists, vendor/google/gms/config.mk)
else
    $(call inherit-product, vendor/microg/microg.mk)
endif
```

建议在首次构建记录中明确保存其中一种 profile：

### Google profile

```bash
export TARGET_BUILD_GAPPS=true
```

### YAAP 默认 MicroG/vanilla profile

```bash
unset TARGET_BUILD_GAPPS
```

这项选择会改变 product package 和 overlay 集合，因此首次生成 Soong graph 前固定。

## 9. Build gate：首次 graph 已完成

首次 graph 已使用以下配置通过，并在提交态复验：

```bash
cd ~/android/yaap16
export TARGET_BUILD_GAPPS=true
source build/envsetup.sh
lunch yaap_haotian-bp4a-userdebug
m -j16 nothing
```

完整证据见 `docs/YAAP16_SOONG_GRAPH_REPORT.md` 与 `evidence/yaap16-soong-graph.json`。

下一阶段若启动完整产品编译，YAAP 官方文档给出的通用形式为 `lunch yaap_device-user && m yaap`。haotian 的 Android 16 确定性 release-config 入口记录为：

```bash
cd ~/android/yaap16

# 先按第 8 节固定 profile
export TARGET_BUILD_GAPPS=true

source build/envsetup.sh
lunch yaap_haotian-bp4a-userdebug
m yaap
```

阶段选择：

- 首个 bring-up：`yaap_haotian-bp4a-userdebug`；
- 发布候选：`yaap_haotian-bp4a-user`；
- `eng` 仅用于短期开发诊断，不作为分发产物。

首次构建应同时保存：

```text
完整 stdout/stderr
首个失败模块
Soong/Ninja 命令行
峰值磁盘占用
out/target/product/haotian 文件树
target-files / OTA / image SHA-256
```

## 10. 失败时的最小回退点

| 层 | 固定回退对象 |
|---|---|
| manifest | `manifests/resolved/yaap16-haotian-20260812.xml` |
| device | `534e15a4b4fc49672826e2c99d1fcad1d64e5802` |
| common | `dbfb9fc599f7e2ff7e3c5add6b9c8f38185db90a` |
| kernel | `802915cc6b269c3bf577327c4c165c3117852ff5` |
| health interfaces | `ca560522cee3977861002372d1408cd7bb690198` |
| health sepolicy | `4aa6646b41042e19d9238034ed202d9a6b1a5ed9` |
| vendor trees | D 盘 staging，checksum delta 为 0 |
| baseline evidence | `evidence/yaap16-source-baseline.json` |
| validation evidence | `evidence/yaap16-prebuild-validation.json` |

遇到问题时先保留失败日志与 `out/soong` 状态，再针对首个根因做窄修改；源码同步、vendor staging 与 kernel header 归档无需重复初始化。
