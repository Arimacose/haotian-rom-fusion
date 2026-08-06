[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\configs\baselines.json'),
    [switch]$SkipSha256
)

$ErrorActionPreference = 'Stop'

function Write-JsonAtomic {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path)
    $temporary = "$Path.tmp"
    $Value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$artifact = $config.official_3_0_304
$destination = [IO.Path]::GetFullPath($artifact.archive)
$partial = "$destination.part"
$aria2Control = "$partial.aria2"
$directory = Split-Path -Parent $destination
$statusPath = Join-Path $directory 'download-status.json'
$expectedBytes = [int64]$artifact.expected_bytes

New-Item -ItemType Directory -Path $directory -Force | Out-Null

if (Test-Path -LiteralPath $destination) {
    $existingBytes = (Get-Item -LiteralPath $destination).Length
    if ($existingBytes -ne $expectedBytes) {
        throw "Existing final archive length mismatch: expected=$expectedBytes actual=$existingBytes"
    }
} else {
    $started = (Get-Date).ToString('o')
    $beforeBytes = if (Test-Path -LiteralPath $partial) {
        (Get-Item -LiteralPath $partial).Length
    } else {
        0
    }

    if ($beforeBytes -gt $expectedBytes) {
        throw "Partial archive exceeds expected length: expected=$expectedBytes actual=$beforeBytes"
    }

    $downloading = [ordered]@{
        state = 'downloading'
        started_at = $started
        expected_bytes = $expectedBytes
        initial_bytes = $beforeBytes
        partial_path = $partial
        source_url = $artifact.url
    }
    Write-JsonAtomic -Value $downloading -Path $statusPath

    if (($beforeBytes -lt $expectedBytes) -or (Test-Path -LiteralPath $aria2Control)) {
        $aria2 = if ($config.tools.PSObject.Properties.Name -contains 'aria2c') {
            [IO.Path]::GetFullPath($config.tools.aria2c)
        } else {
            $null
        }

        if ($aria2 -and (Test-Path -LiteralPath $aria2 -PathType Leaf)) {
            & $aria2 `
                --continue=true `
                --max-connection-per-server=16 `
                --split=16 `
                --min-split-size=4M `
                --file-allocation=none `
                --auto-file-renaming=false `
                --allow-overwrite=true `
                --retry-wait=3 `
                --max-tries=0 `
                --timeout=30 `
                --connect-timeout=30 `
                "--dir=$directory" `
                "--out=$(Split-Path -Leaf $partial)" `
                $artifact.url
            $downloadExit = $LASTEXITCODE
            $downloader = 'aria2c'
        } else {
            if (Test-Path -LiteralPath $aria2Control) {
                throw "An aria2 control file exists, but the pinned aria2c executable is absent: $aria2"
            }
            & curl.exe `
                --location `
                --fail `
                --continue-at - `
                --retry 20 `
                --retry-delay 5 `
                --retry-all-errors `
                --connect-timeout 30 `
                --speed-time 120 `
                --speed-limit 10240 `
                --progress-bar `
                --output $partial `
                $artifact.url
            $downloadExit = $LASTEXITCODE
            $downloader = 'curl'
        }

        if (($downloadExit -ne 0) -or (Test-Path -LiteralPath $aria2Control)) {
            $currentBytes = if (Test-Path -LiteralPath $partial) {
                (Get-Item -LiteralPath $partial).Length
            } else {
                0
            }
            Write-JsonAtomic -Value ([ordered]@{
                state = 'interrupted'
                started_at = $started
                checked_at = (Get-Date).ToString('o')
                expected_bytes = $expectedBytes
                partial_length = $currentBytes
                downloader = $downloader
                downloader_exit = $downloadExit
                aria2_control_present = (Test-Path -LiteralPath $aria2Control)
                partial_path = $partial
            }) -Path $statusPath
            throw "$downloader exited with code $downloadExit; the partial file remains available for resume"
        }
    }

    $actualBytes = (Get-Item -LiteralPath $partial).Length
    if ($actualBytes -ne $expectedBytes) {
        Write-JsonAtomic -Value ([ordered]@{
            state = 'length-mismatch'
            expected_bytes = $expectedBytes
            actual_bytes = $actualBytes
            partial_path = $partial
        }) -Path $statusPath
        throw "Downloaded length mismatch: expected=$expectedBytes actual=$actualBytes"
    }

    Move-Item -LiteralPath $partial -Destination $destination -Force
}

$hash = $null
if (-not $SkipSha256) {
    $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
}

$complete = [ordered]@{
    state = 'downloaded'
    verified_at = (Get-Date).ToString('o')
    expected_bytes = $expectedBytes
    actual_bytes = (Get-Item -LiteralPath $destination).Length
    sha256 = $hash
    etag = $artifact.etag
    oss_crc64_ecma = $artifact.oss_crc64_ecma
    path = $destination
}
Write-JsonAtomic -Value $complete -Path $statusPath
$complete | ConvertTo-Json -Depth 10
