param(
    [ValidateRange(1, 4)]
    [int]$Jobs = 1
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$vivadoBat = 'E:\app\Xilinx20252\2025.2\Vivado\bin\vivado.bat'
$tclScript = Join-Path $scriptDir 'build_3dsp_integrator_pair_candidate.tcl'
$vivadoRoot = Split-Path -Parent (Split-Path -Parent $vivadoBat)
$tclStore = Join-Path $vivadoRoot 'data\XilinxTclStore'

if (-not (Test-Path -LiteralPath $vivadoBat -PathType Leaf)) {
    throw "Vivado 2025.2 was not found at $vivadoBat"
}
if (@(Get-Process -Name 'vivado' -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'Close every Vivado window before the candidate build.'
}

$env:XILINX_TCLAPP_REPO = $tclStore
$env:TCLLIBPATH = (@(
    (Join-Path $tclStore 'support\appinit'),
    (Join-Path $tclStore 'support'),
    (Join-Path $tclStore 'tclapp')
) | ForEach-Object { $_.Replace('\', '/') }) -join ' '

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$resultDir = Join-Path $scriptDir "results\3dsp_pair_$stamp"
New-Item -ItemType Directory -Force -Path $resultDir | Out-Null
$projectDir = Split-Path -Parent `
    (Split-Path -Parent (Split-Path -Parent $scriptDir))
$projectFile = Join-Path $projectDir 'XC7A35T_interp.xpr'
$projectHashBefore = (Get-FileHash -Algorithm SHA256 `
    -LiteralPath $projectFile).Hash
$buildFailed = $false

Push-Location $resultDir
try {
    & $vivadoBat -mode batch -notrace -log 'vivado.log' `
        -journal 'vivado.jou' -source $tclScript `
        -tclargs $resultDir $Jobs
    if ($LASTEXITCODE -ne 0) {
        $buildFailed = $true
    }
}
finally {
    Pop-Location
    $projectHashAfter = (Get-FileHash -Algorithm SHA256 `
        -LiteralPath $projectFile).Hash
    if ($projectHashAfter -ne $projectHashBefore) {
        throw 'The isolated experiment unexpectedly modified the project file.'
    }
}

if ($buildFailed) {
    throw "3-DSP integrator-pair candidate failed. See $resultDir\vivado.log"
}

Write-Host 'THREE_DSP_PAIR_POWERSHELL_PASS'
Write-Host "Results: $resultDir"
