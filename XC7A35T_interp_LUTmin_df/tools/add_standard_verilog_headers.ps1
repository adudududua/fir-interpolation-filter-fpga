param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

# 本表只列出本次从板级验证工程带入、尚未采用统一文件头的源码。
# 已由核心精简工程继承的 Verilog 文件保持原有详细中文文件头不变。
$headers = [ordered]@{
    'XC7A35T_interp.srcs/sources_1/new/board_demo_competition_dac8_top.v' = @(
        'board_demo_competition_dac8_top',
        'XC7A35T 全国总决赛完整板级验证顶层。集成双采样率四倍率插值链、AD9708 接口、矩阵按键、固定 100BASE-TX RGMII、ARP、UDP 波形上传与 DAC 前 24 位数字节点回传。'
    )
    'XC7A35T_interp.srcs/sources_1/new/demo_interp_dac8_audio_pcm_common.v' = @(
        'demo_interp_dac8_audio_pcm_common',
        '板级音频数据通路公共模块。完成 ROM/UDP 上传源选择、44.1/48 kHz 家族复位切换、1x/4x/8x/128x 节点选择、24 位监测索引生成以及 AD9708 前的定点截位。'
    )
    'XC7A35T_interp.srcs/sim_1/new/all2x_v7/verification/tb_phase7_mode_switch_dynamic.v' = @(
        'tb_phase7_mode_switch_dynamic',
        'Phase 7 四倍率动态切换测试平台。验证 1x/4x/8x/128x 模式提交、DAC 时钟完整脉宽、数据有效性与无未知态，并覆盖不同 CIC DSP 映射配置。'
    )
    'network_capture/rtl/ack_async_fifo.v' = @(
        'ack_async_fifo',
        'ARP/ACK 以太网字节流跨时钟异步 FIFO。采用 Gray 指针同步、写满/读空保护和读域预取寄存，保证反压期间输出数据稳定。'
    )
    'network_capture/rtl/arp_reply_tx.v' = @(
        'arp_reply_tx',
        'ARP 应答帧发送器。根据合法请求构造单播 ARP Reply，补齐最小以太网帧并生成 IEEE CRC32/FCS。'
    )
    'network_capture/rtl/arp_request_rx.v' = @(
        'arp_request_rx',
        'ARP 请求接收与校验模块。核对目标 MAC/IP、ARP 字段和 Ethernet FCS，并向应答通道提交来源地址描述符。'
    )
    'network_capture/rtl/dac24_capture_pingpong.v' = @(
        'dac24_capture_pingpong / capture_sdp_bram',
        'DAC 截位前 24 位节点采集模块。使用 16384×24 位简单双口双时钟 BRAM、toggle 握手和稳定描述符，支持 COMMIT 时确定性重启到输出索引 0。'
    )
    'network_capture/rtl/dac24_udp_network_top.v' = @(
        'dac24_udp_network_top',
        '百兆网络测量子系统顶层。集成 RGMII RX/TX、ARP、IPv4/UDP 解析、DACU 上传双 Bank、DAC2 回传、ACK 异步 FIFO及三路整帧仲裁。'
    )
    'network_capture/rtl/dac24_upload_protocol_rx.v' = @(
        'dac24_upload_protocol_rx',
        'DACU 应用层协议解析器。解析 32 字节小端头、CONTROL/WAVE/COMMIT 正文及 payload CRC32，向上传事务控制器输出结构化字段。'
    )
    'network_capture/rtl/dac24_wave_upload_buffer.v' = @(
        'dac24_wave_upload_buffer',
        'PC 任意 24 位 1x 波形上传与播放控制器。管理两组 16384×24 位 Bank、连续 offset/sequence、幂等重传、COMMIT 原子换 Bank 和 RXCLK→audio CDC。'
    )
    'network_capture/rtl/ethernet_crc32.v' = @(
        'ethernet_crc32',
        '以太网 IEEE 802.3 反射式 CRC32 单字节更新函数模块，为接收 FCS 校验和发送 FCS 生成提供统一算法。'
    )
    'network_capture/rtl/ethernet_frame_arbiter2.v' = @(
        'ethernet_frame_arbiter2',
        '两路以太网帧仲裁器。仅在帧边界选择高优先级输入，选中后锁定至 last，防止不同来源的帧字节交叉。'
    )
    'network_capture/rtl/ethernet_frame_arbiter3.v' = @(
        'ethernet_frame_arbiter3',
        'ARP、控制 ACK 与音频回传三路整帧仲裁器。固定优先级 ARP>ACK>音频，并在相邻帧之间强制合法 IFG。'
    )
    'network_capture/rtl/rgmii100_rx.v' = @(
        'rgmii100_rx',
        '固定 100 Mb/s RGMII 接收适配器。以 RXCLK 下降沿 IOB 寄存器在数据眼中心采样半字节，搜索 7×55+D5 并输出去前导的字节帧。'
    )
    'network_capture/rtl/rgmii100_tx.v' = @(
        'rgmii100_tx',
        '固定 100 Mb/s RGMII 发送适配器。每个 25 MHz 周期发送一个半字节，ODDR 两沿重复同一 nibble，一个字节严格占两个周期。'
    )
    'network_capture/rtl/udp_audio_frame_tx.v' = @(
        'udp_audio_frame_tx',
        'DAC2 数字样本回传帧生成器。把 16384 个 s24LE 样本分成 64 个 UDP4000 广播包，填写模式、采样率、输出索引、来源和事务 ID，并生成 IPv4 校验和与 FCS。'
    )
    'network_capture/rtl/udp_control_ack_tx.v' = @(
        'udp_control_ack_tx',
        'UDP4001 控制 ACK 发送器。回显 transaction/sequence/total/next_offset/status，构造完整 Ethernet/IPv4/UDP/DACU ACK 帧。'
    )
    'network_capture/rtl/udp_ipv4_rx_parser.v' = @(
        'udp_ipv4_rx_parser',
        '精简 Ethernet/IPv4/UDP 接收解析器。验证目的地址、EtherType、IPv4 头校验和、长度、分片条件和 FCS，并用双 1 KiB Bank 后验回放 UDP payload。'
    )
    'network_capture/sim/tb_ack_async_fifo.v' = @('tb_ack_async_fifo', '异步 FIFO 反压与回卷测试平台。验证长突发、停顿期间数据稳定、跨多次指针回卷后的严格字节顺序。')
    'network_capture/sim/tb_arp_request_reply.v' = @('tb_arp_request_reply', 'ARP 请求解析与应答生成单元测试。覆盖合法请求、字段错误、FCS 错误及回复帧内容/FCS。')
    'network_capture/sim/tb_arp_rgmii_loop.v' = @('tb_arp_rgmii_loop', '真实 100M RGMII 半字节输入到 ARP 回复字节流的链路测试，覆盖前导码、SFD、FCS 与请求/应答地址闭环。')
    'network_capture/sim/tb_board_reference.v' = @('tb_board_reference', '板级公共数据通路参考向量生成测试。按真实发布参数输出模式/采样率对应的连续 24 位监测样本与绝对索引。')
    'network_capture/sim/tb_capture_pingpong.v' = @('tb_capture_pingpong', '16384 点采集 BRAM 与 CDC 握手测试。验证帧描述符、读序、ACK 释放以及 COMMIT restart 后上传帧从索引 0 开始。')
    'network_capture/sim/tb_dac24_upload_end_to_end.v' = @('tb_dac24_upload_end_to_end', 'DACU 协议解析、上传双 Bank、COMMIT、ACK 与音频播放的模块级端到端测试，逐点核对 s24LE 样本。')
    'network_capture/sim/tb_dac24_upload_protocol_rx.v' = @('tb_dac24_upload_protocol_rx', 'DACU 32 字节头与正文解析测试。覆盖 WAVE、CONTROL、COMMIT、CRC 错误及长度错误。')
    'network_capture/sim/tb_dac24_wave_upload_buffer.v' = @('tb_dac24_wave_upload_buffer', '上传事务与双 Bank 控制测试。覆盖顺序、offset、重传、family 门禁、capture_ready、循环/单次播放及提交复位。')
    'network_capture/sim/tb_ethernet_frame_arbiter2.v' = @('tb_ethernet_frame_arbiter2', '两路帧仲裁器测试。验证高优先级选择、帧内锁定和下游反压。')
    'network_capture/sim/tb_ethernet_frame_arbiter3.v' = @('tb_ethernet_frame_arbiter3', '三路帧仲裁与 IFG 测试。验证 ARP>ACK>音频优先级、帧不被打断以及帧间隔。')
    'network_capture/sim/tb_keypad_mode_chain.v' = @('tb_keypad_mode_chain', '矩阵按键到板级模式提交链测试。覆盖 SW1～SW8 消抖、44.1/48 kHz 家族选择及 1x/4x/8x/128x 模式切换。')
    'network_capture/sim/tb_network_upload_end_to_end.v' = @('tb_network_upload_end_to_end', '完整网络链路测试。由真实 RGMII 前导开始，覆盖 ARP、UDP4001、DACU 重传、COMMIT、ACK、上传播放与 16384 点索引 0 回传。')
    'network_capture/sim/tb_rgmii100_rx.v' = @('tb_rgmii100_rx', '100M RGMII 接收测试。验证下降沿取样、前导/SFD 搜索、错误前导重同步、字节拼接及奇数半字节截断。')
    'network_capture/sim/tb_rgmii100_tx.v' = @('tb_rgmii100_tx', '100M RGMII 发送测试。验证低/高半字节各保持完整周期、ODDR 双沿重复和 ready 节流。')
    'network_capture/sim/tb_udp_audio_frame_tx.v' = @('tb_udp_audio_frame_tx', 'DAC2 回传帧测试。生成 64 个包并核对应用头、16384 点顺序、IPv4 校验和、FCS、ACK 后不重复发送。')
    'network_capture/sim/tb_udp_control_ack_tx.v' = @('tb_udp_control_ack_tx', '控制 ACK 帧测试。核对事务字段、动态目标 IP/端口、IPv4 校验和、反压及 Ethernet FCS。')
    'network_capture/sim/tb_udp_ipv4_rx_parser.v' = @('tb_udp_ipv4_rx_parser', 'Ethernet/IPv4/UDP parser 测试。覆盖连续合法帧、端口错误、IPv4 校验错误、截断、FCS 错误及末字节同拍结束。')
}

$separator = '//============================================================='
$updated = 0
foreach ($entry in $headers.GetEnumerator()) {
    $relative = $entry.Key.Replace('/', [IO.Path]::DirectorySeparatorChar)
    $path = Join-Path $ProjectRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "缺少待处理 Verilog 文件：$path"
    }

    $text = [IO.File]::ReadAllText($path)
    $timescaleMatch = [regex]::Match($text, '\A`timescale[^\r\n]*(?:\r?\n)')
    if (-not $timescaleMatch.Success) {
        throw "文件首行没有 timescale：$path"
    }
    $timescale = $timescaleMatch.Value.TrimEnd("`r", "`n")
    $body = $text.Substring($timescaleMatch.Length)

    # 删除旧式统一文件头；普通协议注释和代码内章节注释全部保留。
    $body = [regex]::Replace(
        $body,
        '(?s)\A\s*//={20,}\r?\n.*?//={20,}\r?\n\s*',
        ''
    )
    # 少数测试文件在宏定义后放置旧文件头，把它移到真正文件首部。
    $body = [regex]::Replace(
        $body,
        '(?s)(\A(?:\s*`(?:ifdef|elsif|else|endif|define)[^\r\n]*\r?\n)+\s*)//={20,}\r?\n.*?//={20,}\r?\n\s*',
        '$1'
    )

    $moduleName = $entry.Value[0]
    $summary = $entry.Value[1]
    $fileName = [IO.Path]::GetFileName($path)
    $header = @(
        $timescale,
        '',
        $separator,
        "// 文件名       : $fileName",
        "// 模块名       : $moduleName",
        "// 功能简述     : $summary",
        '//',
        '// 设计作者     : kafeizizi',
        '// 整理日期     : 2026-08-16',
        '// 版本         : V2025.2',
        '// 开发工具     : Vivado 2025.2',
        '// 修订记录     :',
        '//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，',
        '//                            补充模块职责、协议边界和验证目的说明。',
        $separator,
        ''
    ) -join "`r`n"
    [IO.File]::WriteAllText($path, $header + $body.TrimStart("`r", "`n"), $utf8NoBom)
    $updated++
}

Write-Host "STANDARD_VERILOG_HEADERS_UPDATED=$updated"
