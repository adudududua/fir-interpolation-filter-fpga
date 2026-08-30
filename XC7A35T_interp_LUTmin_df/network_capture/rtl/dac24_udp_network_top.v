`timescale 1ns / 1ps

//=============================================================
// 文件名       : dac24_udp_network_top.v
// 模块名       : dac24_udp_network_top
// 功能简述     : 百兆网络测量子系统顶层。集成 RGMII RX/TX、ARP、IPv4/UDP 解析、DACU 上传双 Bank、DAC2 回传、ACK 异步 FIFO及三路整帧仲裁。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
module dac24_udp_network_top(
    input  wire               audio_clk,
    input  wire signed [23:0] monitor_sample,
    input  wire               monitor_valid,
    input  wire [31:0]        monitor_sample_index,
    input  wire [1:0]         monitor_mode,
    input  wire               monitor_family_48k,
    input  wire               net_clk_25m,
    input  wire               net_txc_clk_25m,
    input  wire               net_rst_n,
    input  wire               mac_rxc,
    input  wire               mac_rxctl,
    input  wire [3:0]         mac_rxd,
    output wire signed [23:0] upload_sample,
    output wire               upload_sample_update,
    output wire               upload_source_active,
    output wire               upload_pipeline_reset_pulse,
    output wire               upload_family_48k,
    output wire [1:0]         upload_mode,
    output wire [31:0]        upload_transaction_id,
    input  wire               input_sample_ce,
    output wire               mac_txc,
    output wire               mac_txctl,
    output wire [3:0]         mac_txd
);
    wire        capture_valid;
    wire [31:0] capture_frame_id;
    wire [31:0] capture_start_sample_index;
    wire [1:0]  capture_mode;
    wire        capture_family;
    wire        capture_upload_source;
    wire [31:0] capture_transaction_id;
    wire        capture_take;
    wire [13:0] capture_rd_addr;
    wire [23:0] capture_rd_data;
    wire [7:0]  tx_data;
    wire        tx_valid;
    wire        tx_ready;
    wire        tx_last_unused;
    wire [7:0]  audio_tx_data;
    wire        audio_tx_valid;
    wire        audio_tx_ready;
    wire        audio_tx_last;
    wire [7:0]  ack_tx_data;
    wire        ack_tx_valid;
    wire        ack_tx_ready;
    wire        ack_tx_last;
    wire [7:0]  arp_tx_data;
    wire        arp_tx_valid;
    wire        arp_tx_ready;
    wire        arp_tx_last;
    wire        ack_fifo_wr_ready;
    wire [8:0]  ack_fifo_rd_data;
    wire        ack_fifo_rd_valid;
    wire        ack_fifo_rd_ready;
    wire        arp_fifo_wr_ready;
    wire [8:0]  arp_fifo_rd_data;
    wire        arp_fifo_rd_valid;
    wire        arp_fifo_rd_ready;
    (* ASYNC_REG = "TRUE" *) reg [1:0] capture_rst_sync = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] rx_rst_sync = 2'b00;

    // RXC 由 PHY 输出，使用独立的异步断言/同步释放复位。
    always @(posedge mac_rxc or negedge net_rst_n) begin
        if (!net_rst_n)
            rx_rst_sync <= 2'b00;
        else
            rx_rst_sync <= {rx_rst_sync[0], 1'b1};
    end

    wire [7:0] rx_frame_data;
    wire rx_frame_data_valid, rx_frame_start, rx_frame_end, rx_frame_error;
    wire [7:0] rx_payload_data;
    wire rx_payload_valid, rx_payload_last, rx_packet_valid;
    wire [15:0] rx_payload_length;
    wire [31:0] rx_source_ip;
    wire [15:0] rx_source_port;

    rgmii100_rx u_rgmii_rx (
        .rx_clk(mac_rxc), .rst_n(rx_rst_sync[1]),
        .rgmii_rxd(mac_rxd), .rgmii_rxctl(mac_rxctl),
        .data(rx_frame_data), .data_valid(rx_frame_data_valid),
        .frame_start(rx_frame_start), .frame_end(rx_frame_end),
        .frame_error(rx_frame_error)
    );

    udp_ipv4_rx_parser u_udp_rx_parser (
        .clk(mac_rxc), .rst_n(rx_rst_sync[1]),
        .frame_data(rx_frame_data), .frame_data_valid(rx_frame_data_valid),
        .frame_start(rx_frame_start), .frame_end(rx_frame_end),
        .frame_error(rx_frame_error), .payload_data(rx_payload_data),
        .payload_valid(rx_payload_valid), .payload_last(rx_payload_last),
        .packet_valid(rx_packet_valid), .packet_drop(),
        .payload_length(rx_payload_length), .source_ip(rx_source_ip),
        .source_port(rx_source_port)
    );

    wire        arp_request_valid;
    wire        arp_request_ready;
    wire [47:0] arp_requester_mac;
    wire [31:0] arp_requester_ip;
    wire [7:0]  arp_rx_tx_data;
    wire        arp_rx_tx_valid;
    wire        arp_rx_tx_last;

    // PC 首次向 192.168.1.10 发送普通 UDP 前会先解析本机 MAC。ARP 请求
    // 与 UDP 解析器并行观察同一条、已校验前导码边界的 Ethernet 帧流。
    arp_request_rx u_arp_request_rx (
        .clk(mac_rxc), .rst_n(rx_rst_sync[1]),
        .frame_data(rx_frame_data), .frame_data_valid(rx_frame_data_valid),
        .frame_start(rx_frame_start), .frame_end(rx_frame_end),
        .frame_error(rx_frame_error),
        .request_valid(arp_request_valid), .request_ready(arp_request_ready),
        .requester_mac(arp_requester_mac), .requester_ip(arp_requester_ip)
    );

    arp_reply_tx u_arp_reply_tx_rx_domain (
        .clk(mac_rxc), .rst_n(rx_rst_sync[1]),
        .request_valid(arp_request_valid), .request_ready(arp_request_ready),
        .requester_mac(arp_requester_mac), .requester_ip(arp_requester_ip),
        .tx_data(arp_rx_tx_data), .tx_valid(arp_rx_tx_valid),
        .tx_ready(arp_fifo_wr_ready), .tx_last(arp_rx_tx_last)
    );

    // 和 ACK 一样，先在 RXC 域产生完整帧，再通过独立异步字节 FIFO
    // 送入 25 MHz TX 域。ARP 与 ACK 不会相互占用 FIFO 容量。
    ack_async_fifo #(.ADDR_W(8)) u_arp_async_fifo (
        .wr_clk(mac_rxc), .wr_rst_n(rx_rst_sync[1]),
        .wr_data({arp_rx_tx_last, arp_rx_tx_data}),
        .wr_valid(arp_rx_tx_valid), .wr_ready(arp_fifo_wr_ready),
        .rd_clk(net_clk_25m), .rd_rst_n(net_rst_n),
        .rd_data(arp_fifo_rd_data), .rd_valid(arp_fifo_rd_valid),
        .rd_ready(arp_fifo_rd_ready)
    );

    assign arp_tx_data  = arp_fifo_rd_data[7:0];
    assign arp_tx_valid = arp_fifo_rd_valid;
    assign arp_tx_last  = arp_fifo_rd_data[8];
    assign arp_fifo_rd_ready = arp_tx_ready;

    reg [31:0] protocol_source_ip;
    reg [15:0] protocol_source_port;
    always @(posedge mac_rxc) begin
        if (!rx_rst_sync[1]) begin
            protocol_source_ip <= 32'd0;
            protocol_source_port <= 16'd0;
        end else begin
            if (rx_packet_valid) begin
                protocol_source_ip <= rx_source_ip;
                protocol_source_port <= rx_source_port;
            end
        end
    end

    wire upload_header_valid, upload_packet_error;
    wire [7:0] upload_msg_type, upload_flags, upload_body_data;
    wire [31:0] upload_rx_transaction_id, upload_sequence;
    wire [31:0] upload_total_samples, upload_sample_offset;
    wire [15:0] upload_sample_count;
    wire upload_body_valid, upload_body_last;

    dac24_upload_protocol_rx u_upload_protocol (
        .clk(mac_rxc), .rst_n(rx_rst_sync[1]),
        .payload_data(rx_payload_data), .payload_valid(rx_payload_valid),
        .payload_last(rx_payload_last),
        .packet_start(rx_packet_valid),
        .packet_length(rx_payload_length),
        .header_valid(upload_header_valid), .packet_error(upload_packet_error),
        .msg_type(upload_msg_type), .flags(upload_flags),
        .transaction_id(upload_rx_transaction_id), .sequence(upload_sequence),
        .total_samples(upload_total_samples), .sample_offset(upload_sample_offset),
        .sample_count(upload_sample_count), .payload_crc32(),
        .body_data(upload_body_data), .body_valid(upload_body_valid),
        .body_last(upload_body_last)
    );

    wire upload_status_valid;
    wire [15:0] upload_status_code;
    wire [31:0] upload_status_transaction_id, upload_status_sequence;
    wire [31:0] upload_status_total_samples;
    wire [31:0] upload_next_offset;
    wire [31:0] upload_last_received_transaction_id;
    wire [31:0] upload_playback_length;
    wire capture_ready_audio;
    wire ack_event_ready;
    wire [7:0] ack_rx_tx_data;
    wire ack_rx_tx_valid, ack_rx_tx_last;

    dac24_wave_upload_buffer u_upload_buffer (
        .rx_clk(mac_rxc), .rx_rst_n(rx_rst_sync[1]),
        .header_valid(upload_header_valid), .packet_error(upload_packet_error),
        .msg_type(upload_msg_type), .flags(upload_flags),
        .transaction_id(upload_rx_transaction_id), .sequence(upload_sequence),
        .total_samples(upload_total_samples), .sample_offset(upload_sample_offset),
        .sample_count(upload_sample_count),
        .body_data(upload_body_data), .body_valid(upload_body_valid),
        .body_last(upload_body_last), .status_valid(upload_status_valid),
        .status_code(upload_status_code),
        .status_transaction_id(upload_status_transaction_id),
        .status_sequence(upload_status_sequence),
        .status_total_samples(upload_status_total_samples),
        .next_offset(upload_next_offset),
        .transaction_active(), .active_transaction_id(),
        .last_received_transaction_id(upload_last_received_transaction_id),
        .audio_clk(audio_clk), .audio_rst_n(capture_rst_sync[1]),
        .sample_ce(input_sample_ce), .capture_ready(capture_ready_audio),
        .current_family_48k(monitor_family_48k),
        .sample_out(upload_sample),
        .sample_update(upload_sample_update), .source_active(upload_source_active),
        .pipeline_reset_pulse(upload_pipeline_reset_pulse),
        .playback_family_48k(upload_family_48k), .playback_mode(upload_mode),
        .playback_length(upload_playback_length),
        .playback_transaction_id(upload_transaction_id)
    );

    // ACK 必须在 RXC 域生成事件并先完成整帧串行化；小型异步字节 FIFO
    // 随后把完整帧送入 25 MHz TX 域，避免直接跨时钟使用 ready/valid。
    udp_control_ack_tx u_ack_tx_rx_domain (
        .clk(mac_rxc), .rst_n(rx_rst_sync[1]),
        .event_valid(upload_status_valid), .event_ready(ack_event_ready),
        .status_code(upload_status_code),
        .transaction_id(upload_status_transaction_id),
        .sequence(upload_status_sequence),
        .total_samples(upload_status_total_samples),
        .next_offset(upload_next_offset),
        .dest_ip(protocol_source_ip), .dest_port(protocol_source_port),
        .tx_data(ack_rx_tx_data), .tx_valid(ack_rx_tx_valid),
        .tx_ready(ack_fifo_wr_ready), .tx_last(ack_rx_tx_last)
    );

    ack_async_fifo #(.ADDR_W(8)) u_ack_async_fifo (
        .wr_clk(mac_rxc), .wr_rst_n(rx_rst_sync[1]),
        .wr_data({ack_rx_tx_last, ack_rx_tx_data}),
        .wr_valid(ack_rx_tx_valid), .wr_ready(ack_fifo_wr_ready),
        .rd_clk(net_clk_25m), .rd_rst_n(net_rst_n),
        .rd_data(ack_fifo_rd_data), .rd_valid(ack_fifo_rd_valid),
        .rd_ready(ack_fifo_rd_ready)
    );

    assign ack_tx_data  = ack_fifo_rd_data[7:0];
    assign ack_tx_valid = ack_fifo_rd_valid;
    assign ack_tx_last  = ack_fifo_rd_data[8];
    assign ack_fifo_rd_ready = ack_tx_ready;

    // 网络启动复位独立于音频采样率族切换。插值数据通路静音或复位期间仍保留
    // 捕获状态，避免复位引发 done_toggle 跳变而产生伪数据帧。
    // 标准复位同步器：立即断言，经过两个音频时钟沿后同步释放，
    // 从而避免捕获逻辑在网络域复位信号亚稳释放时启动。
    always @(posedge audio_clk or negedge net_rst_n) begin
        if (!net_rst_n)
            capture_rst_sync <= 2'b00;
        else
            capture_rst_sync <= {capture_rst_sync[0], 1'b1};
    end

    // 只有上传波形的采样率族与板上当前物理时钟族一致时，才把数据帧
    // 标记为“上传源”；否则数据通路仍在使用板载 ROM。
    wire upload_source_effective = upload_source_active &&
                                   (upload_family_48k == monitor_family_48k);

    dac24_capture_pingpong u_capture (
        .audio_clk          (audio_clk),
        .audio_rst_n        (capture_rst_sync[1]),
        .sample_data        (monitor_sample),
        .sample_valid       (monitor_valid),
        .sample_index       (monitor_sample_index),
        .sample_mode        (monitor_mode),
        .sample_family_48k  (monitor_family_48k),
        .sample_upload_source(upload_source_effective),
        .sample_transaction_id(upload_source_effective ?
                               upload_transaction_id : 32'd0),
        .capture_restart    (upload_pipeline_reset_pulse),
        .net_clk            (net_clk_25m),
        .net_rst_n          (net_rst_n),
        .frame_take         (capture_take),
        .frame_valid        (capture_valid),
        .frame_id           (capture_frame_id),
        .frame_start_sample_index(capture_start_sample_index),
        .frame_mode         (capture_mode),
        .frame_family_48k   (capture_family),
        .frame_upload_source(capture_upload_source),
        .frame_transaction_id(capture_transaction_id),
        .capture_ready      (capture_ready_audio),
        .frame_rd_addr      (capture_rd_addr),
        .frame_rd_data      (capture_rd_data)
    );

    udp_audio_frame_tx u_udp_tx (
        .clk                 (net_clk_25m),
        .rst_n               (net_rst_n),
        .capture_valid       (capture_valid),
        .capture_frame_id    (capture_frame_id),
        .capture_start_sample_index(capture_start_sample_index),
        .capture_mode        (capture_mode),
        .capture_family_48k  (capture_family),
        .capture_upload_source(capture_upload_source),
        .capture_transaction_id(capture_transaction_id),
        .capture_take        (capture_take),
        .capture_rd_addr     (capture_rd_addr),
        .capture_rd_data     (capture_rd_data),
        .tx_data             (audio_tx_data),
        .tx_valid            (audio_tx_valid),
        .tx_ready            (audio_tx_ready),
        .tx_last             (audio_tx_last)
    );

    // 帧级固定优先级 ARP > 控制 ACK > 音频采集。仲裁只在帧边界切换，
    // 并在公共出口统一插入 100M Ethernet IFG。
    ethernet_frame_arbiter3 u_tx_arbiter (
        .clk(net_clk_25m), .rst_n(net_rst_n),
        .s0_data(arp_tx_data), .s0_valid(arp_tx_valid),
        .s0_ready(arp_tx_ready), .s0_last(arp_tx_last),
        .s1_data(ack_tx_data), .s1_valid(ack_tx_valid),
        .s1_ready(ack_tx_ready), .s1_last(ack_tx_last),
        .s2_data(audio_tx_data), .s2_valid(audio_tx_valid),
        .s2_ready(audio_tx_ready), .s2_last(audio_tx_last),
        .m_data(tx_data), .m_valid(tx_valid), .m_ready(tx_ready),
        .m_last(tx_last_unused)
    );

    rgmii100_tx u_rgmii_tx (
        .clk_25m    (net_clk_25m),
        .clk_txc_25m(net_txc_clk_25m),
        .rst_n      (net_rst_n),
        .s_data     (tx_data),
        .s_valid    (tx_valid),
        .s_ready    (tx_ready),
        .rgmii_txc  (mac_txc),
        .rgmii_txd  (mac_txd),
        .rgmii_txctl(mac_txctl)
    );
endmodule
