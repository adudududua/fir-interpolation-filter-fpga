[CmdletBinding()]
param(
    [string]$VivadoExe = 'E:\app\Xilinx2018.3\Vivado\2018.3\bin\vivado.bat',
    [ValidateSet('all', 'synth', 'implement')]
    [string]$Step = 'all',
    [ValidateSet('Default', 'AreaOptimized_high', 'AreaOptimized_medium')]
    [string]$SynthesisDirective = 'AreaOptimized_high',
    [ValidateSet('rebuilt', 'full', 'none')]
    [string]$FlattenHierarchy = 'rebuilt',
    [ValidateSet('auto', 'on', 'off')]
    [string]$ResourceSharing = 'on',
    [ValidateSet('Default', 'Explore', 'ExploreWithRemap', 'ExploreArea', 'AddRemap')]
    [string]$ImplementationOptDirective = 'Default',
    [ValidateSet(0, 1)]
    [int]$Stage1Dsp48Preadder = 0,
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$ResultTag = 'board_dual_rate_cic6_round5_opt'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$nfRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$runRoot = Join-Path $nfRoot "_work\vivado\$timestamp"
$synthTcl = Join-Path $PSScriptRoot 'build_national_finals_board.tcl'
$implementTcl = Join-Path $PSScriptRoot 'implement_national_finals_single_process.tcl'

foreach ($requiredFile in @($VivadoExe, $synthTcl, $implementTcl)) {
    if (-not (Test-Path -LiteralPath $requiredFile)) {
        throw "Required build file not found: $requiredFile"
    }
}

New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

function Invoke-VivadoStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$TclPath,
        [string[]]$TclArguments = @()
    )

    $journalPath = Join-Path $runRoot "$Name.jou"
    $logPath = Join-Path $runRoot "$Name.log"
    $arguments = @(
        '-mode', 'batch',
        '-journal', $journalPath,
        '-log', $logPath,
        '-source', $TclPath
    )
    if ($TclArguments.Count -gt 0) {
        $arguments += '-tclargs'
        $arguments += $TclArguments
    }

    Write-Host "[$Name] Vivado start"
    Push-Location $runRoot
    try {
        $toolOutput = & $VivadoExe @arguments 2>&1
        $exitCode = $LASTEXITCODE
        foreach ($line in $toolOutput) {
            Write-Host $line
        }
        if ($exitCode -ne 0) {
            throw "Vivado step '$Name' failed with exit code $exitCode. Log: $logPath"
        }
    }
    finally {
        Pop-Location
    }
    Write-Host "[$Name] PASS"
}

if ($Step -eq 'all' -or $Step -eq 'synth') {
    Invoke-VivadoStep -Name 'synthesis' -TclPath $synthTcl `
        -TclArguments @(
            '0',
            '1',
            $SynthesisDirective,
            $FlattenHierarchy,
            $ResourceSharing,
            $ResultTag,
            $Stage1Dsp48Preadder
        )
}

if ($Step -eq 'all' -or $Step -eq 'implement') {
    Invoke-VivadoStep -Name 'implementation' -TclPath $implementTcl `
        -TclArguments @(
            $ResultTag,
            $ImplementationOptDirective
        )
}

Write-Host ''
Write-Host "NATIONAL FINALS VIVADO BUILD PASS: $Step"
Write-Host "Isolated work/log directory: $runRoot"
