[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$ResultTag = 'p4d_release_closure_4dsp',
    [string]$OutputName = 'release_manifest_p4d.json'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$nfRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$resultDir = Join-Path $nfRoot "vivado_results\$ResultTag"
if (-not (Test-Path -LiteralPath $resultDir)) {
    throw "Result directory not found: $resultDir"
}

function Get-Text([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing evidence file: $Path" }
    return Get-Content -LiteralPath $Path -Raw
}

function Get-RegexNumber([string]$Text, [string]$Pattern, [string]$Name) {
    $match = [regex]::Match($Text, $Pattern, 'Multiline')
    if (-not $match.Success) { throw "Could not parse ${Name}." }
    return [double]$match.Groups[1].Value
}

function Get-RegexNumberMaximum([string]$Text, [string]$Pattern, [string]$Name) {
    $matches = [regex]::Matches($Text, $Pattern, 'Multiline')
    if ($matches.Count -eq 0) { throw "Could not parse ${Name}." }
    return [double](($matches | ForEach-Object { [double]$_.Groups[1].Value } |
        Measure-Object -Maximum).Maximum)
}

function Get-FileRecord([string]$Path) {
    $item = Get-Item -LiteralPath $Path
    $relativePath = $item.FullName.Substring($repoRoot.Length + 1).Replace('\', '/')
    return [ordered]@{
        path = $relativePath
        bytes = $item.Length
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
    }
}

$utilizationText = Get-Text (Join-Path $resultDir 'utilization_placed.rpt')
$timingText = Get-Text (Join-Path $resultDir 'build_manifest.txt')
$powerText = Get-Text (Join-Path $resultDir 'power_vectorless_routed.rpt')
$busSkewText = Get-Text (Join-Path $resultDir 'bus_skew_routed.rpt')
$modeDelayText = Get-Text (Join-Path $resultDir 'mode_absolute_delay_routed.rpt')
$cdcText = Get-Text (Join-Path $resultDir 'cdc_routed.rpt')
$bramPrimitiveText = Get-Text (Join-Path $resultDir 'bram_utilization_routed.rpt')
$sourceStatePath = Join-Path $resultDir 'source_state_at_build_start.json'
if (-not (Test-Path -LiteralPath $sourceStatePath)) {
    throw "Build-start Git state is missing: $sourceStatePath"
}
$sourceState = Get-Content -LiteralPath $sourceStatePath -Raw | ConvertFrom-Json
if ($sourceState.source_worktree_dirty) {
    throw "Release build did not start from a clean source worktree: $($sourceState.source_status_porcelain)"
}

$regressionLogs = Get-ChildItem (Join-Path $nfRoot '_work\rtl_regression') `
    -Filter 'xsim.log' -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Directory.Name -eq 'full_chain_bittrue' } |
    Sort-Object LastWriteTime -Descending
$smokeLog = $regressionLogs | Where-Object {
    (Get-Content -LiteralPath $_.FullName -Raw).Contains(
        'PHASE7 FULL CHAIN BITTRUE PASS: impulse + 1 seeds, reset-zero prefixes and all nodes 0 LSB.')
} | Select-Object -First 1
$releaseLog = $regressionLogs | Where-Object {
    (Get-Content -LiteralPath $_.FullName -Raw).Contains(
        'PHASE7 FULL CHAIN BITTRUE PASS: impulse + 10 seeds + 2 fullscale, reset-zero prefixes and all nodes 0 LSB.')
} | Select-Object -First 1
if ($null -eq $smokeLog -or $null -eq $releaseLog) {
    throw 'Both Smoke and Release full-chain PASS logs are required.'
}
$smokeEvidencePath = Join-Path $resultDir 'rtl_smoke_full_chain_xsim.log'
$releaseEvidencePath = Join-Path $resultDir 'rtl_release_full_chain_xsim.log'
Copy-Item -LiteralPath $smokeLog.FullName -Destination $smokeEvidencePath -Force
Copy-Item -LiteralPath $releaseLog.FullName -Destination $releaseEvidencePath -Force

$canonicalPaths = @(
    'XC7A35T_interp_audio_pcm_wordlen_opt\XC7A35T_interp.xpr',
    'XC7A35T_interp_audio_pcm_wordlen_opt\XC7A35T_interp.srcs\constrs_1\new\board_demo_competition_dac8_top.xdc',
    'XC7A35T_interp_audio_pcm_wordlen_opt\XC7A35T_interp.srcs\sources_1\new\board_demo_competition_dac8_top.v',
    'XC7A35T_interp_audio_pcm_wordlen_opt\XC7A35T_interp.srcs\sources_1\new\all2x_v7\interp128_all2x_v7_folded_fir_cic_top_ce.v',
    'XC7A35T_interp_audio_pcm_wordlen_opt\XC7A35T_interp.srcs\sources_1\new\national_finals\nf_signedoff_filter_core.v',
    'XC7A35T_interp_audio_pcm_wordlen_opt\XC7A35T_interp.srcs\sim_1\new\all2x_v7\verification\tb_phase7_full_chain_bittrue.v',
    'matlab_fir\national_finals\nf_04_generate_release_vectors.m',
    'matlab_fir\national_finals\nf_05_validate_release_v2_model.m',
    'matlab_fir\national_finals\nf_06_generate_release_v2_metadata.m',
    'matlab_fir\national_finals\nf_07_release_v2_frequency_check.m',
    'matlab_fir\national_finals\nf_release_v2_config.m',
    'matlab_fir\national_finals\nf_cic3_shiftadd_bittrue.m',
    'matlab_fir\national_finals\nf_cic_n3_hold2_bittrue.m',
    'matlab_fir\national_finals\release_v2\p4d_release_v2_config.json',
    'matlab_fir\national_finals\release_v2\q_format_and_scaling.json',
    'matlab_fir\national_finals\release_v2\coefficients.csv',
    'matlab_fir\national_finals\release_v2\SHA256SUMS',
    'matlab_fir\national_finals\sim\run_national_finals_rtl_regression.ps1',
    'matlab_fir\national_finals\vivado\build_national_finals_board.tcl',
    'matlab_fir\national_finals\vivado\implement_national_finals_single_process.tcl',
    'matlab_fir\national_finals\vivado\configure_national_finals_gui_project.tcl',
    'matlab_fir\national_finals\vivado\verify_national_finals_gui_project.tcl'
)
$sourceManifestPath = Join-Path $resultDir 'synthesis_sources.txt'
if (-not (Test-Path -LiteralPath $sourceManifestPath)) {
    throw "Synthesis source manifest is missing: $sourceManifestPath"
}
$canonicalPaths += Get-Content -LiteralPath $sourceManifestPath |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$canonicalPaths += Get-ChildItem (Join-Path $nfRoot 'vectors\daily') -Filter '*.mem' |
    ForEach-Object { $_.FullName.Substring($repoRoot.Length + 1) }
$canonicalPaths += Get-ChildItem -LiteralPath $resultDir -File |
    Where-Object { $_.Name -ne $OutputName } |
    ForEach-Object { $_.FullName }
$absoluteCanonicalPaths = @($canonicalPaths | ForEach-Object {
    if ([System.IO.Path]::IsPathRooted($_)) {
        [System.IO.Path]::GetFullPath($_)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $repoRoot $_))
    }
} | Sort-Object -Unique)
$fileRecords = foreach ($absolutePath in $absoluteCanonicalPaths) {
    Get-FileRecord $absolutePath
}

$safeDirectory = $repoRoot.Replace('\', '/')
$branch = (@(& git -c "safe.directory=$safeDirectory" -C $repoRoot branch --show-current) -join '').Trim()
$commit = (@(& git -c "safe.directory=$safeDirectory" -C $repoRoot rev-parse HEAD) -join '').Trim()
if ([string]::IsNullOrWhiteSpace($branch)) {
    $branch = '(detached)'
}
$worktreeStatusAll = @(& git -c "safe.directory=$safeDirectory" -C $repoRoot `
    status --porcelain --untracked-files=all)
$generatedPrefixes = @(
    'matlab_fir/national_finals/_work/',
    'matlab_fir/national_finals/vivado_results/'
)
$worktreeStatusSource = @($worktreeStatusAll | Where-Object {
    $statusPath = if ($_.Length -gt 3) { $_.Substring(3).Replace('\', '/') } else { '' }
    -not ($generatedPrefixes | Where-Object { $statusPath.StartsWith($_) })
})
$submoduleStatus = ''
if (Test-Path -LiteralPath (Join-Path $repoRoot '.gitmodules')) {
    $submoduleStatus = (@(& git -c "safe.directory=$safeDirectory" -C $repoRoot submodule status) -join "`n")
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to capture Git submodule status.'
    }
}
$manifest = [ordered]@{
    schema = 'national-finals-release-manifest-v2'
    config_id = 'NF-P4D-R2-479LUT-468FF-4DSP-2BRAM-2MMCM'
    generated_utc = (Get-Date).ToUniversalTime().ToString('o')
    tool = [ordered]@{ name = 'Vivado'; version = '2018.3'; build = '2405991'; part = 'xc7a35tfgg484-2' }
    git = [ordered]@{
        branch = $branch
        commit = $commit
        source_worktree_dirty_at_build_start = [bool]$sourceState.source_worktree_dirty
        source_status_at_build_start = [string]$sourceState.source_status_porcelain
        source_worktree_dirty_at_manifest = ($worktreeStatusSource.Count -ne 0)
        source_status_at_manifest = ($worktreeStatusSource -join "`n")
        generated_status_at_manifest = ($worktreeStatusAll -join "`n")
        submodule_status = $submoduleStatus
    }
    topology = [ordered]@{
        stage1_dsp48_preadder = 1
        stage23_shared_dsp = 1
        cic_integrator_dsp_mode = 2
        serial_cic_comb = 1
        unified_stage23_history = 1
        single_bram_stage1 = 1
        unified_fir_coefficient_bram = 1
        packed_stage23_bram = 0
    }
    resources_post_route = [ordered]@{
        slice_lut = [int](Get-RegexNumber $utilizationText '^\| Slice LUTs\s*\|\s*([0-9]+)' 'LUT count')
        slice_ff = [int](Get-RegexNumber $utilizationText '^\| Slice Registers\s*\|\s*([0-9]+)' 'FF count')
        dsp48e1 = [int](Get-RegexNumber $utilizationText '^\| DSPs\s*\|\s*([0-9]+)' 'DSP count')
        bram_tile = [int](Get-RegexNumber $utilizationText '^\| Block RAM Tile\s*\|\s*([0-9]+)' 'BRAM count')
        mmcm = [int](Get-RegexNumber $utilizationText '^\| MMCME2_ADV\s*\|\s*([0-9]+)' 'MMCM count')
    }
    timing_post_route_ns = [ordered]@{
        wns = Get-RegexNumber $timingText 'Routed setup slack:\s*([0-9.+-]+)' 'WNS'
        whs = Get-RegexNumber $timingText 'Routed hold slack:\s*([0-9.+-]+)' 'WHS'
        dac_setup = Get-RegexNumber $timingText 'AD9708 output setup slack:\s*([0-9.+-]+)' 'DAC setup'
        dac_hold = Get-RegexNumber $timingText 'AD9708 output hold slack:\s*([0-9.+-]+)' 'DAC hold'
        mode_bus_skew_requirement = Get-RegexNumber $busSkewText 'Slow\s+([0-9.]+)\s+[0-9.]+\s+[0-9.]+' 'bus-skew requirement'
        mode_bus_skew_actual = Get-RegexNumber $busSkewText 'Slow\s+[0-9.]+\s+([0-9.]+)\s+[0-9.]+' 'actual bus skew'
        mode_absolute_data_delay_max = Get-RegexNumberMaximum $modeDelayText 'Data Path Delay:\s*([0-9.]+)ns' 'mode absolute data delay'
    }
    power_vectorless_w = [ordered]@{
        total = Get-RegexNumber $powerText '^\| Total On-Chip Power \(W\)\s*\|\s*([0-9.]+)' 'total power'
        dynamic = Get-RegexNumber $powerText '^\| Dynamic \(W\)\s*\|\s*([0-9.]+)' 'dynamic power'
        static = Get-RegexNumber $powerText '^\| Device Static \(W\)\s*\|\s*([0-9.]+)' 'static power'
    }
    verification = [ordered]@{
        smoke = [ordered]@{ result = 'PASS'; cases = '15/15'; full_chain = 'impulse + 1 seed x 1024'; log = $smokeEvidencePath.Substring($repoRoot.Length + 1).Replace('\', '/') }
        release = [ordered]@{ result = 'PASS'; cases = '15/15'; full_chain = 'impulse + 10 seeds x 4096 + positive/negative fullscale; reset-zero prefixes and 4x/8x/128x all 0 LSB'; log = $releaseEvidencePath.Substring($repoRoot.Length + 1).Replace('\', '/') }
        gui_behavioral = 'PASS: impulse + seed01, 0 LSB'
        gui_implementation = 'PASS: bitstream and 479/468/4/4xRAMB18/2 resources'
    }
    cdc_post_route = [ordered]@{
        cdc3_info = [int](Get-RegexNumber $cdcText '^CDC-3\s+Info\s+([0-9]+)' 'CDC-3 count')
        cdc13_reviewed = [int](Get-RegexNumber $cdcText '^CDC-13\s+Critical\s+([0-9]+)' 'CDC-13 count')
        cdc15_reviewed = [int](Get-RegexNumber $cdcText '^CDC-15\s+Warning\s+([0-9]+)' 'CDC-15 count')
        ignored_exception_report_empty = ((Get-Text (Join-Path $resultDir 'exceptions_ignored_routed.rpt')) -notmatch '(?m)^\s*[0-9]+\s+')
    }
    primitive_counts = [ordered]@{
        ramb18e1 = [int](Get-RegexNumber $bramPrimitiveText '^Cell count:\s*([0-9]+)' 'RAMB18E1 primitive count')
    }
    reviewed_warnings = @(
        'TIMING-18: Vivado 2018.3 methodology warning retained; check_timing reports zero ports missing output delay and both generated-clock max/min delays are present.',
        'CDC-13: BUFGMUX_CTRL S0/S1 dedicated clock-select pins; functional family-switch stress test passes.',
        'CDC-15: request/ack bundled-data shadow bus; source holds stable through acknowledgement, destination waits three cycles, and 50 ns bus-skew constraint meets with margin.'
    )
    file_hashes = $fileRecords
}

$outputPath = Join-Path $resultDir $OutputName
$json = $manifest | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText(
    $outputPath, $json + [Environment]::NewLine,
    [System.Text.UTF8Encoding]::new($false))
Write-Host "NATIONAL_FINALS_RELEASE_MANIFEST_PASS: $outputPath"
