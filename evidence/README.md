# Evidence

This directory contains compact, redistributable metadata generated from local analysis.

Raw OTA files, extracted images, modules, APKs, certificates with private material, proprietary blobs and per-device data remain outside the Git repository.

Generated files:

- `known-artifacts.json`: pinned input metadata;
- `baseline-manifest.json`: local path, size and hash validation;
- `kernel-three-way-comparison.json`: official/Lineage/Evolution kernel comparison;
- `kernel-three-way-comparison.md`: readable kernel summary;
- `yaap16-source-baseline.json`: synchronized YAAP source and proprietary staging baseline;
- `yaap16-prebuild-validation.json`: current static checks against the resolved manifest;
- `yaap16-soong-graph.json`: fixed GApps/userdebug Soong, Kati, packaging and Ninja graph evidence.
