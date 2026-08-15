[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DcpPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [string]$VivadoBin = 'E:\app\Xilinx20252\2025.2\Vivado\bin'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptRoot = $PSScriptRoot
$nfRoot = (Resolve-Path (Join-Path $scriptRoot '..')).Path
$dcp = (Resolve-Path -LiteralPath $DcpPath).Path
$output = [System.IO.Path]::GetFullPath($OutputDirectory)
$simRoot = Join-Path $output 'simulation'
$netlist = Join-Path $simRoot 'board_demo_competition_dac8_top_postroute_funcsim.v'
$testbenchSource = Join-Path $nfRoot 'sim\tb_board_postroute_dac_activity.v'
$testbench = Join-Path $simRoot 'tb_board_postroute_dac_activity.v'
$exportTcl = Join-Path $nfRoot 'vivado\export_postroute_funcsim.tcl'
$captureTcl = Join-Path $scriptRoot 'xsim_capture_saif.tcl'
$powerTcl = Join-Path $scriptRoot 'report_power_from_saif.tcl'
$saif = Join-Path $simRoot 'board_activity.saif'
$powerReport = Join-Path $output 'power_saif.rpt'
$powerSummary = Join-Path $output 'power_saif_summary.txt'

$vivado = Join-Path $VivadoBin 'vivado.bat'
$xvlog = Join-Path $VivadoBin 'xvlog.bat'
$xelab = Join-Path $VivadoBin 'xelab.bat'
$xsim = Join-Path $VivadoBin 'xsim.bat'
$vivadoRoot = Split-Path -Parent $VivadoBin
$tclStore = Join-Path $vivadoRoot 'data\XilinxTclStore'
if (Test-Path -LiteralPath $tclStore) {
    $env:XILINX_TCLAPP_REPO = $tclStore
    $env:TCLLIBPATH = (@(
        (Join-Path $tclStore 'support\appinit'),
        (Join-Path $tclStore 'support'),
        (Join-Path $tclStore 'tclapp')
    ) | ForEach-Object { $_.Replace('\', '/') }) -join ' '
}
foreach ($required in @($dcp, $testbenchSource, $exportTcl, $captureTcl,
                         $powerTcl, $vivado, $xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required file does not exist: $required"
    }
}

New-Item -ItemType Directory -Path $simRoot -Force | Out-Null
Copy-Item -LiteralPath $testbenchSource -Destination $testbench -Force

function Invoke-Checked {
    param([string]$Exe, [string[]]$Arguments, [string]$WorkingDirectory)
    Push-Location $WorkingDirectory
    try {
        & $Exe @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Tool failed with exit code $LASTEXITCODE`: $Exe"
        }
    }
    finally {
        Pop-Location
    }
}

if (-not (Test-Path -LiteralPath $saif)) {
    Invoke-Checked -Exe $vivado -WorkingDirectory $simRoot -Arguments @(
        '-mode', 'batch', '-source', $exportTcl, '-tclargs', $dcp, $netlist)
    Invoke-Checked -Exe $xvlog -WorkingDirectory $simRoot -Arguments @(
        $netlist, $testbench)
    Invoke-Checked -Exe $xelab -WorkingDirectory $simRoot -Arguments @(
        'tb_board_postroute_dac_activity', 'glbl', '-L', 'unisims_ver',
        '-debug', 'typical',
        '-s', 'tb_board_postroute_dac_activity_sim')
    $env:NF_SAIF_PATH = $saif.Replace('\', '/')
    try {
        Invoke-Checked -Exe $xsim -WorkingDirectory $simRoot -Arguments @(
            'tb_board_postroute_dac_activity_sim', '-tclbatch',
            $captureTcl.Replace('\', '/'))
    }
    finally {
        Remove-Item Env:NF_SAIF_PATH -ErrorAction SilentlyContinue
    }
}
else {
    Write-Host "Reusing existing SAIF: $saif"
}

if (-not (Test-Path -LiteralPath $saif)) {
    throw "SAIF was not generated: $saif"
}
$simLog = Join-Path $simRoot 'xsim.log'
if (-not (Test-Path -LiteralPath $simLog) -or
    -not ([System.IO.File]::ReadAllText($simLog).Contains(
        'BOARD POSTROUTE DAC ACTIVITY PASS'))) {
    throw 'Post-route activity simulation did not reach its PASS marker.'
}

Invoke-Checked -Exe $vivado -WorkingDirectory $output -Arguments @(
    '-mode', 'batch', '-source', $powerTcl, '-tclargs', $dcp, $saif,
    $powerReport, $powerSummary)

Write-Host "SAIF_POWER_PASS=$powerSummary"
