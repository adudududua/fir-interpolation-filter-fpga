[CmdletBinding()]
param(
    [string]$VivadoExe = 'E:\app\Xilinx2018.3\Vivado\2018.3\bin\vivado.bat',
    [ValidateSet(0, 1, 2)]
    [int]$CicLowDspProfile = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$wrapper = Join-Path $PSScriptRoot 'run_national_finals_vivado_build.ps1'
$resultRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\vivado_results')).Path
$tagPrefix = "scan_cic_profile${CicLowDspProfile}"
$summaryPath = Join-Path $resultRoot "${tagPrefix}_strategy_scan.csv"

$candidates = @(
    [pscustomobject]@{
        Tag = "${tagPrefix}_area_rebuilt_auto"
        Directive = 'AreaOptimized_high'
        Flatten = 'rebuilt'
        Sharing = 'auto'
    },
    [pscustomobject]@{
        Tag = "${tagPrefix}_area_full_auto"
        Directive = 'AreaOptimized_high'
        Flatten = 'full'
        Sharing = 'auto'
    },
    [pscustomobject]@{
        Tag = "${tagPrefix}_area_none_auto"
        Directive = 'AreaOptimized_high'
        Flatten = 'none'
        Sharing = 'auto'
    },
    [pscustomobject]@{
        Tag = "${tagPrefix}_area_rebuilt_on"
        Directive = 'AreaOptimized_high'
        Flatten = 'rebuilt'
        Sharing = 'on'
    },
    [pscustomobject]@{
        Tag = "${tagPrefix}_default_rebuilt_auto"
        Directive = 'Default'
        Flatten = 'rebuilt'
        Sharing = 'auto'
    }
)

function Read-UtilizationCount {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern
    )
    $match = [regex]::Match($Text, $Pattern)
    if (-not $match.Success) {
        throw "Unable to parse utilization with pattern: $Pattern"
    }
    return [int]$match.Groups[1].Value
}

$rows = foreach ($candidate in $candidates) {
    Write-Host "[scan] $($candidate.Tag)"
    & $wrapper `
        -VivadoExe $VivadoExe `
        -Step synth `
        -CicLowDspProfile $CicLowDspProfile `
        -SynthesisDirective $candidate.Directive `
        -FlattenHierarchy $candidate.Flatten `
        -ResourceSharing $candidate.Sharing `
        -ResultTag $candidate.Tag

    $reportPath = Join-Path $resultRoot `
        "$($candidate.Tag)\utilization_synthesized.rpt"
    if (-not (Test-Path -LiteralPath $reportPath)) {
        throw "Synthesis report not found: $reportPath"
    }
    $reportText = Get-Content -LiteralPath $reportPath -Raw

    [pscustomobject]@{
        tag = $candidate.Tag
        directive = $candidate.Directive
        flatten_hierarchy = $candidate.Flatten
        resource_sharing = $candidate.Sharing
        slice_lut = Read-UtilizationCount $reportText `
            '\|\s*Slice LUTs\*\s*\|\s*(\d+)'
        flip_flop = Read-UtilizationCount $reportText `
            '\|\s*Slice Registers\s*\|\s*(\d+)'
        dsp48e1 = Read-UtilizationCount $reportText `
            '\|\s*DSPs\s*\|\s*(\d+)'
        bram_tile = Read-UtilizationCount $reportText `
            '\|\s*Block RAM Tile\s*\|\s*(\d+)'
    }
}

$rows | Export-Csv -LiteralPath $summaryPath -NoTypeInformation `
    -Encoding UTF8
$rows | Sort-Object slice_lut, flip_flop | Format-Table -AutoSize
Write-Host "SYNTHESIS STRATEGY SCAN PASS"
Write-Host "Summary: $summaryPath"
