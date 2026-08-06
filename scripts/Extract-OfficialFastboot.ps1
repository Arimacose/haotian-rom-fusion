[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\configs\baselines.json'),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$artifact = $config.official_3_0_304
$archive = [IO.Path]::GetFullPath($artifact.archive)
$outputRoot = [IO.Path]::GetFullPath($artifact.extract_root)
$expectedBytes = [int64]$artifact.expected_bytes

if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
    throw "Official archive is not present at $archive"
}

$actualBytes = (Get-Item -LiteralPath $archive).Length
if ($actualBytes -ne $expectedBytes) {
    throw "Official archive length mismatch: expected=$expectedBytes actual=$actualBytes"
}

$listingPath = Join-Path $outputRoot 'archive-listing.txt'
$extractPath = Join-Path $outputRoot 'extracted'
$manifestPath = Join-Path $outputRoot 'official-image-manifest.json'
$allowedWorkRoot = [IO.Path]::GetFullPath((Join-Path $config.audit_root 'work'))

if (-not $outputRoot.StartsWith($allowedWorkRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Extraction root is outside the configured audit work directory: $outputRoot"
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

& tar.exe -tzf $archive | Set-Content -LiteralPath $listingPath -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
    throw "tar archive listing failed with exit code $LASTEXITCODE"
}

if ($Force -and (Test-Path -LiteralPath $extractPath)) {
    $resolvedExtractPath = [IO.Path]::GetFullPath($extractPath)
    if (-not $resolvedExtractPath.StartsWith($outputRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Resolved extraction path is outside the intended output root: $resolvedExtractPath"
    }
    Remove-Item -LiteralPath $extractPath -Recurse -Force
}

if (-not (Test-Path -LiteralPath $extractPath)) {
    New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
    & tar.exe -xzf $archive -C $extractPath
    if ($LASTEXITCODE -ne 0) {
        throw "tar extraction failed with exit code $LASTEXITCODE"
    }
}

$imagesDirectory = Get-ChildItem -LiteralPath $extractPath -Directory -Recurse |
    Where-Object { $_.Name -eq 'images' } |
    Select-Object -First 1

if (-not $imagesDirectory) {
    throw "The extracted package has no images directory"
}

$selectedNames = @(
    'boot.img',
    'init_boot.img',
    'vendor_boot.img',
    'dtbo.img',
    'vbmeta.img',
    'vbmeta_system.img',
    'recovery.img',
    'super.img'
)

$selected = foreach ($name in $selectedNames) {
    $path = Join-Path $imagesDirectory.FullName $name
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $file = Get-Item -LiteralPath $path
        [ordered]@{
            name = $name
            path = $file.FullName
            bytes = $file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
}

$firmwareNames = @(
    'abl.img', 'aop.img', 'aop_config.img', 'bluetooth.img', 'cpucp.img',
    'cpucp_dtb.img', 'devcfg.img', 'dsp.img', 'featenabler.img', 'hyp.img',
    'idmanager.img', 'imagefv.img', 'keymaster.img', 'modem.img',
    'modemfirmware.img', 'multiimgqti.img', 'pdp.img', 'pdp_cdb.img',
    'pvmfw.img', 'qupfw.img', 'shrm.img', 'soccp_dcd.img', 'soccp_debug.img',
    'spuservice.img', 'tz.img', 'uefi.img', 'uefisecapp.img', 'vm-bootsys.img',
    'xbl.img', 'xbl_config.img', 'xbl_ramdump.img'
)

$firmware = foreach ($name in $firmwareNames) {
    $path = Join-Path $imagesDirectory.FullName $name
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $file = Get-Item -LiteralPath $path
        [ordered]@{
            name = $name
            path = $file.FullName
            bytes = $file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
}

$manifest = [ordered]@{
    schema_version = '1.0'
    generated_at = (Get-Date).ToString('o')
    source_archive = $archive
    source_bytes = $actualBytes
    source_sha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    images_directory = $imagesDirectory.FullName
    selected_images = @($selected)
    firmware_images = @($firmware)
}

$temporary = "$manifestPath.tmp"
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temporary -Encoding UTF8
Move-Item -LiteralPath $temporary -Destination $manifestPath -Force
$manifest | ConvertTo-Json -Depth 10
