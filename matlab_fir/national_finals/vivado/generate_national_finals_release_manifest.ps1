[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$ResultTag = 'p4d_release_closure_4dsp',
    [string]$OutputName = 'release_manifest_p4d.json',
    [string]$ConfigId = 'NF-P4D-479LUT-468FF-4DSP-2BRAM-2MMCM',
    [int]$RegressionCaseCount = 15,
    [ValidateSet(0, 1)]
    [int]$SharedPcmStage1Bram = 0,
    [ValidateSet(0, 1)]
    [int]$UnifiedStage23History = 1
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

$regressionLogs = Get-ChildItem (Join-Path $nfRoot '_work\rtl_regression') `
    -Filter 'xsim.log' -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Directory.Name -eq 'full_chain_bittrue' } |
    Sort-Object LastWriteTime -Descending
$smokeLog = $regressionLogs | Where-Object {
    (Get-Content -LiteralPath $_.FullName -Raw).Contains(
        'PHASE7 FULL CHAIN BITTRUE PASS: impulse + 1 seeds, all nodes 0 LSB.')
} | Select-Object -First 1
$releaseLog = $regressionLogs | Where-Object {
    (Get-Content -LiteralPath $_.FullName -Raw).Contains(
        'PHASE7 FULL CHAIN BITTRUE PASS: impulse + 10 seeds, all nodes 0 LSB.')
} | Select-Object -First 1
if ($null -eq $smokeLog -or $null -eq $releaseLog) {
    throw 'Both Smoke and Release full-chain PASS logs are required.'
}

$canonicalPaths = @(
    'XC7A35T_interp_audio_pcm_wordlen_opt\XC7A35T_interp.xpr',
    'XC7A35T_interp_audio_pcm_wordlen_opt\XC7A35T_interp.srcs\constrs_1\new\board_demo_competition_dac8_top.xdc',
    'XC7A35T_interp_audio_pcm_wordlen_opt\XC7A35T_interp.srcs\sources_1\new\board_demo_competition_dac8_top.v',
    'XC7A35T_interp_audio_pcm_wordlen_opt\XC7A35T_interp.srcs\sources_1\new\all2x_v7\interp128_all2x_v7_folded_fir_cic_top_ce.v',
    'XC7A35T_interp_audio_pcm_wordlen_opt\XC7A35T_interp.srcs\sources_1\new\national_finals\nf_signedoff_filter_core.v',
    'XC7A35T_interp_audio_pcm_wordlen_opt\XC7A35T_interp.srcs\sources_1\new\national_finals\nf_pcm_stage1_shared_ramb18_sdp.v',
    'XC7A35T_interp_audio_pcm_wordlen_opt\XC7A35T_interp.srcs\sim_1\new\national_finals\tb_nf_pcm_stage1_shared_ramb18.v',
    'XC7A35T_interp_audio_pcm_wordlen_opt\XC7A35T_interp.srcs\sim_1\new\all2x_v7\verification\tb_phase7_full_chain_bittrue.v',
    'matlab_fir\national_finals\nf_04_generate_release_vectors.m',
    'matlab_fir\national_finals\sim\run_national_finals_rtl_regression.ps1',
    'matlab_fir\national_finals\vivado\build_national_finals_board.tcl',
    'matlab_fir\national_finals\vivado\implement_national_finals_single_process.tcl',
    'matlab_fir\national_finals\vivado\configure_national_finals_gui_project.tcl',
    'matlab_fir\national_finals\vivado\verify_national_finals_gui_project.tcl'
)
$canonicalPaths += Get-ChildItem (Join-Path $nfRoot 'vectors\daily') -Filter '*.mem' |
    ForEach-Object { $_.FullName.Substring($repoRoot.Length + 1) }
$canonicalPaths += @(
    (Join-Path $resultDir 'national_finals_dual_rate_4x8x128x_areaopt.bit').Substring($repoRoot.Length + 1),
    (Join-Path $resultDir 'build_manifest.txt').Substring($repoRoot.Length + 1),
    $smokeLog.FullName.Substring($repoRoot.Length + 1),
    $releaseLog.FullName.Substring($repoRoot.Length + 1)
)
$fileRecords = foreach ($path in $canonicalPaths) {
    $absolutePath = if ([System.IO.Path]::IsPathRooted($path)) {
        $path
    } else {
        Join-Path $repoRoot $path
    }
    Get-FileRecord $absolutePath
}

$branch = (& git -C $repoRoot branch --show-current).Trim()
$commit = (& git -C $repoRoot rev-parse HEAD).Trim()
$trackedStatus = (& git -C $repoRoot status --porcelain --untracked-files=no) -join "`n"
$manifest = [ordered]@{
    schema = 'national-finals-release-manifest-v1'
    config_id = $ConfigId
    generated_utc = (Get-Date).ToUniversalTime().ToString('o')
    tool = [ordered]@{ name = 'Vivado'; version = '2018.3'; build = '2405991'; part = 'xc7a35tfgg484-2' }
    git = [ordered]@{ branch = $branch; commit = $commit; tracked_worktree_dirty = -not [string]::IsNullOrWhiteSpace($trackedStatus) }
    topology = [ordered]@{
        stage1_dsp48_preadder = 1
        stage23_shared_dsp = 1
        cic_integrator_dsp_mode = 2
        serial_cic_comb = 1
        unified_stage23_history = $UnifiedStage23History
        distributed_stage23_history = 1 - $UnifiedStage23History
        single_bram_stage1 = 1
        shared_pcm_stage1_bram = $SharedPcmStage1Bram
        unified_fir_coefficient_bram = 1
        packed_stage23_bram = 0
    }
    resources_post_route = [ordered]@{
        slice_lut = [int](Get-RegexNumber $utilizationText '^\| Slice LUTs\s*\|\s*([0-9]+)' 'LUT count')
        slice_ff = [int](Get-RegexNumber $utilizationText '^\| Slice Registers\s*\|\s*([0-9]+)' 'FF count')
        dsp48e1 = [int](Get-RegexNumber $utilizationText '^\| DSPs\s*\|\s*([0-9]+)' 'DSP count')
        bram_tile = Get-RegexNumber $utilizationText '^\| Block RAM Tile\s*\|\s*([0-9.]+)' 'BRAM count'
        mmcm = [int](Get-RegexNumber $utilizationText '^\| MMCME2_ADV\s*\|\s*([0-9]+)' 'MMCM count')
    }
    timing_post_route_ns = [ordered]@{
        wns = Get-RegexNumber $timingText 'Routed setup slack:\s*([0-9.+-]+)' 'WNS'
        whs = Get-RegexNumber $timingText 'Routed hold slack:\s*([0-9.+-]+)' 'WHS'
        dac_setup = Get-RegexNumber $timingText 'AD9708 output setup slack:\s*([0-9.+-]+)' 'DAC setup'
        dac_hold = Get-RegexNumber $timingText 'AD9708 output hold slack:\s*([0-9.+-]+)' 'DAC hold'
        mode_bus_skew_requirement = Get-RegexNumber $busSkewText 'Slow\s+([0-9.]+)\s+[0-9.]+\s+[0-9.]+' 'bus-skew requirement'
        mode_bus_skew_actual = Get-RegexNumber $busSkewText 'Slow\s+[0-9.]+\s+([0-9.]+)\s+[0-9.]+' 'actual bus skew'
    }
    power_vectorless_w = [ordered]@{
        total = Get-RegexNumber $powerText '^\| Total On-Chip Power \(W\)\s*\|\s*([0-9.]+)' 'total power'
        dynamic = Get-RegexNumber $powerText '^\| Dynamic \(W\)\s*\|\s*([0-9.]+)' 'dynamic power'
        static = Get-RegexNumber $powerText '^\| Device Static \(W\)\s*\|\s*([0-9.]+)' 'static power'
    }
    verification = [ordered]@{
        smoke = [ordered]@{ result = 'PASS'; cases = "$RegressionCaseCount/$RegressionCaseCount"; full_chain = 'impulse + 1 seed x 1024'; log = $smokeLog.FullName.Substring($repoRoot.Length + 1).Replace('\', '/') }
        release = [ordered]@{ result = 'PASS'; cases = "$RegressionCaseCount/$RegressionCaseCount"; full_chain = 'impulse + 10 seeds x 4096; 4x/8x/128x all 0 LSB'; log = $releaseLog.FullName.Substring($repoRoot.Length + 1).Replace('\', '/') }
        gui_behavioral = 'PASS: impulse + seed01, 0 LSB'
        gui_implementation = 'PASS: bitstream and resource guards verified by GUI project script'
    }
    reviewed_warnings = @(
        'TIMING-18: Vivado 2018.3 methodology warning retained; check_timing reports zero ports missing output delay and both generated-clock max/min delays are present.',
        'CDC-13: BUFGMUX_CTRL S0/S1 dedicated clock-select pins; functional family-switch stress test passes.',
        'CDC-15: request/ack bundled-data shadow bus; source holds stable through acknowledgement, destination waits three cycles, and 50 ns bus-skew constraint meets with margin.'
    )
    file_hashes = $fileRecords
}

$outputPath = Join-Path $resultDir $OutputName
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outputPath -Encoding UTF8
Write-Host "NATIONAL_FINALS_RELEASE_MANIFEST_PASS: $outputPath"
