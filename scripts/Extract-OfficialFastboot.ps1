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

$archiveListing = @(& tar.exe -tzf $archive)
if ($LASTEXITCODE -ne 0) {
    throw "tar archive listing failed with exit code $LASTEXITCODE"
}
$archiveListing | Set-Content -LiteralPath $listingPath -Encoding UTF8

foreach ($entry in $archiveListing) {
    $portableEntry = $entry.Replace('\', '/')
    $segments = $portableEntry.Split('/', [StringSplitOptions]::RemoveEmptyEntries)
    if ($portableEntry.StartsWith('/') -or $portableEntry -match '^[A-Za-z]:' -or $segments -contains '..') {
        throw "Unsafe archive entry detected: $entry"
    }
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
    'vendor_kernel_boot.img',
    'dtbo.img',
    'vbmeta.img',
    'vbmeta_system.img',
    'vbmeta_vendor.img',
    'recovery.img',
    'super.img'
)

$allFiles = Get-ChildItem -LiteralPath $imagesDirectory.FullName -File |
    Sort-Object Name |
    ForEach-Object {
        [ordered]@{
            name = $_.Name
            extension = $_.Extension.ToLowerInvariant()
            path = $_.FullName
            bytes = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }

$allImages = @($allFiles | Where-Object { $_.extension -eq '.img' })
$selected = @($allImages | Where-Object { $_.name -in $selectedNames })

$firmwareExtensions = @('.elf', '.mbn', '.bin', '.melf', '.fv')
$firmware = @($allFiles | Where-Object {
    ($_.extension -in $firmwareExtensions -and $_.name -notlike 'gpt_*' -and $_.name -notlike 'zeros_*') -or
    $_.name -in @('pvmfw.img', 'vm-bootsys.img')
})

$manifest = [ordered]@{
    schema_version = '1.0'
    generated_at = (Get-Date).ToString('o')
    source_archive = $archive
    source_bytes = $actualBytes
    source_sha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    images_directory = $imagesDirectory.FullName
    file_count = @($allFiles).Count
    all_files = @($allFiles)
    image_count = @($allImages).Count
    all_images = @($allImages)
    selected_images = @($selected)
    firmware_images = @($firmware)
}

$temporary = "$manifestPath.tmp"
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temporary -Encoding UTF8
Move-Item -LiteralPath $temporary -Destination $manifestPath -Force
$manifest | ConvertTo-Json -Depth 10
