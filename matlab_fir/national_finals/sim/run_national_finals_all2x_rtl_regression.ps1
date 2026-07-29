[CmdletBinding()]
param(
    [string]$VivadoBin = 'E:\app\Xilinx2018.3\Vivado\2018.3\bin'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$projectSrc = Join-Path $repoRoot `
    'XC7A35T_interp_audio_pcm_wordlen_opt\XC7A35T_interp.srcs'
$sourceRoot = Join-Path $projectSrc 'sources_1\new'
$simRoot = Join-Path $projectSrc 'sim_1\new'
$nfRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$goldenRoot = Join-Path $repoRoot 'matlab_fir\alt_all2x_v6\mixed_width_golden'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$runRoot = Join-Path $nfRoot "_work\all2x_rtl_regression\$timestamp"

$xvlog = Join-Path $VivadoBin 'xvlog.bat'
$xelab = Join-Path $VivadoBin 'xelab.bat'
$xsim = Join-Path $VivadoBin 'xsim.bat'
$glbl = Join-Path (Split-Path $VivadoBin -Parent) 'data\verilog\src\glbl.v'

foreach ($requiredFile in @($xvlog, $xelab, $xsim, $glbl)) {
    if (-not (Test-Path -LiteralPath $requiredFile)) {
        throw "Required simulator file not found: $requiredFile"
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
        $output = & $Executable @Arguments 2>&1
        foreach ($line in $output) { Write-Host $line }
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
        [Parameter(Mandatory = $true)][string]$ExpectedPassText,
        [string[]]$Defines = @(),
        [string[]]$Assets = @()
    )
    $caseDir = Join-Path $runRoot $Name
    New-Item -ItemType Directory -Path $caseDir -Force | Out-Null
    foreach ($asset in $Assets) {
        Copy-Item -LiteralPath $asset -Destination $caseDir -Force
    }

    $defineArgs = foreach ($define in $Defines) { '-d'; $define }
    $snapshot = "tb_nf_all2x_${Name}_sim"
    Write-Host "[$Name] compile"
    Invoke-CheckedTool $caseDir $xvlog ($defineArgs + $VerilogFiles)
    Write-Host "[$Name] elaborate"
    Invoke-CheckedTool $caseDir $xelab @($Top, 'glbl', '-L', 'unisims_ver',
        '-s', $snapshot)
    Write-Host "[$Name] simulate"
    Invoke-CheckedTool $caseDir $xsim @($snapshot, '-runall')

    $logPath = Join-Path $caseDir 'xsim.log'
    $logText = Get-Content -LiteralPath $logPath -Raw
    if (-not $logText.Contains($ExpectedPassText)) {
        throw "[$Name] expected PASS marker not found: $ExpectedPassText"
    }
    if ($logText -match '(?im)^\s*(FAIL|FATAL|ERROR)\b') {
        throw "[$Name] failure text found in xsim.log"
    }
    Write-Host "[$Name] PASS"
}

$v2Source = Join-Path $sourceRoot 'all2x_v2'
$v3Source = Join-Path $sourceRoot 'all2x_v3'
$v6Source = Join-Path $sourceRoot 'all2x_v6'
$v7Source = Join-Path $sourceRoot 'all2x_v7'
$nfSource = Join-Path $sourceRoot 'national_finals'
$v6Sim = Join-Path $simRoot 'all2x_v6'
$v7Sim = Join-Path $simRoot 'all2x_v7\verification'
$nfSim = Join-Path $simRoot 'national_finals'

$commonSources = @(
    (Join-Path $sourceRoot 'round_sat_q16_to24.v'),
    (Join-Path $sourceRoot 'fir_core_symm_interp2_all2x.v'),
    (Join-Path $sourceRoot 'interp2_top_symm_ce_all2x.v'),
    (Join-Path $v6Source 'round_sat_shift_compact.v'),
    (Join-Path $v3Source 'interp2_stage1_strict_halfband_bram_ce.v'),
    (Join-Path $v6Source 'bridge_valid_quantized_to_interp2_ce.v'),
    (Join-Path $v2Source 'bridge_valid_only_to_interp2_ce.v'),
    (Join-Path $v2Source 'interp2_halfband7_shiftadd_ce.v'),
    (Join-Path $v2Source 'interp2_all2x_v2_stage_select.v'),
    (Join-Path $v7Source 'interp2_stage23_lutram_cic_dsp_ce.v'),
    (Join-Path $nfSource 'bridge_valid_quantized_buffered_ce.v'),
    (Join-Path $nfSource 'interp2_halfband7_shared4_ce.v'),
    (Join-Path $nfSource 'interp128_all2x_nf_optimized_top_ce.v')
)
$coeffHeader = Join-Path $v2Source 'all2x_v2_coeff_pkg.vh'
$goldenFiles = Get-ChildItem -LiteralPath $goldenRoot -Filter '*.mem' |
    ForEach-Object { $_.FullName }

Invoke-RtlCase -Name 'bittrue' `
    -VerilogFiles ($commonSources + @(
        (Join-Path $v6Sim 'tb_phase6_mixed_width_bittrue.v'), $glbl
    )) `
    -Top 'tb_phase6_mixed_width_bittrue' `
    -Defines @('NATIONAL_FINALS_ALL2X') `
    -Assets (@($coeffHeader) + $goldenFiles) `
    -ExpectedPassText `
        'NATIONAL FINALS ALL2X BITTRUE PASS: impulse/random, all nodes 0 LSB.'

Invoke-RtlCase -Name 'tail_equivalence' `
    -VerilogFiles ($commonSources + @(
        (Join-Path $nfSim 'tb_all2x_shared_tail_equiv.v'), $glbl
    )) `
    -Top 'tb_all2x_shared_tail_equiv' `
    -Assets @($coeffHeader) `
    -ExpectedPassText 'ALL2X SHARED TAIL EQUIVALENCE PASS'

Invoke-RtlCase -Name 'reset_recovery' `
    -VerilogFiles ($commonSources + @(
        (Join-Path $v7Sim 'tb_phase7_full_chain_reset_recovery.v'), $glbl
    )) `
    -Top 'tb_phase7_full_chain_reset_recovery' `
    -Defines @('NATIONAL_FINALS_ALL2X') `
    -Assets @($coeffHeader) `
    -ExpectedPassText `
        'NATIONAL FINALS ALL2X RESET RECOVERY PASS: 8 internal-state scenarios clean.'

Invoke-RtlCase -Name 'dynamic_mode_switch' `
    -VerilogFiles ($commonSources + @(
        (Join-Path $nfSource 'dual_rate_test_tone_rom_source.v'),
        (Join-Path $sourceRoot 'demo_interp_dac8_audio_pcm_common.v'),
        (Join-Path $v7Sim 'tb_phase7_mode_switch_dynamic.v'), $glbl
    )) `
    -Top 'tb_phase7_mode_switch_dynamic' `
    -Defines @('NATIONAL_FINALS_ALL2X') `
    -Assets @(
        $coeffHeader,
        (Join-Path $nfSource 'nf_sine_15k_dual_rate_24bit_256.mem')
    ) `
    -ExpectedPassText `
        'PHASE7 DYNAMIC MODE PASS: 10 switches, no reset, no runt pulse or X.'

Write-Host ''
Write-Host 'NATIONAL FINALS ALL2X RTL REGRESSION PASS (4/4)'
Write-Host "Run directory: $runRoot"
