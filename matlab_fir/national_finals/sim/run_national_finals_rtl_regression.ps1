[CmdletBinding()]
param(
    [string]$VivadoBin = 'E:\app\Xilinx2018.3\Vivado\2018.3\bin',
    [ValidateSet('Smoke', 'Release')]
    [string]$RegressionScale = 'Smoke',
    [ValidateSet(0, 1, 2)]
    [int]$CicIntegratorDspMode = 2,
    [string]$VectorDir = '',
    [switch]$PublishImpulseOutputs
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$projectRoot = Join-Path $repoRoot 'XC7A35T_interp_audio_pcm_wordlen_opt\XC7A35T_interp.srcs'
$sourceRoot = Join-Path $projectRoot 'sources_1\new'
$simRoot = Join-Path $projectRoot 'sim_1\new'
$nfRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$p3Root = Join-Path $nfRoot 'p3_joint_stage3_equalizer'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$runRoot = Join-Path $nfRoot "_work\rtl_regression\$timestamp"

$xvlog = Join-Path $VivadoBin 'xvlog.bat'
$xelab = Join-Path $VivadoBin 'xelab.bat'
$xsim = Join-Path $VivadoBin 'xsim.bat'
$glbl = Join-Path (Split-Path $VivadoBin -Parent) 'data\verilog\src\glbl.v'

foreach ($tool in @($xvlog, $xelab, $xsim, $glbl)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Required Vivado Simulator file not found: $tool"
    }
}

New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

function Invoke-CheckedTool {
    param(
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    Push-Location $WorkingDirectory
    try {
        $toolOutput = & $Executable @Arguments 2>&1
        foreach ($line in $toolOutput) {
            Write-Host $line
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Tool failed with exit code ${LASTEXITCODE}: $Executable"
        }
    }
    finally {
        Pop-Location
    }
}

function Invoke-RtlCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$VerilogFiles,
        [Parameter(Mandatory = $true)][string]$Top,
        [Parameter(Mandatory = $true)][string]$Snapshot,
        [Parameter(Mandatory = $true)][string]$ExpectedPassText,
        [string[]]$XvlogOptions = @(),
        [string[]]$XelabOptions = @(),
        [string[]]$Assets = @()
    )

    $caseDir = Join-Path $runRoot $Name
    New-Item -ItemType Directory -Path $caseDir -Force | Out-Null

    foreach ($asset in $Assets) {
        Copy-Item -LiteralPath $asset -Destination $caseDir -Force
    }

    Write-Host "[$Name] compile"
    Invoke-CheckedTool -WorkingDirectory $caseDir -Executable $xvlog `
        -Arguments ($XvlogOptions + $VerilogFiles)

    Write-Host "[$Name] elaborate"
    Invoke-CheckedTool -WorkingDirectory $caseDir -Executable $xelab `
        -Arguments (@($Top) + $XelabOptions + @('-s', $Snapshot))

    Write-Host "[$Name] simulate"
    Invoke-CheckedTool -WorkingDirectory $caseDir -Executable $xsim `
        -Arguments @($Snapshot, '-runall')

    $xsimLog = Join-Path $caseDir 'xsim.log'
    if (-not (Test-Path -LiteralPath $xsimLog)) {
        throw "[$Name] xsim.log was not generated"
    }

    $logText = Get-Content -LiteralPath $xsimLog -Raw
    if (-not $logText.Contains($ExpectedPassText)) {
        throw "[$Name] expected PASS marker was not found: $ExpectedPassText"
    }
    if ($logText -match '(?im)^\s*(FAIL|FATAL|ERROR)\b') {
        throw "[$Name] failure text was found in xsim.log"
    }

    Write-Host "[$Name] PASS"
    return $caseDir
}

$nfSource = Join-Path $sourceRoot 'national_finals'
$nfSim = Join-Path $simRoot 'national_finals'
$signedOffFullChainXvlogOptions = @(
    '-d', 'NATIONAL_FINALS',
    '-d', 'NATIONAL_FINALS_P3',
    '-d', 'NATIONAL_FINALS_USE_SERIAL_CIC_COMB',
    '-d', 'NATIONAL_FINALS_USE_N3_HOLD',
    '-d', 'NATIONAL_FINALS_USE_STAGE1_DSP48_PREADDER',
    '-d', 'NATIONAL_FINALS_NARROW_STAGE23',
    '-d', 'PHASE7_USE_LUTRAM_STAGE23',
    '-d', 'PHASE7_USE_BRAM_STAGE23_HISTORY',
    '-d', 'NATIONAL_FINALS_UNIFIED_STAGE23_HISTORY',
    '-d', 'NATIONAL_FINALS_SINGLE_BRAM_STAGE1',
    '-d', 'PHASE7_USE_BRAM_STAGE23_COEFF'
)
if ($CicIntegratorDspMode -lt 2) {
    $signedOffFullChainXvlogOptions += @(
        '-d', "NF_CIC_INTEGRATOR_DSP_MODE_$CicIntegratorDspMode")
}
$v7Source = Join-Path $sourceRoot 'all2x_v7'
$v7Sim = Join-Path $simRoot 'all2x_v7\verification'
$coeffHeader = Join-Path $sourceRoot 'all2x_v2\all2x_v2_coeff_pkg.vh'

if ([string]::IsNullOrWhiteSpace($VectorDir)) {
    if ($RegressionScale -eq 'Release') {
        $VectorDir = Join-Path $p3Root '_work\rtl_vectors'
    }
    else {
        $VectorDir = Join-Path $nfRoot 'vectors\p3j_daily'
    }
}
if (-not (Test-Path -LiteralPath $VectorDir)) {
    throw "Vector directory not found for $RegressionScale regression: $VectorDir"
}
$VectorDir = (Resolve-Path -LiteralPath $VectorDir).Path
$vectorManifestPath = Join-Path $VectorDir 'p3_rtl_vector_manifest.csv'
if (-not (Test-Path -LiteralPath $vectorManifestPath)) {
    throw "P3-J vector manifest is missing: $vectorManifestPath"
}
$vectorManifestRows = @(Import-Csv -LiteralPath $vectorManifestPath)
if ($vectorManifestRows.Count -eq 0 -or
    @($vectorManifestRows | Where-Object {
        $_.CONFIG_ID -ne 'NF-P3-RTL-JOINT-STAGE3-EQ-R1'
    }).Count -ne 0) {
    throw "Vector directory is not the signed-off P3-J configuration: $VectorDir"
}
$expectedSeedCount = if ($RegressionScale -eq 'Release') { 10 } else { 1 }
$requiredVectorNames = @(
    'impulse_input_24bit.mem',
    'impulse_y4_golden_24bit.mem',
    'impulse_y8_golden_24bit.mem',
    'impulse_y128_golden_24bit.mem'
)
for ($seedIndex = 1; $seedIndex -le $expectedSeedCount; $seedIndex++) {
    $seedName = 'random_seed{0:d2}' -f $seedIndex
    $requiredVectorNames += @(
        "${seedName}_input_24bit.mem",
        "${seedName}_y4_golden_24bit.mem",
        "${seedName}_y8_golden_24bit.mem",
        "${seedName}_y128_golden_24bit.mem"
    )
}
if ($RegressionScale -eq 'Release') {
    foreach ($directedName in @(
            'fullscale_positive',
            'fullscale_negative',
            'strong_44k1_minus1dbfs')) {
        $requiredVectorNames += @(
            "${directedName}_input_24bit.mem",
            "${directedName}_y4_golden_24bit.mem",
            "${directedName}_y8_golden_24bit.mem",
            "${directedName}_y128_golden_24bit.mem"
        )
    }
}
$vectorFiles = foreach ($vectorName in $requiredVectorNames) {
    $vectorPath = Join-Path $VectorDir $vectorName
    if (-not (Test-Path -LiteralPath $vectorPath)) {
        throw "Required $RegressionScale vector is missing: $vectorPath"
    }
    $vectorPath
}
$fullChainXvlogOptions = @($signedOffFullChainXvlogOptions)
if ($RegressionScale -eq 'Release') {
    $fullChainXvlogOptions += @('-d', 'NF_RELEASE_REGRESSION')
}
$fullChainPassText = if ($RegressionScale -eq 'Release') {
    'PHASE7 FULL CHAIN BITTRUE PASS: impulse + 10 seeds + 2 fullscale + strong -1 dBFS, reset-zero prefixes and all nodes 0 LSB.'
}
else {
    'PHASE7 FULL CHAIN BITTRUE PASS: impulse + 1 seeds, reset-zero prefixes and all nodes 0 LSB.'
}

$signedOffWrapperPath = Join-Path $nfSource 'nf_signedoff_filter_core.v'
$fullChainTbPath = Join-Path $v7Sim 'tb_phase7_full_chain_bittrue.v'
if ($CicIntegratorDspMode -lt 2) {
    $generatedCandidateDir = Join-Path $runRoot 'generated_candidate'
    New-Item -ItemType Directory -Path $generatedCandidateDir -Force | Out-Null
    $candidateModuleName = "nf_p3j_cic_mode${CicIntegratorDspMode}_filter_core"

    $wrapperText = [System.IO.File]::ReadAllText($signedOffWrapperPath)
    $moduleNeedle = 'module nf_signedoff_filter_core ('
    if (([regex]::Matches($wrapperText,
            [regex]::Escape($moduleNeedle))).Count -ne 1) {
        throw 'Could not uniquely rewrite the P3-J signed-off wrapper module name.'
    }
    $dspNeedle = '.CIC_INTEGRATOR_DSP_MODE(2),'
    if (([regex]::Matches($wrapperText,
            [regex]::Escape($dspNeedle))).Count -ne 2) {
        throw 'Could not find both signed-off CIC DSP mode literals.'
    }
    $wrapperText = $wrapperText.Replace(
        $moduleNeedle, "module $candidateModuleName (")
    $wrapperText = $wrapperText.Replace(
        $dspNeedle, ".CIC_INTEGRATOR_DSP_MODE($CicIntegratorDspMode),")
    $candidateWrapperPath = Join-Path $generatedCandidateDir "${candidateModuleName}.v"
    [System.IO.File]::WriteAllText(
        $candidateWrapperPath, $wrapperText,
        [System.Text.UTF8Encoding]::new($false))

    $tbText = [System.IO.File]::ReadAllText($fullChainTbPath)
    $tbNeedle = 'nf_signedoff_filter_core u_dut ('
    if (([regex]::Matches($tbText,
            [regex]::Escape($tbNeedle))).Count -ne 1) {
        throw 'Could not uniquely bind the generated P3-J candidate wrapper.'
    }
    $tbText = $tbText.Replace(
        $tbNeedle, "$candidateModuleName u_dut (")
    $candidateFullChainTbPath = Join-Path $generatedCandidateDir 'tb_phase7_full_chain_bittrue.v'
    [System.IO.File]::WriteAllText(
        $candidateFullChainTbPath, $tbText,
        [System.Text.UTF8Encoding]::new($false))
}
else {
    $candidateWrapperPath = $signedOffWrapperPath
    $candidateFullChainTbPath = $fullChainTbPath
}

$romDir = Invoke-RtlCase -Name 'rom' `
    -VerilogFiles @(
        (Join-Path $nfSource 'dual_rate_test_tone_rom_source.v'),
        (Join-Path $nfSim 'tb_dual_rate_test_tone_rom_source.v')
    ) `
    -Top 'tb_dual_rate_test_tone_rom_source' `
    -Snapshot 'tb_nf_rom_sim' `
    -ExpectedPassText 'PASS: dual-rate ROM data, wrap, and synchronous family reset' `
    -Assets @((Join-Path $nfSource 'nf_sine_15k_dual_rate_24bit_256.mem'))

$coeffPrimitiveDir = Invoke-RtlCase -Name 'unified_coeff_ramb18_primitive' `
    -VerilogFiles @(
        (Join-Path $nfSource 'nf_unified_fir_coeff_bram.v'),
        (Join-Path $nfSim 'tb_nf_unified_fir_coeff_bram_primitive.v'),
        $glbl
    ) `
    -Top 'tb_nf_unified_fir_coeff_bram_primitive' `
    -Snapshot 'tb_nf_unified_coeff_primitive_sim' `
    -ExpectedPassText 'UNIFIED COEFFICIENT RAMB18 PRIMITIVE PASS: coefficients plus Stage1/Stage23 last flags' `
    -XvlogOptions @('-d', 'SYNTHESIS') `
    -XelabOptions @('glbl', '-L', 'unisims_ver')

$historyPrimitiveDir = Invoke-RtlCase -Name 'history_ramb18_primitive' `
    -VerilogFiles @(
        (Join-Path $nfSource 'nf_stage1_history_ramb18_sdp.v'),
        (Join-Path $nfSource 'nf_stage23_history_ramb18_sdp.v'),
        (Join-Path $nfSim 'tb_nf_history_ramb18_primitive.v'),
        $glbl
    ) `
    -Top 'tb_nf_history_ramb18_primitive' `
    -Snapshot 'tb_nf_history_primitive_sim' `
    -ExpectedPassText 'HISTORY RAMB18 PRIMITIVE PASS: Stage1 64x24 and Stage2/3 32x22, sweep=128 random=5000' `
    -XelabOptions @('glbl', '-L', 'unisims_ver')

$stage1SingleBramDir = Invoke-RtlCase -Name 'stage1_single_bram_equivalence' `
    -VerilogFiles @(
        (Join-Path $sourceRoot 'all2x_v3\interp2_stage1_strict_halfband_bram_ce.v'),
        (Join-Path $nfSource 'nf_stage1_history_ramb18_sdp.v'),
        (Join-Path $nfSource 'interp2_stage1_single_bram_serial_ce.v'),
        (Join-Path $nfSim 'tb_stage1_single_bram_equiv.v'),
        $glbl
    ) `
    -Top 'tb_stage1_single_bram_equiv' `
    -Snapshot 'tb_nf_stage1_single_bram_sim' `
    -ExpectedPassText 'STAGE1 SINGLE BRAM EQUIVALENCE PASS' `
    -XelabOptions @('glbl', '-L', 'unisims_ver') `
    -Assets @((Join-Path $sourceRoot 'all2x_v3\all2x_v3_stage1_coeff_pkg.vh'))

$equalizerDir = Invoke-RtlCase -Name 'equalizer' `
    -VerilogFiles @(
        (Join-Path $nfSource 'cic3_compensator_shiftadd_ce.v'),
        (Join-Path $nfSim 'tb_cic3_compensator_shiftadd_ce.v')
    ) `
    -Top 'tb_cic3_compensator_shiftadd_ce' `
    -Snapshot 'tb_nf_equalizer_sim' `
    -ExpectedPassText 'NF CIC3 SHIFTADD COMPENSATOR PASS samples=2009'

$stage23UnifiedDir = Invoke-RtlCase -Name 'stage23_unified_history' `
    -VerilogFiles @(
        (Join-Path $sourceRoot 'all2x_v6\round_sat_shift_compact.v'),
        (Join-Path $sourceRoot 'all2x_v5\round_sat_q15_compact_to24.v'),
        (Join-Path $nfSource 'nf_stage23_history_ramb18_sdp.v'),
        (Join-Path $v7Source 'interp2_stage23_folded_cic_dsp_ce.v'),
        (Join-Path $v7Source 'interp2_stage23_lutram_cic_dsp_ce.v'),
        (Join-Path $v7Sim 'tb_stage23_lutram_dsp_equiv.v'),
        $glbl
    ) `
    -Top 'tb_stage23_lutram_dsp_equiv' `
    -Snapshot 'tb_nf_stage23_unified_history_sim' `
    -ExpectedPassText 'PASS: Stage 2/3 LUTRAM candidate is 0 LSB equivalent.' `
    -XvlogOptions @(
        '-d', 'PHASE7_ENABLE_BRAM_HISTORY',
        '-d', 'NATIONAL_FINALS_UNIFIED_STAGE23_HISTORY'
    ) `
    -XelabOptions @('glbl', '-L', 'unisims_ver') `
    -Assets @($coeffHeader)

$cicSerialDir = Invoke-RtlCase -Name 'cic_serial_equivalence' `
    -VerilogFiles @(
        (Join-Path $sourceRoot 'all2x_v6\round_sat_shift_compact.v'),
        (Join-Path $v7Source 'cic_interp16_core_dsp_ce.v'),
        (Join-Path $nfSource 'cic_interp16_serial_comb_dsp_ce.v'),
        (Join-Path $nfSim 'tb_cic_interp16_serial_comb_equiv.v')
    ) `
    -Top 'tb_cic_interp16_serial_comb_equiv' `
    -Snapshot 'tb_nf_cic_serial_equiv_sim' `
    -ExpectedPassText 'CIC SERIAL COMB EQUIVALENCE PASS'

$cicHoldDir = Invoke-RtlCase -Name 'cic_n3_hold_equivalence' `
    -VerilogFiles @(
        (Join-Path $sourceRoot 'all2x_v6\round_sat_shift_compact.v'),
        (Join-Path $nfSource 'cic_interp16_serial_comb_dsp_ce.v'),
        (Join-Path $nfSource 'cic_interp16_n3_hold2_dsp_ce.v'),
        (Join-Path $nfSim 'tb_cic_interp16_n3_hold_equiv.v')
    ) `
    -Top 'tb_cic_interp16_n3_hold_equiv' `
    -Snapshot 'tb_nf_cic_n3_hold_equiv_sim' `
    -ExpectedPassText 'N3 HOLD CIC EQUIVALENCE PASS'

$clockDir = Invoke-RtlCase -Name 'clock' `
    -VerilogFiles @(
        (Join-Path $nfSource 'dual_family_audio_clock.v'),
        (Join-Path $nfSim 'tb_dual_family_audio_clock.v'),
        $glbl
    ) `
    -Top 'tb_dual_family_audio_clock' `
    -Snapshot 'tb_nf_clock_sim' `
    -ExpectedPassText 'PASS: dual-family clock frequency and glitchless switching' `
    -XelabOptions @('glbl', '-L', 'unisims_ver')

$modeCdcDir = Invoke-RtlCase -Name 'mode_cdc_handshake' `
    -VerilogFiles @(
        (Join-Path $nfSource 'nf_mode_cdc_handshake.v'),
        (Join-Path $nfSim 'tb_nf_mode_cdc_handshake.v')
    ) `
    -Top 'tb_nf_mode_cdc_handshake' `
    -Snapshot 'tb_nf_mode_cdc_handshake_sim' `
    -ExpectedPassText 'NF MODE CDC HANDSHAKE PASS: 1200 directed transitions, atomic commit, stable bundled data, one ACK each.'

$keypadDir = Invoke-RtlCase -Name 'keypad' `
    -VerilogFiles @(
        (Join-Path $sourceRoot 'board_demo_competition_dac8_top.v'),
        (Join-Path $sourceRoot 'matrix_keypad_mode_ctrl_compact.v'),
        (Join-Path $nfSource 'matrix_keypad_mode_ctrl_ultracompact.v'),
        (Join-Path $v7Sim 'tb_matrix_keypad_mode_ctrl_compact.v')
    ) `
    -Top 'tb_matrix_keypad_mode_ctrl_compact' `
    -Snapshot 'tb_nf_keypad_sim' `
    -ExpectedPassText 'PASS: compact keypad matches SW1-SW8 family/mode behavior'

$boardDir = Invoke-RtlCase -Name 'board' `
    -VerilogFiles @(
        (Join-Path $sourceRoot 'board_demo_competition_dac8_top.v'),
        (Join-Path $sourceRoot 'matrix_keypad_mode_ctrl_compact.v'),
        (Join-Path $nfSource 'matrix_keypad_mode_ctrl_ultracompact.v'),
        (Join-Path $nfSource 'nf_mode_cdc_handshake.v'),
        (Join-Path $v7Sim 'tb_board_phase7_shared_keypad_scan.v')
    ) `
    -Top 'tb_board_phase7_shared_keypad_scan' `
    -Snapshot 'tb_nf_board_sim' `
    -ExpectedPassText 'NATIONAL FINALS BOARD INTEGRATION PASS'

$fullDir = Invoke-RtlCase -Name 'full_chain_bittrue' `
    -VerilogFiles @(
        (Join-Path $sourceRoot 'all2x_v6\round_sat_shift_compact.v'),
        (Join-Path $sourceRoot 'all2x_v3\interp2_stage1_strict_halfband_bram_ce.v'),
        (Join-Path $nfSource 'nf_stage1_history_ramb18_sdp.v'),
        (Join-Path $nfSource 'interp2_stage1_single_bram_serial_ce.v'),
        (Join-Path $sourceRoot 'all2x_v6\bridge_valid_quantized_to_interp2_ce.v'),
        (Join-Path $sourceRoot 'all2x_v5\round_sat_q15_compact_to24.v'),
        (Join-Path $v7Source 'interp2_stage23_folded_cic_dsp_ce.v'),
        (Join-Path $v7Source 'interp2_stage23_lutram_cic_dsp_ce.v'),
        (Join-Path $nfSource 'nf_unified_fir_coeff_bram.v'),
        (Join-Path $nfSource 'nf_stage23_history_ramb18_sdp.v'),
        (Join-Path $nfSource 'cic3_compensator_shiftadd_ce.v'),
        (Join-Path $v7Source 'cic_interp16_core_dsp_ce.v'),
        (Join-Path $nfSource 'cic_interp16_serial_comb_dsp_ce.v'),
        (Join-Path $nfSource 'cic_interp16_n3_hold2_dsp_ce.v'),
        (Join-Path $v7Source 'interp128_all2x_v7_folded_fir_cic_top_ce.v'),
        $candidateWrapperPath,
        $candidateFullChainTbPath,
        $glbl
    ) `
    -Top 'tb_phase7_full_chain_bittrue' `
    -Snapshot 'tb_nf_full_final_sim' `
    -ExpectedPassText $fullChainPassText `
    -XvlogOptions $fullChainXvlogOptions `
    -XelabOptions @('glbl', '-L', 'unisims_ver') `
    -Assets (@($coeffHeader) + $vectorFiles)

$resetDir = Invoke-RtlCase -Name 'full_chain_reset_recovery' `
    -VerilogFiles @(
        (Join-Path $sourceRoot 'all2x_v6\round_sat_shift_compact.v'),
        (Join-Path $sourceRoot 'all2x_v3\interp2_stage1_strict_halfband_bram_ce.v'),
        (Join-Path $nfSource 'nf_stage1_history_ramb18_sdp.v'),
        (Join-Path $nfSource 'interp2_stage1_single_bram_serial_ce.v'),
        (Join-Path $sourceRoot 'all2x_v6\bridge_valid_quantized_to_interp2_ce.v'),
        (Join-Path $sourceRoot 'all2x_v5\round_sat_q15_compact_to24.v'),
        (Join-Path $v7Source 'interp2_stage23_folded_cic_dsp_ce.v'),
        (Join-Path $v7Source 'interp2_stage23_lutram_cic_dsp_ce.v'),
        (Join-Path $nfSource 'nf_unified_fir_coeff_bram.v'),
        (Join-Path $nfSource 'nf_stage23_history_ramb18_sdp.v'),
        (Join-Path $nfSource 'cic3_compensator_shiftadd_ce.v'),
        (Join-Path $v7Source 'cic_interp16_core_dsp_ce.v'),
        (Join-Path $nfSource 'cic_interp16_serial_comb_dsp_ce.v'),
        (Join-Path $nfSource 'cic_interp16_n3_hold2_dsp_ce.v'),
        (Join-Path $v7Source 'interp128_all2x_v7_folded_fir_cic_top_ce.v'),
        (Join-Path $v7Sim 'tb_phase7_full_chain_reset_recovery.v'),
        $glbl
    ) `
    -Top 'tb_phase7_full_chain_reset_recovery' `
    -Snapshot 'tb_nf_full_reset_sim' `
    -ExpectedPassText 'PHASE7 FULL RESET RECOVERY PASS: 8 internal-state scenarios clean.' `
    -XvlogOptions $signedOffFullChainXvlogOptions `
    -XelabOptions @('glbl', '-L', 'unisims_ver') `
    -Assets @($coeffHeader)

$dynamicXvlogOptions = @(
    '-d', 'PHASE7_USE_BRAM_STAGE23_HISTORY',
    '-d', 'PHASE7_USE_BRAM_STAGE23_COEFF'
)
if ($CicIntegratorDspMode -lt 2) {
    $dynamicXvlogOptions += @(
        '-d', "NF_CIC_INTEGRATOR_DSP_MODE_$CicIntegratorDspMode")
}

$dynamicDir = Invoke-RtlCase -Name 'dynamic_mode_switch' `
    -VerilogFiles @(
        (Join-Path $sourceRoot 'all2x_v6\round_sat_shift_compact.v'),
        (Join-Path $sourceRoot 'all2x_v3\interp2_stage1_strict_halfband_bram_ce.v'),
        (Join-Path $nfSource 'nf_stage1_history_ramb18_sdp.v'),
        (Join-Path $nfSource 'interp2_stage1_single_bram_serial_ce.v'),
        (Join-Path $sourceRoot 'all2x_v6\bridge_valid_quantized_to_interp2_ce.v'),
        (Join-Path $sourceRoot 'all2x_v5\round_sat_q15_compact_to24.v'),
        (Join-Path $v7Source 'interp2_stage23_folded_cic_dsp_ce.v'),
        (Join-Path $v7Source 'interp2_stage23_lutram_cic_dsp_ce.v'),
        (Join-Path $nfSource 'nf_unified_fir_coeff_bram.v'),
        (Join-Path $nfSource 'nf_stage23_history_ramb18_sdp.v'),
        (Join-Path $nfSource 'cic3_compensator_shiftadd_ce.v'),
        (Join-Path $v7Source 'cic_interp16_core_dsp_ce.v'),
        (Join-Path $nfSource 'cic_interp16_serial_comb_dsp_ce.v'),
        (Join-Path $nfSource 'cic_interp16_n3_hold2_dsp_ce.v'),
        (Join-Path $v7Source 'interp128_all2x_v7_folded_fir_cic_top_ce.v'),
        (Join-Path $nfSource 'dual_rate_test_tone_rom_source.v'),
        (Join-Path $sourceRoot 'demo_interp_dac8_audio_pcm_common.v'),
        (Join-Path $v7Sim 'tb_phase7_mode_switch_dynamic.v'),
        $glbl
    ) `
    -Top 'tb_phase7_mode_switch_dynamic' `
    -Snapshot 'tb_nf_dynamic_mode_sim' `
    -ExpectedPassText 'PHASE7 DYNAMIC MODE PASS: 10 switches, no reset, no runt pulse or X.' `
    -XvlogOptions $dynamicXvlogOptions `
    -XelabOptions @('glbl', '-L', 'unisims_ver') `
    -Assets @(
        $coeffHeader,
        (Join-Path $nfSource 'nf_sine_15k_dual_rate_24bit_256.mem')
    )

if ($PublishImpulseOutputs) {
    $publishDir = Join-Path $nfRoot 'rtl_outputs'
    New-Item -ItemType Directory -Path $publishDir -Force | Out-Null
    foreach ($name in @('rtl_impulse_y4.csv', 'rtl_impulse_y8.csv', 'rtl_impulse_y128.csv')) {
        Copy-Item -LiteralPath (Join-Path $fullDir $name) -Destination $publishDir -Force
    }
    Write-Host "Published impulse responses to: $publishDir"
}

Write-Host ''
Write-Host 'NATIONAL FINALS RTL REGRESSION PASS (15/15)'
Write-Host "CIC integrator DSP mode: $CicIntegratorDspMode"
Write-Host "Run directory: $runRoot"
