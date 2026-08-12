param(
    [ValidateSet('Default', 'AddRemap', 'ExploreWithRemap', 'ExploreArea')]
    [string]$OptDirective,

    [ValidateSet('Default', 'Explore', 'ExtraTimingOpt')]
    [string]$PlaceDirective = 'Explore',

    [string]$SynthDcp
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$vivadoBat = 'E:\app\Xilinx20252\2025.2\Vivado\bin\vivado.bat'
$tclScript = Join-Path $scriptDir 'scan_3dsp_implementation_strategies.tcl'
$vivadoRoot = Split-Path -Parent (Split-Path -Parent $vivadoBat)
$tclStore = Join-Path $vivadoRoot 'data\XilinxTclStore'

if ([string]::IsNullOrWhiteSpace($SynthDcp)) {
    $latestDcp = Get-ChildItem -LiteralPath (Join-Path $scriptDir 'results') `
        -Filter 'board_synthesized.dcp' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Directory.Name -like 'cic_dsp_mode1_*' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -ne $latestDcp) {
        $SynthDcp = $latestDcp.FullName
    }
}

if (-not (Test-Path -LiteralPath $vivadoBat -PathType Leaf)) {
    throw "Vivado 2025.2 was not found at $vivadoBat"
}
if ([string]::IsNullOrWhiteSpace($SynthDcp) -or
    -not (Test-Path -LiteralPath $SynthDcp -PathType Leaf)) {
    throw ('A 3-DSP synthesis checkpoint was not found. Rebuild mode=1 with ' +
        'run_cic_dsp_pareto_2025_2.ps1, or pass -SynthDcp explicitly.')
}
$SynthDcp = (Resolve-Path -LiteralPath $SynthDcp).Path
if (@(Get-Process -Name 'vivado' -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'Close every Vivado window before the strategy scan.'
}

$env:XILINX_TCLAPP_REPO = $tclStore
$env:TCLLIBPATH = (@(
    (Join-Path $tclStore 'support\appinit'),
    (Join-Path $tclStore 'support'),
    (Join-Path $tclStore 'tclapp')
) | ForEach-Object { $_.Replace('\', '/') }) -join ' '

$variant = ('{0}_{1}' -f $OptDirective, $PlaceDirective).ToLowerInvariant()
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$resultDir = Join-Path $scriptDir "results\three_dsp_strategy_${variant}_$stamp"
New-Item -ItemType Directory -Force -Path $resultDir | Out-Null

Push-Location $resultDir
try {
    & $vivadoBat -mode batch -notrace -log 'vivado.log' -journal 'vivado.jou' `
        -source $tclScript `
        -tclargs $SynthDcp $resultDir $OptDirective $PlaceDirective
    if ($LASTEXITCODE -ne 0) {
        throw "3-DSP strategy build failed. See $resultDir\vivado.log"
    }
}
finally {
    Pop-Location
}

Write-Host 'THREE_DSP_STRATEGY_POWERSHELL_PASS'
Write-Host "Results: $resultDir"
