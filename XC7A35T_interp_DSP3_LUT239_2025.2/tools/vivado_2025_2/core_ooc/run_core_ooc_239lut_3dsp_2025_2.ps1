param(
    [string]$VivadoBat = '',

    [ValidateRange(1, 4)]
    [int]$Jobs = 1,

    [ValidateRange(1.0, 32.0)]
    [double]$MinimumCommitHeadroomGB = 3.0,

    [switch]$SkipMemoryGate
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$tclScript = Join-Path $scriptDir 'run_core_ooc_239lut_3dsp_2025_2.tcl'

if ([string]::IsNullOrWhiteSpace($VivadoBat)) {
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($env:XILINX_VIVADO)) {
        $candidates += (Join-Path $env:XILINX_VIVADO 'bin\vivado.bat')
    }
    $candidates += 'E:\app\Xilinx20252\2025.2\Vivado\bin\vivado.bat'
    $VivadoBat = $candidates |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
}

if ([string]::IsNullOrWhiteSpace($VivadoBat) -or
    -not (Test-Path -LiteralPath $VivadoBat)) {
    throw '未找到 Vivado 2025.2。请用 -VivadoBat 指定 vivado.bat 的完整路径。'
}

# 固定 Tcl App 搜索目录，避免用户 Tcl Store 缓存损坏影响批处理启动。
$vivadoBin = Split-Path -Parent $VivadoBat
$vivadoRoot = Split-Path -Parent $vivadoBin
$tclStore = Join-Path $vivadoRoot 'data\XilinxTclStore'
if (Test-Path -LiteralPath $tclStore) {
    $tclStorePath = $tclStore.Replace('\', '/')
    $env:XILINX_TCLAPP_REPO = $tclStorePath
    $env:TCLLIBPATH = $tclStorePath
}

# OOC 实现会占用较多提交内存。要求关闭 GUI，避免两个 Vivado 竞争内存。
$runningVivado = @(Get-Process -Name 'vivado' -ErrorAction SilentlyContinue)
if ($runningVivado.Count -gt 0) {
    $ids = ($runningVivado.Id | Sort-Object) -join ', '
    throw "请先关闭所有 Vivado 窗口。当前 Vivado PID：$ids"
}

if (-not $SkipMemoryGate) {
    $samples = Get-Counter '\Memory\Committed Bytes','\Memory\Commit Limit' |
        Select-Object -ExpandProperty CounterSamples
    $committed = ($samples |
        Where-Object {$_.Path -like '*committed bytes'}).CookedValue
    $limit = ($samples |
        Where-Object {$_.Path -like '*commit limit'}).CookedValue
    $headroomGB = ($limit - $committed) / 1GB
    Write-Host ('Windows 提交内存余量：{0:N2} GB' -f $headroomGB)
    if ($headroomGB -lt $MinimumCommitHeadroomGB) {
        throw ('提交内存余量仅 {0:N2} GB，至少需要 {1:N2} GB。' -f `
            $headroomGB, $MinimumCommitHeadroomGB)
    }
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$resultDir = Join-Path $scriptDir "results\$stamp"
New-Item -ItemType Directory -Force -Path $resultDir | Out-Null
$logPath = Join-Path $resultDir 'vivado_core_ooc.log'
$journalPath = Join-Path $resultDir 'vivado_core_ooc.jou'

Write-Host "Vivado：$VivadoBat"
Write-Host "核心 OOC 结果目录：$resultDir"

Push-Location $resultDir
try {
    & $VivadoBat -mode batch -notrace -log $logPath -journal $journalPath `
        -source $tclScript -tclargs $resultDir $Jobs
    if ($LASTEXITCODE -ne 0) {
        throw "核心 OOC 运行失败，退出码 $LASTEXITCODE。请查看：$logPath"
    }
}
finally {
    Pop-Location
}

$summaryPath = Join-Path $resultDir 'core_ooc_summary.txt'
if (-not (Test-Path -LiteralPath $summaryPath)) {
    throw "未生成核心 OOC 摘要：$summaryPath"
}

Write-Host ''
Get-Content -LiteralPath $summaryPath
Write-Host ''
Write-Host 'CORE_OOC_239LUT_3DSP_2025_2_DEMO_PASS'
Write-Host "资源报告：$(Join-Path $resultDir 'utilization_post_route.rpt')"

