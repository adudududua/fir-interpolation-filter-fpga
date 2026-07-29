[CmdletBinding()]
param(
    [string]$VivadoExe = 'E:\app\Xilinx2018.3\Vivado\2018.3\bin\vivado.bat',
    [ValidateSet('cic', 'all2x')]
    [string]$Architecture = 'cic',
    [ValidateSet(0, 1)]
    [int]$All2xTailDsp48 = 0,
    [ValidateSet(0, 1)]
    [int]$PackedStage23 = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$wrapper = Join-Path $PSScriptRoot 'run_national_finals_vivado_build.ps1'
$resultRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\vivado_results')).Path
$tagPrefix = if ($Architecture -eq 'all2x') {
    "scan_all2x_dsp${All2xTailDsp48}"
}
else {
    'scan_cic'
}
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
        -Architecture $Architecture `
        -All2xSharedTail 1 `
        -All2xTailDsp48 $All2xTailDsp48 `
        -PackedStage23 $PackedStage23 `
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

    $bramMatch = [regex]::Match(
        $reportText,
        '\|\s*Block RAM Tile\s*\|\s*([0-9.]+)'
    )
    if (-not $bramMatch.Success) {
        throw 'Unable to parse Block RAM Tile utilization'
    }

    [pscustomobject]@{
        tag = $candidate.Tag
        architecture = $Architecture
        directive = $candidate.Directive
        flatten_hierarchy = $candidate.Flatten
        resource_sharing = $candidate.Sharing
        slice_lut = Read-UtilizationCount $reportText `
            '\|\s*Slice LUTs\*\s*\|\s*(\d+)'
        flip_flop = Read-UtilizationCount $reportText `
            '\|\s*Slice Registers\s*\|\s*(\d+)'
        dsp48e1 = Read-UtilizationCount $reportText `
            '\|\s*DSPs\s*\|\s*(\d+)'
        bram_tile = [double]$bramMatch.Groups[1].Value
    }
}

$rows | Export-Csv -LiteralPath $summaryPath -NoTypeInformation `
    -Encoding UTF8
$rows | Sort-Object slice_lut, flip_flop | Format-Table -AutoSize
Write-Host "SYNTHESIS STRATEGY SCAN PASS"
Write-Host "Summary: $summaryPath"
