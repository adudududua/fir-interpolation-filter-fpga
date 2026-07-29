[CmdletBinding()]
param(
    [string]$VivadoBin = 'E:\app\Xilinx2018.3\Vivado\2018.3\bin',
    [switch]$PublishImpulseOutputs
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$projectRoot = Join-Path $repoRoot 'XC7A35T_interp_audio_pcm_wordlen_opt\XC7A35T_interp.srcs'
$sourceRoot = Join-Path $projectRoot 'sources_1\new'
$simRoot = Join-Path $projectRoot 'sim_1\new'
$nfRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
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
$v7Source = Join-Path $sourceRoot 'all2x_v7'
$v7Sim = Join-Path $simRoot 'all2x_v7\verification'

$romDir = Invoke-RtlCase -Name 'rom' `
    -VerilogFiles @(
        (Join-Path $nfSource 'dual_rate_test_tone_rom_source.v'),
        (Join-Path $nfSim 'tb_dual_rate_test_tone_rom_source.v')
    ) `
    -Top 'tb_dual_rate_test_tone_rom_source' `
    -Snapshot 'tb_nf_rom_sim' `
    -ExpectedPassText 'PASS: dual-rate ROM data, wrap, and synchronous family reset' `
    -Assets @((Join-Path $nfSource 'nf_sine_15k_dual_rate_24bit_256.mem'))

$equalizerDir = Invoke-RtlCase -Name 'equalizer' `
    -VerilogFiles @(
        (Join-Path $nfSource 'cic3_compensator_shiftadd_ce.v'),
        (Join-Path $nfSim 'tb_cic3_compensator_shiftadd_ce.v')
    ) `
    -Top 'tb_cic3_compensator_shiftadd_ce' `
    -Snapshot 'tb_nf_equalizer_sim' `
    -ExpectedPassText 'NF CIC3 SHIFTADD COMPENSATOR PASS samples=2009'

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

$keypadDir = Invoke-RtlCase -Name 'keypad' `
    -VerilogFiles @(
        (Join-Path $sourceRoot 'board_demo_competition_dac8_top.v'),
        (Join-Path $sourceRoot 'matrix_keypad_mode_ctrl_compact.v'),
        (Join-Path $v7Sim 'tb_matrix_keypad_mode_ctrl_compact.v')
    ) `
    -Top 'tb_matrix_keypad_mode_ctrl_compact' `
    -Snapshot 'tb_nf_keypad_sim' `
    -ExpectedPassText 'PASS: compact keypad matches SW1-SW8 family/mode behavior'

$boardDir = Invoke-RtlCase -Name 'board' `
    -VerilogFiles @(
        (Join-Path $sourceRoot 'board_demo_competition_dac8_top.v'),
        (Join-Path $sourceRoot 'matrix_keypad_mode_ctrl_compact.v'),
        (Join-Path $v7Sim 'tb_board_phase7_shared_keypad_scan.v')
    ) `
    -Top 'tb_board_phase7_shared_keypad_scan' `
    -Snapshot 'tb_nf_board_sim' `
    -ExpectedPassText 'NATIONAL FINALS BOARD INTEGRATION PASS'

$vectorFiles = Get-ChildItem -LiteralPath (Join-Path $nfRoot 'vectors\daily') -Filter '*.mem' |
    ForEach-Object { $_.FullName }
$coeffHeader = Join-Path $sourceRoot 'all2x_v2\all2x_v2_coeff_pkg.vh'
$fullDir = Invoke-RtlCase -Name 'full_chain_bittrue' `
    -VerilogFiles @(
        (Join-Path $sourceRoot 'all2x_v6\round_sat_shift_compact.v'),
        (Join-Path $sourceRoot 'all2x_v3\interp2_stage1_strict_halfband_bram_ce.v'),
        (Join-Path $sourceRoot 'all2x_v6\bridge_valid_quantized_to_interp2_ce.v'),
        (Join-Path $sourceRoot 'all2x_v5\round_sat_q15_compact_to24.v'),
        (Join-Path $v7Source 'interp2_stage23_folded_cic_dsp_ce.v'),
        (Join-Path $v7Source 'interp2_stage23_lutram_cic_dsp_ce.v'),
        (Join-Path $nfSource 'cic3_compensator_shiftadd_ce.v'),
        (Join-Path $v7Source 'cic_interp16_core_dsp_ce.v'),
        (Join-Path $v7Source 'interp128_all2x_v7_folded_fir_cic_top_ce.v'),
        (Join-Path $v7Sim 'tb_phase7_full_chain_bittrue.v'),
        $glbl
    ) `
    -Top 'tb_phase7_full_chain_bittrue' `
    -Snapshot 'tb_nf_full_final_sim' `
    -ExpectedPassText 'PHASE7 FULL CHAIN BITTRUE PASS: impulse + 1 seeds, all nodes 0 LSB.' `
    -XvlogOptions @(
        '-d', 'NATIONAL_FINALS',
        '-d', 'PHASE7_USE_LUTRAM_STAGE23',
        '-d', 'PHASE7_USE_BRAM_STAGE23_HISTORY',
        '-d', 'PHASE7_USE_BRAM_STAGE23_COEFF'
    ) `
    -XelabOptions @('glbl', '-L', 'unisims_ver') `
    -Assets (@($coeffHeader) + $vectorFiles)

if ($PublishImpulseOutputs) {
    $publishDir = Join-Path $nfRoot 'rtl_outputs'
    New-Item -ItemType Directory -Path $publishDir -Force | Out-Null
    foreach ($name in @('rtl_impulse_y4.csv', 'rtl_impulse_y8.csv', 'rtl_impulse_y128.csv')) {
        Copy-Item -LiteralPath (Join-Path $fullDir $name) -Destination $publishDir -Force
    }
    Write-Host "Published impulse responses to: $publishDir"
}

Write-Host ''
Write-Host 'NATIONAL FINALS RTL REGRESSION PASS (6/6)'
Write-Host "Run directory: $runRoot"
