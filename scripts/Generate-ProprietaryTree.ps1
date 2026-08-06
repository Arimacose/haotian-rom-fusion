[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$BuildRoot = "D:\Codex\haotian-rom-fusion-build",
    [string]$AuditRoot = "D:\Codex\haotian-evox-0603-audit",
    [string]$WslDistro = "Ubuntu-IPQuality",
    [switch]$SkipExtraction
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not $ProjectRoot) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}

$sourceRoot = Join-Path $BuildRoot "source"
$deviceRoot = Join-Path $sourceRoot "device\xiaomi"
$haotianRoot = Join-Path $deviceRoot "haotian"
$commonRoot = Join-Path $deviceRoot "sm8750-common"
$extractUtilsRoot = Join-Path $sourceRoot "tools\extract-utils"
$extractToolsRoot = Join-Path $sourceRoot "prebuilts\extract-tools"
$dumpRoot = Join-Path $BuildRoot "stock-3.0.304-dump"
$filesystemRoot = Join-Path $AuditRoot "work\stock-3.0.304-fastboot\filesystems"
$firmwareRoot = Join-Path $AuditRoot "work\stock-3.0.304-firmware-expanded\firmware-update"
$logPath = Join-Path $BuildRoot "extract-3.0.304.log"
$summaryPath = Join-Path $BuildRoot "proprietary-tree-generation-summary.json"

$haotianCommit = "483ace84ff3f8ef9cf0438626ce221022d23f433"
$commonCommit = "6f633ec0919fdfe3f8d307e8ab7770c1c1a90696"
$extractUtilsCommit = "b80fc427c8719bfa34e3c0dbdf43289bd24831d2"
$extractToolsCommit = "a8aabbbe42bdecba4c6d1a9e6e71fbc47de59f96"

function Invoke-GitChecked {
    param(
        [Parameter(Mandatory)] [string]$Repository,
        [Parameter(Mandatory)] [string[]]$GitArguments
    )
    & git -C $Repository @GitArguments
    if ($LASTEXITCODE -ne 0) {
        throw "git -C $Repository $($GitArguments -join ' ') exited with $LASTEXITCODE"
    }
}

function Ensure-Clone {
    param(
        [Parameter(Mandatory)] [string]$Url,
        [Parameter(Mandatory)] [string]$Branch,
        [Parameter(Mandatory)] [string]$Destination
    )
    if (Test-Path -LiteralPath (Join-Path $Destination ".git")) {
        return
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    & git clone --branch $Branch $Url $Destination
    if ($LASTEXITCODE -ne 0) {
        throw "Clone failed: $Url"
    }
}

function Ensure-Head {
    param(
        [Parameter(Mandatory)] [string]$Repository,
        [Parameter(Mandatory)] [string]$ExpectedCommit
    )
    $actual = (& git -C $Repository rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "HEAD inspection failed for $Repository"
    }
    if ($actual -eq $ExpectedCommit) {
        return
    }
    $changes = (& git -C $Repository status --porcelain)
    if ($changes) {
        throw "HEAD drifted and the worktree has changes: $Repository"
    }
    Invoke-GitChecked -Repository $Repository -GitArguments @("checkout", $ExpectedCommit)
}

function Ensure-FusionBranch {
    param([Parameter(Mandatory)] [string]$Repository)
    $current = (& git -C $Repository branch --show-current).Trim()
    if ($current -eq "fusion-3.0.304") {
        return
    }
    $existing = (& git -C $Repository branch --list "fusion-3.0.304").Trim()
    if ($existing) {
        Invoke-GitChecked -Repository $Repository -GitArguments @("switch", "fusion-3.0.304")
    }
    else {
        Invoke-GitChecked -Repository $Repository -GitArguments @("switch", "-c", "fusion-3.0.304")
    }
}

function Ensure-Patch {
    param(
        [Parameter(Mandatory)] [string]$Repository,
        [Parameter(Mandatory)] [string]$PatchPath
    )
    & git -C $Repository apply --reverse --check $PatchPath 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Already applied: $PatchPath"
        return
    }
    & git -C $Repository apply --check $PatchPath
    if ($LASTEXITCODE -ne 0) {
        throw "Patch preflight failed: $PatchPath"
    }
    & git -C $Repository apply $PatchPath
    if ($LASTEXITCODE -ne 0) {
        throw "Patch application failed: $PatchPath"
    }
}

function Ensure-Junction {
    param(
        [Parameter(Mandatory)] [string]$Link,
        [Parameter(Mandatory)] [string]$Target
    )
    if (-not (Test-Path -LiteralPath $Target)) {
        throw "Junction target is absent: $Target"
    }
    if (Test-Path -LiteralPath $Link) {
        return
    }
    New-Item -ItemType Junction -Path $Link -Target $Target | Out-Null
}

function Convert-ToWslPath {
    param([Parameter(Mandatory)] [string]$WindowsPath)
    $resolved = [IO.Path]::GetFullPath($WindowsPath)
    if ($resolved -notmatch "^([A-Za-z]):\\(.*)$") {
        throw "Expected a drive-qualified Windows path: $WindowsPath"
    }
    $driveLetter = $Matches[1].ToLowerInvariant()
    $remainder = $Matches[2].Replace("\", "/")
    return "/mnt/$driveLetter/$remainder"
}

foreach ($required in @($ProjectRoot, $filesystemRoot, $firmwareRoot)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required path is absent: $required"
    }
}

$buildDrive = (Split-Path -Qualifier $BuildRoot).TrimEnd(":")
$drive = Get-PSDrive -Name $buildDrive
if ($drive.Free -lt 12GB) {
    throw "At least 12 GiB free space is required under $BuildRoot"
}

New-Item -ItemType Directory -Force -Path $deviceRoot, (Join-Path $sourceRoot "tools"), (Join-Path $sourceRoot "prebuilts"), $dumpRoot | Out-Null

Ensure-Clone -Url "https://github.com/rep1ace/device_xiaomi_haotian.git" -Branch "lineage-23.2" -Destination $haotianRoot
Ensure-Clone -Url "https://github.com/rep1ace/device_xiaomi_sm8750-common.git" -Branch "lineage-23.2" -Destination $commonRoot
Ensure-Clone -Url "https://github.com/LineageOS/android_tools_extract-utils.git" -Branch "lineage-23.2" -Destination $extractUtilsRoot
Ensure-Clone -Url "https://github.com/LineageOS/android_prebuilts_extract-tools.git" -Branch "lineage-23.2" -Destination $extractToolsRoot

Ensure-Head -Repository $haotianRoot -ExpectedCommit $haotianCommit
Ensure-Head -Repository $commonRoot -ExpectedCommit $commonCommit
Ensure-Head -Repository $extractUtilsRoot -ExpectedCommit $extractUtilsCommit
Ensure-Head -Repository $extractToolsRoot -ExpectedCommit $extractToolsCommit
Ensure-FusionBranch -Repository $haotianRoot
Ensure-FusionBranch -Repository $commonRoot

Ensure-Patch -Repository $haotianRoot -PatchPath (Join-Path $ProjectRoot "patches\0001-haotian-cs40l26-calibration-loader.patch")
Ensure-Patch -Repository $haotianRoot -PatchPath (Join-Path $ProjectRoot "patches\0002-haotian-disable-adb-insecure.patch")
Ensure-Patch -Repository $commonRoot -PatchPath (Join-Path $ProjectRoot "patches\0003-sm8750-production-avb-profile.patch")
Ensure-Patch -Repository $commonRoot -PatchPath (Join-Path $ProjectRoot "patches\0004-sm8750-3.0.304-soterservice-source.patch")

$junctions = [ordered]@{
    "odm" = Join-Path $filesystemRoot "odm_a"
    "vendor" = Join-Path $filesystemRoot "vendor_a"
    "product" = Join-Path $filesystemRoot "product_a"
    "system" = Join-Path $filesystemRoot "system_a\system"
    "system_ext" = Join-Path $filesystemRoot "system_ext_a"
    "system_dlkm" = Join-Path $filesystemRoot "system_dlkm_a"
    "vendor_dlkm" = Join-Path $filesystemRoot "vendor_dlkm_a"
    "mi_ext" = Join-Path $filesystemRoot "mi_ext_a"
}
foreach ($name in $junctions.Keys) {
    Ensure-Junction -Link (Join-Path $dumpRoot $name) -Target $junctions[$name]
}

$firmwareFiles = Get-ChildItem -LiteralPath $firmwareRoot -File -Filter "*.img"
if ($firmwareFiles.Count -ne 31) {
    throw "Expected 31 official firmware images, got $($firmwareFiles.Count)"
}
foreach ($firmware in $firmwareFiles) {
    $destination = Join-Path $dumpRoot $firmware.Name
    if (-not (Test-Path -LiteralPath $destination)) {
        New-Item -ItemType HardLink -Path $destination -Target $firmware.FullName | Out-Null
    }
}

$wslSourceRoot = Convert-ToWslPath $sourceRoot
$wslDumpRoot = Convert-ToWslPath $dumpRoot
$wslLogPath = Convert-ToWslPath $logPath
if (-not $SkipExtraction) {
    $extractCommand = "set -o pipefail; cd '$wslSourceRoot/device/xiaomi/haotian'; PYTHONUNBUFFERED=1 PYTHONPATH=../../../tools/extract-utils python3 extract-files.py '$wslDumpRoot' 2>&1 | tee '$wslLogPath'"
    & wsl.exe -d $WslDistro -- bash -lc $extractCommand
    if ($LASTEXITCODE -ne 0) {
        throw "extract-files.py exited with $LASTEXITCODE. Review $logPath"
    }
}
elseif (-not (Test-Path -LiteralPath (Join-Path $sourceRoot "vendor\xiaomi\haotian\proprietary"))) {
    throw "SkipExtraction was selected before a generated vendor tree existed"
}

$verificationScript = Join-Path $BuildRoot "verify-proprietary-tree.py"
$verificationSource = @'
from __future__ import annotations

import json
import sys
from pathlib import Path

from extract_utils.file import FileList

source = Path(sys.argv[1])
output = Path(sys.argv[2])
cases = [
    ("haotian", "device/xiaomi/haotian/proprietary-files.txt", "vendor/xiaomi/haotian/proprietary"),
    ("sm8750-common", "device/xiaomi/sm8750-common/proprietary-files.txt", "vendor/xiaomi/sm8750-common/proprietary"),
    ("firmware", "device/xiaomi/haotian/proprietary-firmware.txt", "vendor/xiaomi/haotian/radio"),
]
lists = {}
for name, list_rel, tree_rel in cases:
    file_list = FileList(check_elf=True)
    file_list.add_from_file(source / list_rel)
    entries = list(file_list.files)
    missing = [item.dst for item in entries if not (source / tree_rel / item.dst).is_file()]
    lists[name] = {
        "entry_count": len(entries),
        "present_count": len(entries) - len(missing),
        "missing_count": len(missing),
        "missing": missing,
    }

trees = {}
for name in ("haotian", "sm8750-common"):
    tree = source / "vendor/xiaomi" / name
    files = [path for path in tree.rglob("*") if path.is_file()]
    trees[name] = {
        "path": str(tree),
        "file_count": len(files),
        "bytes": sum(path.stat().st_size for path in files),
    }

result = {
    "schema_version": "1.0",
    "official_version": "OS3.0.304.0.WOBCNXM",
    "lists": lists,
    "trees": trees,
    "total": {
        "file_count": sum(item["file_count"] for item in trees.values()),
        "bytes": sum(item["bytes"] for item in trees.values()),
    },
}
output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
if any(item["missing_count"] for item in lists.values()):
    raise SystemExit(2)
print(json.dumps(result, ensure_ascii=False, indent=2))
'@
[IO.File]::WriteAllText($verificationScript, $verificationSource, [Text.UTF8Encoding]::new($false))
$wslVerificationScript = Convert-ToWslPath $verificationScript
$wslSummaryPath = Convert-ToWslPath $summaryPath
& wsl.exe -d $WslDistro -- bash -lc "cd '$wslSourceRoot'; PYTHONPATH=tools/extract-utils python3 '$wslVerificationScript' '$wslSourceRoot' '$wslSummaryPath'"
if ($LASTEXITCODE -ne 0) {
    throw "Generated-tree verification failed with $LASTEXITCODE"
}

Write-Host "Proprietary tree: $sourceRoot\vendor\xiaomi"
Write-Host "Extraction log: $logPath"
Write-Host "Generation summary: $summaryPath"
