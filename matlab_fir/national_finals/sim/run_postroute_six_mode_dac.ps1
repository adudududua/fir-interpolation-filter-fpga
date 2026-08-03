[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DcpPath,
    [string]$VivadoBin = 'E:\app\Xilinx2018.3\Vivado\2018.3\bin'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$nfRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$dcp = (Resolve-Path -LiteralPath $DcpPath).Path
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$runRoot = Join-Path $nfRoot "_work\postroute_six_mode_dac\$timestamp"
$netlist = Join-Path $runRoot 'board_demo_competition_dac8_top_postroute_funcsim.v'
$testbenchSource = Join-Path $PSScriptRoot 'tb_board_postroute_six_mode_dac.v'
$testbench = Join-Path $runRoot 'tb_board_postroute_six_mode_dac.v'
$exportTcl = Join-Path $nfRoot 'vivado\export_postroute_funcsim.tcl'

$vivado = Join-Path $VivadoBin 'vivado.bat'
$xvlog = Join-Path $VivadoBin 'xvlog.bat'
$xelab = Join-Path $VivadoBin 'xelab.bat'
$xsim = Join-Path $VivadoBin 'xsim.bat'

foreach ($required in @($dcp, $testbenchSource, $exportTcl,
                         $vivado, $xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required file does not exist: $required"
    }
}

New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
Copy-Item -LiteralPath $testbenchSource -Destination $testbench -Force

function Invoke-CheckedTool {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    Push-Location $runRoot
    try {
        $output = & $Executable @Arguments 2>&1
        foreach ($line in $output) {
            Write-Host $line
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Tool failed with exit code ${LASTEXITCODE}: $Executable"
        }
    }
    finally {
        Pop-Location
    }
}

Write-Host '[postroute-six-mode] export routed functional netlist'
Invoke-CheckedTool -Executable $vivado -Arguments @(
    '-mode', 'batch', '-source', $exportTcl, '-tclargs', $dcp, $netlist)

Write-Host '[postroute-six-mode] compile'
Invoke-CheckedTool -Executable $xvlog -Arguments @($netlist, $testbench)

Write-Host '[postroute-six-mode] elaborate'
Invoke-CheckedTool -Executable $xelab -Arguments @(
    'tb_board_postroute_six_mode_dac', 'glbl', '-L', 'unisims_ver',
    '-s', 'tb_board_postroute_six_mode_dac_sim')

Write-Host '[postroute-six-mode] simulate six public-key modes'
Invoke-CheckedTool -Executable $xsim -Arguments @(
    'tb_board_postroute_six_mode_dac_sim', '-runall')

$xsimLog = Join-Path $runRoot 'xsim.log'
if (-not (Test-Path -LiteralPath $xsimLog)) {
    throw 'Post-route six-mode simulation did not generate xsim.log'
}
$logText = Get-Content -LiteralPath $xsimLog -Raw
if (-not $logText.Contains('BOARD POSTROUTE SIX-MODE DAC PASS')) {
    throw 'Post-route six-mode DAC PASS marker was not found'
}
if ($logText -match '(?im)^.*BOARD SIX-MODE FAIL') {
    throw 'Post-route six-mode DAC failure marker was found'
}

Write-Host 'NATIONAL FINALS POSTROUTE SIX-MODE DAC PASS'
Write-Host "Routed checkpoint: $dcp"
Write-Host "Run directory: $runRoot"
