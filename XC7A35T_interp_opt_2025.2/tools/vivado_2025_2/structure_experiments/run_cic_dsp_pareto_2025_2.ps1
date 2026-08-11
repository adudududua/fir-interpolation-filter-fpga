param(
    [ValidateSet(0, 1)]
    [int]$IntegratorDspMode,

    [ValidateRange(1, 4)]
    [int]$Jobs = 1
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$vivadoBat = 'E:\app\Xilinx20252\2025.2\Vivado\bin\vivado.bat'
$tclScript = Join-Path $scriptDir 'run_cic_dsp_pareto_2025_2.tcl'
$vivadoRoot = Split-Path -Parent (Split-Path -Parent $vivadoBat)
$tclStore = Join-Path $vivadoRoot 'data\XilinxTclStore'

if (-not (Test-Path -LiteralPath $vivadoBat -PathType Leaf)) {
    throw "Vivado 2025.2 was not found at $vivadoBat"
}

$env:XILINX_TCLAPP_REPO = $tclStore
$env:TCLLIBPATH = (@(
    (Join-Path $tclStore 'support\appinit'),
    (Join-Path $tclStore 'support'),
    (Join-Path $tclStore 'tclapp')
) | ForEach-Object { $_.Replace('\', '/') }) -join ' '

$runningVivado = @(Get-Process -Name 'vivado' -ErrorAction SilentlyContinue)
if ($runningVivado.Count -gt 0) {
    throw "Close every Vivado window before the Pareto build."
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$resultDir = Join-Path $scriptDir "results\cic_dsp_mode${IntegratorDspMode}_$stamp"
New-Item -ItemType Directory -Force -Path $resultDir | Out-Null
$logPath = Join-Path $resultDir 'vivado.log'
$journalPath = Join-Path $resultDir 'vivado.jou'

Push-Location $resultDir
try {
    & $vivadoBat -mode batch -notrace -log $logPath -journal $journalPath `
        -source $tclScript -tclargs $resultDir $IntegratorDspMode $Jobs
    if ($LASTEXITCODE -ne 0) {
        throw "CIC DSP Pareto build failed. See $logPath"
    }
}
finally {
    Pop-Location
}

Write-Host 'CIC_DSP_PARETO_POWERSHELL_PASS'
Write-Host "Results: $resultDir"
