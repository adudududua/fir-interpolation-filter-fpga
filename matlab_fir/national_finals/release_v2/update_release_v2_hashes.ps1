[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$releaseDir = $PSScriptRoot
$nfRoot = (Resolve-Path (Join-Path $releaseDir '..')).Path
$repoRoot = (Resolve-Path (Join-Path $nfRoot '..\..')).Path
$vectorDir = Join-Path $nfRoot '_work\release_vectors'
$rtlDir = Join-Path $nfRoot 'rtl_outputs'

$files = @(
    (Join-Path $releaseDir 'p4d_release_v2_config.json'),
    (Join-Path $releaseDir 'q_format_and_scaling.json'),
    (Join-Path $releaseDir 'coefficients.csv'),
    (Join-Path $nfRoot 'nf_release_v2_config.m'),
    (Join-Path $nfRoot 'nf_build_bittrue_case.m'),
    (Join-Path $nfRoot 'nf_cic3_shiftadd_bittrue.m'),
    (Join-Path $nfRoot 'nf_cic_n3_hold2_bittrue.m'),
    (Join-Path $vectorDir 'release_vector_manifest.csv'),
    (Join-Path $rtlDir 'rtl_impulse_y4.csv'),
    (Join-Path $rtlDir 'rtl_impulse_y8.csv'),
    (Join-Path $rtlDir 'rtl_impulse_y128.csv')
)
$files += Get-ChildItem -LiteralPath $vectorDir -Filter '*.mem' -File |
    Sort-Object Name |
    Select-Object -ExpandProperty FullName

$lines = foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Required release-v2 hash input is missing: $file"
    }
    $relative = $file.Substring($repoRoot.Length + 1).Replace('\', '/')
    $digest = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    "$digest  $relative"
}

$outputPath = Join-Path $releaseDir 'SHA256SUMS'
[System.IO.File]::WriteAllLines(
    $outputPath, $lines, [System.Text.Encoding]::ASCII)
$written = [System.IO.File]::ReadAllBytes($outputPath)
if ($written.Length -ge 3 -and $written[0] -eq 0xEF -and
        $written[1] -eq 0xBB -and $written[2] -eq 0xBF) {
    throw 'SHA256SUMS unexpectedly contains a UTF-8 BOM.'
}
Write-Host "NF_RELEASE_V2_SHA256_PASS: $($lines.Count) files, ASCII/no-BOM"
