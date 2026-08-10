param(
    [ValidateRange(1, 4)]
    [int]$Jobs = 2,

    [ValidateRange(1.0, 32.0)]
    [double]$MinimumCommitHeadroomGB = 4.0,

    [switch]$SkipMemoryGate
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = (Resolve-Path (Join-Path $scriptDir '..\..')).Path
$vivadoBat = 'E:\app\Xilinx20252\2025.2\Vivado\bin\vivado.bat'
$buildScript = Join-Path $scriptDir 'build_project_2025_2.tcl'
$vivadoRoot = Split-Path -Parent (Split-Path -Parent $vivadoBat)
$tclStore = Join-Path $vivadoRoot 'data\XilinxTclStore'

if (-not (Test-Path -LiteralPath $vivadoBat)) {
    throw "Vivado 2025.2 was not found at $vivadoBat"
}

# A stale per-user Tcl Store can prevent open_project before synthesis starts.
# Pin both lookup variables to the known-good installation copy so command-line
# builds are reproducible and do not depend on AppData cache health.
$env:XILINX_TCLAPP_REPO = $tclStore
$env:TCLLIBPATH = (@(
    (Join-Path $tclStore 'support\appinit'),
    (Join-Path $tclStore 'support'),
    (Join-Path $tclStore 'tclapp')
) | ForEach-Object { $_.Replace('\', '/') }) -join ' '

$runningVivado = @(Get-Process -Name 'vivado' -ErrorAction SilentlyContinue)
if ($runningVivado.Count -gt 0) {
    $ids = ($runningVivado.Id | Sort-Object) -join ', '
    throw "Close every Vivado window before the full build. Running PID(s): $ids"
}

$samples = Get-Counter '\Memory\Committed Bytes','\Memory\Commit Limit' |
    Select-Object -ExpandProperty CounterSamples
$committed = ($samples | Where-Object {$_.Path -like '*committed bytes'}).CookedValue
$limit = ($samples | Where-Object {$_.Path -like '*commit limit'}).CookedValue
$headroomGB = ($limit - $committed) / 1GB
Write-Host ('Commit headroom: {0:N2} GB' -f $headroomGB)

if ((-not $SkipMemoryGate) -and ($headroomGB -lt $MinimumCommitHeadroomGB)) {
    throw ('Only {0:N2} GB commit headroom is available. Close memory-heavy applications or increase the Windows page file, then retry. Required: {1:N2} GB.' -f $headroomGB, $MinimumCommitHeadroomGB)
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$resultDir = Join-Path $scriptDir "results\$stamp"
New-Item -ItemType Directory -Force -Path $resultDir | Out-Null
$logPath = Join-Path $resultDir 'vivado_full_build.log'
$journalPath = Join-Path $resultDir 'vivado_full_build.jou'

Write-Host "Project: $projectDir"
Write-Host "Results: $resultDir"
Write-Host "Vivado jobs/threads: $Jobs"

# Run Vivado from the timestamped result directory so transient .Xil and
# other launcher artifacts do not accumulate in the project root.
Push-Location $resultDir
try {
    & $vivadoBat -mode batch -notrace -log $logPath -journal $journalPath `
        -source $buildScript -tclargs $resultDir $Jobs
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado full build failed with exit code $LASTEXITCODE. See $logPath"
    }
} finally {
    Pop-Location
}

Write-Host 'VIVADO_2025_2_POWERSHELL_BUILD_PASS'
Write-Host "Results: $resultDir"
