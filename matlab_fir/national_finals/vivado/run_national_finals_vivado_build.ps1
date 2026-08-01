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
    [int]$Stage1Dsp48Preadder = 1,
    [ValidateSet(0, 1, 2)]
    [int]$CicIntegratorDspMode = 2,
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$ResultTag = 'board_dual_rate_cic6_round7_headroom_opt'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$nfRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$runRoot = Join-Path $nfRoot "_work\vivado\$timestamp"
$resultDir = Join-Path $nfRoot "vivado_results\$ResultTag"
$projectFile = Join-Path $repoRoot 'XC7A35T_interp_audio_pcm_wordlen_opt\XC7A35T_interp.xpr'
$synthTcl = Join-Path $PSScriptRoot 'build_national_finals_board.tcl'
$implementTcl = Join-Path $PSScriptRoot 'implement_national_finals_single_process.tcl'

foreach ($requiredFile in @($VivadoExe, $synthTcl, $implementTcl)) {
    if (-not (Test-Path -LiteralPath $requiredFile)) {
        throw "Required build file not found: $requiredFile"
    }
}

$safeDirectory = $repoRoot.Replace('\', '/')
$gitStatusAll = @(& git -c "safe.directory=$safeDirectory" -C $repoRoot `
    status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to capture Git source state before the Vivado build.'
}
if (-not (Test-Path -LiteralPath $projectFile)) {
    throw "Vivado project file not found: $projectFile"
}
$projectFileOriginalBytes = [System.IO.File]::ReadAllBytes($projectFile)
$generatedPrefixes = @(
    'matlab_fir/national_finals/_work/',
    'matlab_fir/national_finals/vivado_results/'
)
$gitStatusSource = @($gitStatusAll | Where-Object {
    $statusPath = if ($_.Length -gt 3) { $_.Substring(3).Replace('\', '/') } else { '' }
    -not ($generatedPrefixes | Where-Object { $statusPath.StartsWith($_) })
})
$gitCommit = (@(& git -c "safe.directory=$safeDirectory" -C $repoRoot rev-parse HEAD) -join '').Trim()
$gitBranch = (@(& git -c "safe.directory=$safeDirectory" -C $repoRoot branch --show-current) -join '').Trim()
if ([string]::IsNullOrWhiteSpace($gitBranch)) {
    $gitBranch = '(detached)'
}

New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
$sourceState = [ordered]@{
    captured_utc = (Get-Date).ToUniversalTime().ToString('o')
    branch = $gitBranch
    commit = $gitCommit
    source_worktree_dirty = ($gitStatusSource.Count -ne 0)
    source_status_porcelain = ($gitStatusSource -join "`n")
    status_porcelain_all = ($gitStatusAll -join "`n")
}
$sourceStateJson = $sourceState | ConvertTo-Json -Depth 4
[System.IO.File]::WriteAllText(
    (Join-Path $resultDir 'source_state_at_build_start.json'),
    $sourceStateJson + [Environment]::NewLine,
    [System.Text.UTF8Encoding]::new($false))

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

try {
    if ($Step -eq 'all' -or $Step -eq 'synth') {
        Invoke-VivadoStep -Name 'synthesis' -TclPath $synthTcl `
            -TclArguments @(
                '0',
                '1',
                $SynthesisDirective,
                $FlattenHierarchy,
                $ResourceSharing,
                $ResultTag,
                $Stage1Dsp48Preadder,
                $CicIntegratorDspMode
            )
    }

    if ($Step -eq 'all' -or $Step -eq 'implement') {
        Invoke-VivadoStep -Name 'implementation' -TclPath $implementTcl `
            -TclArguments @(
                $ResultTag,
                $ImplementationOptDirective
            )
    }
}
finally {
    [System.IO.File]::WriteAllBytes($projectFile, $projectFileOriginalBytes)
}

Write-Host ''
Write-Host "NATIONAL FINALS VIVADO BUILD PASS: $Step"
Write-Host "Isolated work/log directory: $runRoot"
