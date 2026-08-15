[CmdletBinding()]
param(
    [string]$Vivado = 'E:\app\Xilinx20252\2025.2\Vivado\bin\vivado.bat',
    [string]$OutputRoot = '',
    [string]$HoldReferenceSummary = '',
    [ValidateRange(1, 8)]
    [int]$Jobs = 1
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot `
        'matlab_fir\national_finals\_work\innovation_validation_20260815\experiment6\ooc'
}
$tcl = Join-Path $repoRoot `
    'XC7A35T_interp_opt_2025.2\tools\vivado_2025_2\core_ooc\run_core_ooc_2025_2.tcl'

foreach ($required in @($Vivado, $tcl)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required file not found: $required"
    }
}

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$variants = @(
    [pscustomobject]@{
        Name = 'legacy_n3_no_hold'
        Label = 'Legacy C3-up16-I3'
        UseHold = 0
    },
    [pscustomobject]@{
        Name = 'n3_hold_equiv'
        Label = 'C2-Hold16-I2'
        UseHold = 1
    }
)

function Read-KeyValueSummary {
    param([Parameter(Mandatory = $true)][string]$Path)

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^([^=]+)=(.*)$') {
            $values[$matches[1]] = $matches[2]
        }
    }
    return $values
}

$rows = foreach ($variant in $variants) {
    $runDir = Join-Path $OutputRoot $variant.Name
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null
    $summaryPath = Join-Path $runDir 'core_ooc_summary.txt'

    if ($variant.UseHold -eq 1 -and
        -not [string]::IsNullOrWhiteSpace($HoldReferenceSummary)) {
        $summaryPath = (Resolve-Path -LiteralPath $HoldReferenceSummary).Path
        Write-Host "[$($variant.Name)] reuse validated reference summary: $summaryPath"
    }

    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
        Write-Host "[$($variant.Name)] Vivado 2025.2 OOC implementation"
        Push-Location $runDir
        try {
            & $Vivado -mode batch -source $tcl -tclargs `
                $runDir $Jobs wordlength_24_20_20 2 162.760 explore `
                $variant.UseHold
            if ($LASTEXITCODE -ne 0) {
                throw "Vivado failed for $($variant.Name) with exit code $LASTEXITCODE"
            }
        }
        finally {
            Pop-Location
        }
    }
    else {
        Write-Host "[$($variant.Name)] reuse existing OOC summary"
    }

    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
        throw "Missing OOC summary: $summaryPath"
    }
    $summary = Read-KeyValueSummary -Path $summaryPath
    if ([int]$summary.POST_ROUTE_DRC_ERRORS -ne 0 -or
        [double]$summary.INTERNAL_WNS_NS -lt 0.0 -or
        [double]$summary.INTERNAL_WHS_NS -lt 0.0) {
        throw "Implementation gate failed for $($variant.Name)"
    }

    [pscustomobject]@{
        Architecture = $variant.Label
        UseN3HoldEquiv = $variant.UseHold
        LUT = [int]$summary.POST_ROUTE_LUT
        FF = [int]$summary.POST_ROUTE_FF
        DSP = [int]$summary.POST_ROUTE_DSP48E1
        RAMB18 = [int]$summary.POST_ROUTE_RAMB18E1
        WNS_ns = [double]$summary.INTERNAL_WNS_NS
        WHS_ns = [double]$summary.INTERNAL_WHS_NS
        DRC_Errors = [int]$summary.POST_ROUTE_DRC_ERRORS
        EvidenceSummary = $summaryPath
    }
}

$csvPath = Join-Path $OutputRoot 'cic_hold_ooc.csv'
$rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
$rows | Format-Table -AutoSize
Write-Host "CIC Hold ablation PASS: $csvPath"
