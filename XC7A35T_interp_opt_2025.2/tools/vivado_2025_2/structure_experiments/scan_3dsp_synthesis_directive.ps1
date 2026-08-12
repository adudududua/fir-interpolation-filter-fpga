param(
    [ValidateSet('Default', 'AreaOptimized_medium',
        'FewerCarryChains', 'AlternateRoutability')]
    [string]$SynthesisDirective,

    [ValidateRange(1, 4)]
    [int]$Jobs = 1
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$vivadoBat = 'E:\app\Xilinx20252\2025.2\Vivado\bin\vivado.bat'
$tclScript = Join-Path $scriptDir 'scan_3dsp_synthesis_directive.tcl'
$vivadoRoot = Split-Path -Parent (Split-Path -Parent $vivadoBat)
$tclStore = Join-Path $vivadoRoot 'data\XilinxTclStore'

if (@(Get-Process -Name 'vivado' -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'Close every Vivado window before the synthesis scan.'
}

$env:XILINX_TCLAPP_REPO = $tclStore
$env:TCLLIBPATH = (@(
    (Join-Path $tclStore 'support\appinit'),
    (Join-Path $tclStore 'support'),
    (Join-Path $tclStore 'tclapp')
) | ForEach-Object { $_.Replace('\', '/') }) -join ' '

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$safeName = $SynthesisDirective.ToLowerInvariant()
$repositoryRoot = (Resolve-Path `
    (Join-Path $scriptDir '..\..\..\..')).Path
# Incremental synthesis creates deeply nested realtime paths.  Keep this
# scratch directory at repository root to stay below the Windows path limit.
$resultDir = Join-Path $repositoryRoot ".v25_3dsp_${safeName}_$stamp"
New-Item -ItemType Directory -Force -Path $resultDir | Out-Null

Push-Location $resultDir
try {
    & $vivadoBat -mode batch -notrace -log 'vivado.log' `
        -journal 'vivado.jou' -source $tclScript `
        -tclargs $resultDir $SynthesisDirective $Jobs
    if ($LASTEXITCODE -ne 0) {
        throw "3-DSP synthesis scan failed. See $resultDir\vivado.log"
    }
}
finally {
    Pop-Location
}

Write-Host 'THREE_DSP_SYNTHESIS_SCAN_POWERSHELL_PASS'
Write-Host "Results: $resultDir"
