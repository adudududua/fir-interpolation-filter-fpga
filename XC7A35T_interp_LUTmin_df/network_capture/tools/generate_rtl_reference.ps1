param(
    [ValidateSet(0, 1)] [int] $Family48k = 0,
    [ValidateRange(0, 3)] [int] $Mode = 3,
    [ValidateRange(0, 16777216)] [int] $SampleCount = 0
)

$ErrorActionPreference = 'Stop'
if ($SampleCount -eq 0) {
    # 采集引擎仅在 PHY 的 20 ms 复位和后续 30 ms 稳定等待结束后启动。
    # 因此 128x 模式需要更长的向量，才能覆盖首个板级帧的绝对分支索引。
    $SampleCount = if ($Mode -eq 3) { 524288 } else { 131072 }
}
if ($SampleCount -lt 4096) {
    throw 'SampleCount 必须为零（自动选择）或不小于 4096'
}
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$vivadoBin = 'E:\app\Xilinx2018.3\Vivado\2018.3\bin'
$results = Join-Path $projectRoot 'network_capture\results'
$sourceMem = Join-Path $projectRoot 'XC7A35T_interp.srcs\sources_1\new\national_finals\nf_sine_15k_dual_rate_packed32_256.mem'
$localMem = Join-Path $results 'nf_sine_15k_dual_rate_packed32_256.mem'
$referenceLibrary = 'dac24_ref_work'

Push-Location $projectRoot
try {
    $env:DAC24_XSIM_LIBRARY = $referenceLibrary
    & (Join-Path $PSScriptRoot 'make_xvlog_project.ps1') | Out-Null
    $familyDefine = if ($Family48k) { '--define REF_FAMILY_48K ' } else { '' }
    $modeDefine = @('--define REF_MODE_1X ', '--define REF_MODE_4X ',
                    '--define REF_MODE_8X ', '')[$Mode]
    $tbPath = (Join-Path $projectRoot 'network_capture\sim\tb_board_reference.v').Replace('\', '/')
    Add-Content -LiteralPath (Join-Path $results 'full_top.prj') -Encoding ascii -Value (
        'sv {0} --define REF_SAMPLE_COUNT={1} {2} "{3}"' -f `
            $referenceLibrary, $SampleCount,
            ($familyDefine + $modeDefine), $tbPath)
    Add-Content -LiteralPath (Join-Path $results 'full_top.prj') -Encoding ascii -Value (
        'sv {0} "{1}"' -f $referenceLibrary,
        (Join-Path $vivadoBin '..\data\verilog\src\glbl.v').Replace('\', '/'))
    Copy-Item -LiteralPath $sourceMem -Destination $localMem -Force

    Push-Location $results
    try {
        & (Join-Path $vivadoBin 'xvlog.bat') -prj (Join-Path $results 'full_top.prj') `
            --work $referenceLibrary
    }
    finally {
        Pop-Location
    }
    if ($LASTEXITCODE -ne 0) { throw "xvlog 执行失败，退出代码为 $LASTEXITCODE" }

    $snapshot = 'tb_board_reference_sim'
    Push-Location $results
    try {
        & (Join-Path $vivadoBin 'xelab.bat') "$referenceLibrary.tb_board_reference" `
            "$referenceLibrary.glbl" `
            -s $snapshot -L $referenceLibrary -L unisims_ver
    }
    finally {
        Pop-Location
    }
    if ($LASTEXITCODE -ne 0) { throw "xelab 执行失败，退出代码为 $LASTEXITCODE" }

    Push-Location $results
    try {
        & (Join-Path $vivadoBin 'xsim.bat') $snapshot -runall
    }
    finally {
        Pop-Location
    }
    if ($LASTEXITCODE -ne 0) { throw "xsim 执行失败，退出代码为 $LASTEXITCODE" }

    $familyName = if ($Family48k) { '48000' } else { '44100' }
    $modeName = @('1x', '4x', '8x', '128x')[$Mode]
    $destination = Join-Path $results "rtl_reference_${familyName}_${modeName}.txt"
    Move-Item -LiteralPath (Join-Path $results 'rtl_reference.txt') -Destination $destination -Force
    Write-Output $destination
}
finally {
    Remove-Item Env:DAC24_XSIM_LIBRARY -ErrorAction SilentlyContinue
    Pop-Location
}
