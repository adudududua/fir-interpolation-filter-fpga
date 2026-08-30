param(
    [string]$VivadoRoot = 'E:\app\Xilinx20252\2025.2\Vivado'
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = (Resolve-Path (Join-Path $scriptDir '..\..\..')).Path
$sourceRoot = Join-Path $projectDir 'XC7A35T_interp.srcs\sources_1\new'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$workDir = Join-Path (Split-Path -Parent $scriptDir) "_work\structure_redesign\rtl_equivalence_$stamp"
New-Item -ItemType Directory -Force -Path $workDir | Out-Null
Set-Location -LiteralPath $workDir

$xvlog = Join-Path $VivadoRoot 'bin\xvlog.bat'
$xelab = Join-Path $VivadoRoot 'bin\xelab.bat'
$xsim = Join-Path $VivadoRoot 'bin\xsim.bat'
$glbl = Join-Path $VivadoRoot 'data\verilog\src\glbl.v'
$candidateRoot = Join-Path $sourceRoot 'national_finals\experiments'

$sources = @(
    (Join-Path $sourceRoot 'all2x_v6\bridge_valid_quantized_to_interp2_ce.v'),
    (Join-Path $sourceRoot 'all2x_v6\round_sat_shift_compact.v'),
    (Join-Path $sourceRoot 'national_finals\interp2_stage1_single_bram_serial_ce.v'),
    (Join-Path $sourceRoot 'national_finals\nf_stage1_history_ramb18_sdp.v'),
    (Join-Path $sourceRoot 'national_finals\nf_stage23_history_ramb18_sdp.v'),
    (Join-Path $sourceRoot 'national_finals\nf_unified_fir_coeff_bram.v'),
    (Join-Path $sourceRoot 'all2x_v7\interp2_stage23_lutram_cic_dsp_ce.v'),
    (Join-Path $candidateRoot 'bridge_valid_raw_experiment_ce.v'),
    (Join-Path $candidateRoot 'interp2_stage23_fixed256_dsp_ce.v'),
    (Join-Path $candidateRoot 'interp2_stage23_fused_quant_dsp_ce.v'),
    (Join-Path $candidateRoot 'nf_global_fir_scheduler_256x_ce.v'),
    (Join-Path $scriptDir 'baseline_fir_front_direct_wrapper.v'),
    (Join-Path $scriptDir 'fixed256_stage23_front_ooc_wrapper.v'),
    (Join-Path $scriptDir 'fused_quant_fir_front_ooc_wrapper.v'),
    (Join-Path $scriptDir 'global_fir256_front_ooc_wrapper.v'),
    (Join-Path $scriptDir 'qfold256_stage23_front_ooc_wrapper.v'),
    (Join-Path $scriptDir 'tb_fixed256_stage23_front_equiv.v'),
    (Join-Path $scriptDir 'tb_fused_quant_fir_front_equiv.v'),
    (Join-Path $scriptDir 'tb_global_fir256_front_equiv.v'),
    (Join-Path $scriptDir 'tb_qfold256_stage23_front_equiv.v'),
    $glbl
)

& $xvlog --include (Join-Path $sourceRoot 'all2x_v2') @sources
if ($LASTEXITCODE -ne 0) { throw "xvlog failed: $LASTEXITCODE" }

$tests = @(
    'tb_fixed256_stage23_front_equiv',
    'tb_fused_quant_fir_front_equiv',
    'tb_global_fir256_front_equiv',
    'tb_qfold256_stage23_front_equiv'
)

foreach ($test in $tests) {
    $snapshot = "${test}_sim"
    & $xelab $test glbl -L unisims_ver -s $snapshot
    if ($LASTEXITCODE -ne 0) { throw "xelab failed for ${test}: $LASTEXITCODE" }
    & $xsim $snapshot -runall
    if ($LASTEXITCODE -ne 0) { throw "xsim failed for ${test}: $LASTEXITCODE" }
}

Write-Host "STRUCTURE_EXPERIMENT_RTL_EQUIVALENCE_PASS=$workDir"
