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
$runRoot = Join-Path $nfRoot "_work\postroute_dac_activity\$timestamp"
$netlist = Join-Path $runRoot 'board_demo_competition_dac8_top_postroute_funcsim.v'
$testbenchSource = Join-Path $PSScriptRoot 'tb_board_postroute_dac_activity.v'
$testbench = Join-Path $runRoot 'tb_board_postroute_dac_activity.v'
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

Write-Host '[postroute-dac] export routed functional netlist'
Invoke-CheckedTool -Executable $vivado -Arguments @(
    '-mode', 'batch', '-source', $exportTcl, '-tclargs', $dcp, $netlist)

Write-Host '[postroute-dac] compile'
Invoke-CheckedTool -Executable $xvlog -Arguments @($netlist, $testbench)

Write-Host '[postroute-dac] elaborate'
Invoke-CheckedTool -Executable $xelab -Arguments @(
    'tb_board_postroute_dac_activity', 'glbl', '-L', 'unisims_ver',
    '-s', 'tb_board_postroute_dac_activity_sim')

Write-Host '[postroute-dac] simulate real board startup and two milliseconds of DAC output'
Invoke-CheckedTool -Executable $xsim -Arguments @(
    'tb_board_postroute_dac_activity_sim', '-runall')

$xsimLog = Join-Path $runRoot 'xsim.log'
if (-not (Test-Path -LiteralPath $xsimLog)) {
    throw 'Post-route simulation did not generate xsim.log'
}
$logText = Get-Content -LiteralPath $xsimLog -Raw
if (-not $logText.Contains('BOARD POSTROUTE DAC ACTIVITY PASS')) {
    throw 'Post-route DAC activity PASS marker was not found'
}
if ($logText -match '(?im)^.*BOARD POSTROUTE DAC ACTIVITY FAIL:') {
    throw 'Post-route DAC activity failure marker was found'
}

Write-Host 'NATIONAL FINALS POSTROUTE BOARD DAC ACTIVITY PASS'
Write-Host "Routed checkpoint: $dcp"
Write-Host "Run directory: $runRoot"
