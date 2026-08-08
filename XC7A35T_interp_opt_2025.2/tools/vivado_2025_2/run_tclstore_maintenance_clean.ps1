param(
    [ValidateSet('Reset', 'Query')]
    [string]$Action = 'Query'
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$vivadoBat = 'E:\app\Xilinx20252\2025.2\Vivado\bin\vivado.bat'
$tclName = if ($Action -eq 'Reset') { 'reset_tclstore.tcl' } else { 'query_tclstore.tcl' }
$tclScript = Join-Path $scriptDir $tclName
$scratchDir = Join-Path $env:TEMP 'fir_interpolation_vivado_tclstore'

if (-not (Test-Path -LiteralPath $vivadoBat)) {
    throw "Vivado 2025.2 was not found at $vivadoBat"
}
if (-not (Test-Path -LiteralPath $tclScript)) {
    throw "Tcl Store maintenance script was not found at $tclScript"
}

New-Item -ItemType Directory -Force -Path $scratchDir | Out-Null

# Vivado always starts from the system temporary directory and is told not to
# create journal/log files. This prevents .Xil, dfx_runtime.txt, vivado.jou,
# vivado.log and backup journals from appearing in the repository root.
Push-Location $scratchDir
try {
    & $vivadoBat -mode batch -notrace -nojournal -nolog -source $tclScript
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado Tcl Store $Action failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

Write-Host "VIVADO_TCLSTORE_${Action}_PASS"
