param(
    [string]$VivadoBat = '',

    [ValidateRange(1, 4)]
    [int]$Jobs = 1,

    [ValidateRange(1.0, 32.0)]
    [double]$MinimumCommitHeadroomGB = 3.0,

    [switch]$SkipMemoryGate
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$tclScript = Join-Path $scriptDir 'run_core_ooc_2025_2.tcl'

if ([string]::IsNullOrWhiteSpace($VivadoBat)) {
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($env:XILINX_VIVADO)) {
        $candidates += (Join-Path $env:XILINX_VIVADO 'bin\vivado.bat')
    }
    $candidates += 'E:\app\Xilinx20252\2025.2\Vivado\bin\vivado.bat'
    $VivadoBat = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

if ([string]::IsNullOrWhiteSpace($VivadoBat) -or -not (Test-Path -LiteralPath $VivadoBat)) {
    throw 'Vivado 2025.2 was not found. Pass -VivadoBat with the full path to vivado.bat.'
}

# Pin Tcl app discovery to the Vivado installation.  This keeps the OOC flow
# reproducible even when the per-user Tcl Store cache is incomplete or corrupt.
$vivadoBin = Split-Path -Parent $VivadoBat
$vivadoRoot = Split-Path -Parent $vivadoBin
$tclStore = Join-Path $vivadoRoot 'data\XilinxTclStore'
if (Test-Path -LiteralPath $tclStore) {
    $tclStoreTclPath = $tclStore.Replace('\', '/')
    $env:XILINX_TCLAPP_REPO = $tclStoreTclPath
    $env:TCLLIBPATH = $tclStoreTclPath
}

$runningVivado = @(Get-Process -Name 'vivado' -ErrorAction SilentlyContinue)
if ($runningVivado.Count -gt 0) {
    $ids = ($runningVivado.Id | Sort-Object) -join ', '
    throw "Close every Vivado window before the OOC run. Running PID(s): $ids"
}

if (-not $SkipMemoryGate) {
    $samples = Get-Counter '\Memory\Committed Bytes','\Memory\Commit Limit' |
        Select-Object -ExpandProperty CounterSamples
    $committed = ($samples | Where-Object {$_.Path -like '*committed bytes'}).CookedValue
    $limit = ($samples | Where-Object {$_.Path -like '*commit limit'}).CookedValue
    $headroomGB = ($limit - $committed) / 1GB
    Write-Host ('Commit headroom: {0:N2} GB' -f $headroomGB)
    if ($headroomGB -lt $MinimumCommitHeadroomGB) {
        throw ('Only {0:N2} GB commit headroom is available; required: {1:N2} GB.' -f $headroomGB, $MinimumCommitHeadroomGB)
    }
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$resultDir = Join-Path $scriptDir "results\$stamp"
New-Item -ItemType Directory -Force -Path $resultDir | Out-Null
$logPath = Join-Path $resultDir 'vivado_core_ooc.log'
$journalPath = Join-Path $resultDir 'vivado_core_ooc.jou'

Write-Host "Vivado: $VivadoBat"
Write-Host "Core OOC results: $resultDir"

Push-Location $resultDir
try {
    & $VivadoBat -mode batch -notrace -log $logPath -journal $journalPath `
        -source $tclScript -tclargs $resultDir $Jobs
    if ($LASTEXITCODE -ne 0) {
        throw "Core OOC run failed with exit code $LASTEXITCODE. See $logPath"
    }
} finally {
    Pop-Location
}

$summaryPath = Join-Path $resultDir 'core_ooc_summary.txt'
if (-not (Test-Path -LiteralPath $summaryPath)) {
    throw "Core OOC summary is missing: $summaryPath"
}

Write-Host ''
Get-Content -LiteralPath $summaryPath
Write-Host ''
Write-Host 'CORE_OOC_2025_2_DEMO_PASS'
Write-Host "Open this report in Vivado or a text editor: $(Join-Path $resultDir 'utilization_post_route.rpt')"
