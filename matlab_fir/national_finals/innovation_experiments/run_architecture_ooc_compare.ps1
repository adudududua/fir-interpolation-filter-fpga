[CmdletBinding()]
param(
    [string]$Vivado = 'E:\app\Xilinx20252\2025.2\Vivado\bin\vivado.bat',
    [string]$OutputRoot = '',
    [switch]$SkipCic
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot 'matlab_fir\national_finals\_work\innovation_validation_20260815\experiment5\ooc'
}
elseif (-not [System.IO.Path]::IsPathRooted($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot $OutputRoot
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
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

$cicTcl = Join-Path $repoRoot 'XC7A35T_interp_opt_2025.2\tools\vivado_2025_2\core_ooc\run_core_ooc_2025_2.tcl'
$all2xTcl = Join-Path $PSScriptRoot 'run_all2x_core_ooc_2025_2.tcl'
$cicOut = Join-Path $OutputRoot 'fir_cic_3dsp'
$all2xOut = Join-Path $OutputRoot 'all2x_2dsp'
New-Item -ItemType Directory -Path $cicOut,$all2xOut -Force | Out-Null

if (-not $SkipCic) {
    Push-Location $cicOut
    try {
        & $Vivado -mode batch -source $cicTcl -tclargs $cicOut 1 wordlength_24_20_20 1 162.760 explore
        if ($LASTEXITCODE -ne 0) { throw 'FIR-CIC OOC implementation failed.' }
    }
    finally { Pop-Location }
}

Push-Location $all2xOut
try {
    & $Vivado -mode batch -source $all2xTcl -tclargs $all2xOut 162.760 1
    if ($LASTEXITCODE -ne 0) { throw 'All-2x OOC implementation failed.' }
}
finally { Pop-Location }

Write-Host "ARCHITECTURE_OOC_COMPARE_PASS=$OutputRoot"
