# Scripts

| Script | Purpose |
|---|---|
| `Invoke-OfficialFastbootDownload.ps1` | Resume the official 3.0.304 TGZ with pinned aria2 (curl fallback), require a cleared control file and exact length, compute SHA-256 and atomically write status |
| `Extract-OfficialFastboot.ps1` | Validate and extract the TGZ, locate the images directory and hash selected boot/firmware images |
| `Extract-SuperPartitions.ps1` | Dump super metadata, convert sparse input when required, extract logical partitions and hash every image |
| `Build-BaselineManifest.py` | Verify pinned local inputs and generate a compact baseline manifest |
| `Compare-KernelBaselines.py` | Extract the official kernel and compare it with LineageOS and EvolutionX kernels |
| `Build-OfficialFilesystemManifest.py` | Under WSL, hash every extracted EROFS file/link, keep the full manifest on D, and write a compact review summary |
| `Check-ProprietaryCoverage.py` | Under WSL, measure device/common proprietary-list coverage against the official filesystems and record relocated candidates |
| `Generate-ProprietaryTree.ps1` | Pin the device and extract-utils repositories, apply all four fusion patches, create a read-only 3.0.304 dump view, generate both vendor trees, and verify every list output; `-SkipExtraction` rechecks an existing tree |

Scripts default to paths in `configs/baselines.json`. Large audit outputs remain under `D:\Codex\haotian-evox-0603-audit`; generated build inputs remain under `D:\Codex\haotian-rom-fusion-build`. Both stay outside Git.

The pinned binary tool provenance is documented in `docs/TOOLCHAIN.md`.
