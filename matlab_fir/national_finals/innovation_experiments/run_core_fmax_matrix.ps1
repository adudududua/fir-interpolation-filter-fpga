[CmdletBinding()]
param(
    [string]$Vivado = 'E:\app\Xilinx20252\2025.2\Vivado\bin\vivado.bat',
    [string]$OutputRoot = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$vivadoRoot = Split-Path -Parent (Split-Path -Parent $Vivado)
$tclStore = Join-Path $vivadoRoot 'data\XilinxTclStore'
if (Test-Path -LiteralPath $tclStore) {
    $env:XILINX_TCLAPP_REPO = $tclStore
    $env:TCLLIBPATH = (@(
        (Join-Path $tclStore 'support\appinit'),
        (Join-Path $tclStore 'support'),
        (Join-Path $tclStore 'tclapp')
    ) | ForEach-Object { $_.Replace('\', '/') }) -join ' '
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot 'matlab_fir\national_finals\_work\innovation_validation_20260815\experiment4\fmax'
}
$tcl = Join-Path $repoRoot 'XC7A35T_interp_opt_2025.2\tools\vivado_2025_2\core_ooc\run_core_ooc_2025_2.tcl'
$periods = @(12.0, 10.0, 8.0)
$modes = @(2, 1, 0)
$index = @()

foreach ($mode in $modes) {
    foreach ($period in $periods) {
        $periodKey = ('{0:0.0}' -f $period).Replace('.', 'p')
        $out = Join-Path $OutputRoot "mode${mode}_period${periodKey}ns"
        New-Item -ItemType Directory -Path $out -Force | Out-Null
        Push-Location $out
        try {
            & $Vivado -mode batch -source $tcl -tclargs $out 1 wordlength_24_20_20 $mode $period explore
            $exitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }
        $index += [pscustomobject]@{
            CIC_INTEGRATOR_DSP_MODE = $mode
            CLOCK_PERIOD_NS = $period
            TOOL_EXIT_CODE = $exitCode
            SUMMARY = Join-Path $out 'core_ooc_summary.txt'
        }
    }
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$index | Export-Csv -LiteralPath (Join-Path $OutputRoot 'fmax_run_index.csv') -NoTypeInformation
Write-Host "CORE_FMAX_MATRIX_COMPLETE=$OutputRoot"
