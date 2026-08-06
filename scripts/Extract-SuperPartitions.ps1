[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\configs\baselines.json'),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$CapturePath
    )

    $temporaryStderr = -not $CapturePath
    $stderrPath = if ($CapturePath) { "$CapturePath.stderr.log" } else { [IO.Path]::GetTempFileName() }
    $previousErrorAction = $ErrorActionPreference

    try {
        # These AOSP tools print their provenance banner to stderr even on success.
        # Keep stderr separate so lpdumps JSON on stdout remains machine-readable.
        $ErrorActionPreference = 'Continue'
        if ($CapturePath) {
            $stdout = & $Executable @Arguments 2> $stderrPath
        } else {
            & $Executable @Arguments 2> $stderrPath
        }
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }

    $stderrText = if (Test-Path -LiteralPath $stderrPath) {
        Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
    } else {
        ''
    }

    if ($CapturePath) {
        $stdout | Set-Content -LiteralPath $CapturePath -Encoding UTF8
    }

    if ($exitCode -ne 0) {
        $detail = if ($stderrText) { ": $($stderrText.Trim())" } else { '' }
        throw "$Executable exited with code $exitCode$detail"
    }

    if ($temporaryStderr) {
        if ($stderrText) {
            Write-Verbose $stderrText.Trim()
        }
        Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$officialRoot = [IO.Path]::GetFullPath($config.official_3_0_304.extract_root)
$allowedWorkRoot = [IO.Path]::GetFullPath((Join-Path $config.audit_root 'work'))
$outputRoot = [IO.Path]::GetFullPath((Join-Path $officialRoot 'super-partitions'))
$manifestPath = Join-Path $officialRoot 'official-super-partition-manifest.json'
$metadataPath = Join-Path $officialRoot 'official-super-metadata.json'

if (-not $officialRoot.StartsWith($allowedWorkRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Official extraction root is outside the configured audit work directory: $officialRoot"
}

$superImage = Get-ChildItem -LiteralPath (Join-Path $officialRoot 'extracted') -Filter 'super.img' -File -Recurse |
    Select-Object -First 1
if (-not $superImage) {
    throw "Official super.img has not been extracted under $officialRoot"
}

$lpunpack = [IO.Path]::GetFullPath($config.tools.lpunpack)
$lpdumps = [IO.Path]::GetFullPath($config.tools.lpdumps)
$simg2img = [IO.Path]::GetFullPath($config.tools.simg2img)
foreach ($tool in @($lpunpack, $lpdumps, $simg2img)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Required partition tool is absent: $tool"
    }
}

New-Item -ItemType Directory -Path $officialRoot -Force | Out-Null
if ($Force -and (Test-Path -LiteralPath $outputRoot)) {
    $resolvedOutput = [IO.Path]::GetFullPath($outputRoot)
    if (-not $resolvedOutput.StartsWith($officialRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Resolved super output path is outside the official extraction root: $resolvedOutput"
    }
    Remove-Item -LiteralPath $outputRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

$inputImage = $superImage.FullName
$dumpSucceeded = $true
try {
    Invoke-NativeChecked -Executable $lpdumps -Arguments @('-j', $inputImage) -CapturePath $metadataPath
} catch {
    $dumpSucceeded = $false
}

if (-not $dumpSucceeded) {
    $rawSuper = Join-Path $officialRoot 'super.raw.img'
    if (-not (Test-Path -LiteralPath $rawSuper -PathType Leaf)) {
        Invoke-NativeChecked -Executable $simg2img -Arguments @($superImage.FullName, $rawSuper)
    }
    $inputImage = $rawSuper
    Invoke-NativeChecked -Executable $lpdumps -Arguments @('-j', $inputImage) -CapturePath $metadataPath
}

if (-not (Get-ChildItem -LiteralPath $outputRoot -Filter '*.img' -File -ErrorAction SilentlyContinue)) {
    Invoke-NativeChecked -Executable $lpunpack -Arguments @($inputImage, $outputRoot)
}

$partitions = Get-ChildItem -LiteralPath $outputRoot -Filter '*.img' -File |
    Sort-Object Name |
    ForEach-Object {
        [ordered]@{
            name = $_.BaseName
            path = $_.FullName
            bytes = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }

if (-not $partitions) {
    throw "lpunpack produced no logical partition images"
}

$manifest = [ordered]@{
    schema_version = '1.0'
    generated_at = (Get-Date).ToString('o')
    source_super = $superImage.FullName
    source_super_bytes = $superImage.Length
    source_super_sha256 = (Get-FileHash -LiteralPath $superImage.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    extraction_input = $inputImage
    metadata = $metadataPath
    output_root = $outputRoot
    partition_count = @($partitions).Count
    partitions = @($partitions)
}

$temporary = "$manifestPath.tmp"
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temporary -Encoding UTF8
Move-Item -LiteralPath $temporary -Destination $manifestPath -Force
$manifest | ConvertTo-Json -Depth 10
