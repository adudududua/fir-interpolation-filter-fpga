$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$vivadoBin = "E:\app\Xilinx20252\2025.2\Vivado\bin"
$xvlog = Join-Path $vivadoBin "xvlog.bat"
$xelab = Join-Path $vivadoBin "xelab.bat"
$xsim = Join-Path $vivadoBin "xsim.bat"

if (-not (Test-Path -LiteralPath $xvlog)) {
    throw "未找到 Vivado 2025.2：$xvlog"
}

Push-Location $projectRoot
try {
    & $xvlog `
        network_capture/rtl/ethernet_crc32.v `
        network_capture/rtl/rgmii100_rx.v `
        network_capture/rtl/udp_ipv4_rx_parser.v `
        network_capture/rtl/dac24_upload_protocol_rx.v `
        network_capture/rtl/dac24_wave_upload_buffer.v `
        network_capture/rtl/udp_control_ack_tx.v `
        network_capture/sim/tb_dac24_upload_end_to_end.v
    if ($LASTEXITCODE -ne 0) { throw "xvlog 编译失败" }

    & $xelab tb_dac24_upload_end_to_end glbl `
        -L unisims_ver `
        -s tb_dac24_upload_end_to_end_sim `
        -debug typical
    if ($LASTEXITCODE -ne 0) { throw "xelab 展开失败" }

    & $xsim tb_dac24_upload_end_to_end_sim -runall
    if ($LASTEXITCODE -ne 0) { throw "xsim 仿真失败" }
}
finally {
    Pop-Location
}
