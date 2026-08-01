[CmdletBinding()]
param(
    [string]$VivadoExe = 'E:\app\Xilinx2018.3\Vivado\2018.3\bin\vivado.bat'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$nfRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$projectPath = Join-Path $repoRoot `
    'XC7A35T_interp_audio_pcm_wordlen_opt\XC7A35T_interp.xpr'
$configureScript = Join-Path $PSScriptRoot `
    'configure_national_finals_gui_project.tcl'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$runRoot = Join-Path $nfRoot "_work\vivado_gui\$timestamp"
$journalPath = Join-Path $runRoot 'vivado.jou'
$logPath = Join-Path $runRoot 'vivado.log'
$configureJournalPath = Join-Path $runRoot 'configure.jou'
$configureLogPath = Join-Path $runRoot 'configure.log'

foreach ($requiredFile in @($VivadoExe, $projectPath, $configureScript)) {
    if (-not (Test-Path -LiteralPath $requiredFile)) {
        throw "Required Vivado file not found: $requiredFile"
    }
}

New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

$configureArguments = @(
    '-mode', 'batch',
    '-journal', $configureJournalPath,
    '-log', $configureLogPath,
    '-source', $configureScript
)

$arguments = @(
    '-mode', 'gui',
    '-journal', $journalPath,
    '-log', $logPath,
    $projectPath
)

Write-Host "Opening Vivado project: $projectPath"
Write-Host "Isolated GUI work/log directory: $runRoot"

Push-Location $runRoot
try {
    & $VivadoExe @configureArguments
    if ($LASTEXITCODE -ne 0) {
        throw "National-finals GUI configuration failed. Log: $configureLogPath"
    }
    & $VivadoExe @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado GUI exited with code $LASTEXITCODE. Log: $logPath"
    }
}
finally {
    Pop-Location
}
