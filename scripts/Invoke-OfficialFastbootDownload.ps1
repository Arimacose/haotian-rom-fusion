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

    if ($beforeBytes -lt $expectedBytes) {
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

        if ($LASTEXITCODE -ne 0) {
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
                actual_bytes = $currentBytes
                curl_exit = $LASTEXITCODE
                partial_path = $partial
            }) -Path $statusPath
            throw "curl exited with code $LASTEXITCODE; the partial file remains available for resume"
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
