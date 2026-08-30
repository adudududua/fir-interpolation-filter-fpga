`timescale 1ns / 1ps

//=============================================================
// 文件名       : udp_audio_frame_tx.v
// 模块名       : udp_audio_frame_tx
// 功能简述     : DAC2 数字样本回传帧生成器。把 16384 个 s24LE 样本分成 64 个 UDP4000 广播包，填写模式、采样率、输出索引、来源和事务 ID，并生成 IPv4 校验和与 FCS。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
// 将一次 16384 样本捕获拆分为 64 个广播 UDP 数据报发送。每个数据报包含
// 32 字节应用层头，随后是 256 个有符号 24 位小端样本（UDP 载荷共 800 字节，
// 安全低于以太网 MTU）。
module udp_audio_frame_tx #(
    parameter [47:0] SRC_MAC      = 48'h02_35_24_00_00_01,
    parameter [31:0] SRC_IP       = 32'hC0A8010A,
    parameter [15:0] UDP_PORT     = 16'd4000,
    parameter integer FRAME_GAP_CYCLES = 250000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        capture_valid,
    input  wire [31:0] capture_frame_id,
    input  wire [31:0] capture_start_sample_index,
    input  wire [1:0]  capture_mode,
    input  wire        capture_family_48k,
    input  wire        capture_upload_source,
    input  wire [31:0] capture_transaction_id,
    output reg         capture_take,
    output reg  [13:0] capture_rd_addr,
    input  wire [23:0] capture_rd_data,
    output reg  [7:0]  tx_data,
    output reg         tx_valid,
    input  wire        tx_ready,
    output reg         tx_last
);
    localparam integer SAMPLES_PER_PACKET = 256;
    localparam integer PACKET_COUNT       = 64;
    localparam integer APP_HEADER_BYTES   = 32;
    localparam integer APP_PAYLOAD_BYTES  = APP_HEADER_BYTES + 3*SAMPLES_PER_PACKET;
    localparam integer UDP_LENGTH         = 8 + APP_PAYLOAD_BYTES;
    localparam integer IP_TOTAL_LENGTH    = 20 + UDP_LENGTH;
    localparam integer ETH_BODY_BYTES     = 14 + IP_TOTAL_LENGTH;
    localparam integer FRAME_NO_FCS_BYTES = 8 + ETH_BODY_BYTES;

    localparam [2:0] ST_IDLE  = 3'd0;
    localparam [2:0] ST_PRIME = 3'd1;
    localparam [2:0] ST_SEND  = 3'd2;
    localparam [2:0] ST_FCS   = 3'd3;
    localparam [2:0] ST_GAP   = 3'd4;
    localparam [2:0] ST_ACK   = 3'd5;

    reg [2:0]  state;
    reg [10:0] byte_index;
    reg [5:0]  packet_index;
    reg [31:0] crc_reg;
    reg [31:0] fcs_word;
    reg [1:0]  fcs_index;
    reg [18:0] gap_count;
    reg [31:0] frame_id_latched;
    reg [31:0] start_sample_index_latched;
    reg [1:0]  mode_latched;
    reg        family_latched;
    reg        upload_source_latched;
    reg [31:0] transaction_id_latched;
    reg [23:0] sample_latched;

    wire [10:0] eth_index = byte_index - 11'd8;
    wire [10:0] ip_index  = eth_index - 11'd14;
    wire [10:0] udp_index = ip_index - 11'd20;
    wire [10:0] app_index = udp_index - 11'd8;
    wire [9:0]  sample_byte_offset = app_index - APP_HEADER_BYTES;
    wire [1:0]  sample_byte_lane = sample_byte_offset % 3;
    wire [7:0]  packet_payload_byte;
    wire [7:0]  frame_byte;
    wire [31:0] crc_next;

    function [7:0] mac_byte;
        input [47:0] mac;
        input [2:0]  idx;
        begin mac_byte = mac[47 - idx*8 -: 8]; end
    endfunction

    function [7:0] u32_le;
        input [31:0] value;
        input [1:0] idx;
        begin
            case (idx)
                2'd0: u32_le = value[7:0];
                2'd1: u32_le = value[15:8];
                2'd2: u32_le = value[23:16];
                default: u32_le = value[31:24];
            endcase
        end
    endfunction

    // 根据固定头字段和参数化源地址计算 IPv4 头校验和。保持为展开期常量，
    // 可避免日后覆盖 SRC_IP 后悄然沿用失效的旧校验和。
    function [15:0] ipv4_header_checksum;
        input [31:0] source_ip;
        reg [31:0] sum;
        begin
            sum = 32'h0000_4500 + IP_TOTAL_LENGTH + 32'h0000_4000
                + 32'h0000_4011 + source_ip[31:16] + source_ip[15:0]
                + 32'h0000_FFFF + 32'h0000_FFFF;
            sum = {16'd0, sum[15:0]} + sum[31:16];
            sum = {16'd0, sum[15:0]} + sum[31:16];
            ipv4_header_checksum = ~sum[15:0];
        end
    endfunction

    localparam [15:0] IP_CHECKSUM = ipv4_header_checksum(SRC_IP);

    assign packet_payload_byte =
        (sample_byte_lane == 2'd0) ? capture_rd_data[7:0] :
        (sample_byte_lane == 2'd1) ? sample_latched[15:8] :
                                        sample_latched[23:16];

    // 字节多路选择覆盖前导码/SFD、Ethernet II、IPv4、UDP 和应用数据。
    // UDP 校验和置零（IPv4 允许）；状态机在最后一个应用数据字节后追加以太网 FCS。
    assign frame_byte =
        (byte_index < 7) ? 8'h55 :
        (byte_index == 7) ? 8'hD5 :
        (eth_index < 6) ? 8'hFF :
        (eth_index < 12) ? mac_byte(SRC_MAC, eth_index - 6) :
        (eth_index == 12) ? 8'h08 :
        (eth_index == 13) ? 8'h00 :
        (ip_index == 0) ? 8'h45 :
        (ip_index == 1) ? 8'h00 :
        (ip_index == 2) ? IP_TOTAL_LENGTH[15:8] :
        (ip_index == 3) ? IP_TOTAL_LENGTH[7:0] :
        (ip_index == 4 || ip_index == 5) ? 8'h00 :
        (ip_index == 6) ? 8'h40 :
        (ip_index == 7) ? 8'h00 :
        (ip_index == 8) ? 8'h40 :
        (ip_index == 9) ? 8'h11 :
        (ip_index == 10) ? IP_CHECKSUM[15:8] :
        (ip_index == 11) ? IP_CHECKSUM[7:0] :
        (ip_index == 12) ? SRC_IP[31:24] :
        (ip_index == 13) ? SRC_IP[23:16] :
        (ip_index == 14) ? SRC_IP[15:8] :
        (ip_index == 15) ? SRC_IP[7:0] :
        (ip_index >= 16 && ip_index <= 19) ? 8'hFF :
        (udp_index == 0 || udp_index == 2) ? UDP_PORT[15:8] :
        (udp_index == 1 || udp_index == 3) ? UDP_PORT[7:0] :
        (udp_index == 4) ? UDP_LENGTH[15:8] :
        (udp_index == 5) ? UDP_LENGTH[7:0] :
        (udp_index == 6 || udp_index == 7) ? 8'h00 :
        (app_index == 0) ? 8'h44 : // 协议魔数 "DAC2"
        (app_index == 1) ? 8'h41 :
        (app_index == 2) ? 8'h43 :
        (app_index == 3) ? 8'h32 :
        (app_index == 4) ? 8'h01 : // 协议版本
        (app_index == 5) ? {4'd0, upload_source_latched,
                            family_latched, mode_latched} :
        (app_index == 6) ? packet_index :
        (app_index == 7) ? PACKET_COUNT[7:0] :
        (app_index >= 8 && app_index <= 11) ? u32_le(frame_id_latched, app_index-8) :
        (app_index >= 12 && app_index <= 15) ?
            u32_le({18'd0, packet_index, 8'd0}, app_index-12) :
        (app_index == 16) ? SAMPLES_PER_PACKET[7:0] :
        (app_index == 17) ? SAMPLES_PER_PACKET[15:8] :
        (app_index == 18) ? 8'h18 : // 样本位宽 = 24
        (app_index == 19) ? 8'h01 : // 有符号小端格式
        (app_index == 20) ? 8'h00 :
        (app_index == 21) ? 8'h40 : // 总样本数 = 16384
        (app_index >= 22 && app_index <= 25) ?
            u32_le(start_sample_index_latched, app_index-22) :
        (app_index >= 26 && app_index <= 29) ?
            u32_le(transaction_id_latched, app_index-26) :
        (app_index >= 30 && app_index < APP_HEADER_BYTES) ? 8'h00 :
        packet_payload_byte;

    ethernet_crc32 u_crc32 (
        .crc_in (crc_reg),
        .data_in(frame_byte),
        .crc_out(crc_next)
    );

    always @(*) begin
        tx_data  = 8'h00;
        tx_valid = 1'b0;
        tx_last  = 1'b0;
        if (state == ST_SEND) begin
            tx_data  = frame_byte;
            tx_valid = 1'b1;
        end else if (state == ST_FCS) begin
            case (fcs_index)
                2'd0: tx_data = fcs_word[7:0];
                2'd1: tx_data = fcs_word[15:8];
                2'd2: tx_data = fcs_word[23:16];
                default: tx_data = fcs_word[31:24];
            endcase
            tx_valid = 1'b1;
            tx_last  = (fcs_index == 2'd3);
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state              <= ST_IDLE;
            byte_index         <= 11'd0;
            packet_index       <= 6'd0;
            crc_reg            <= 32'hFFFFFFFF;
            fcs_word           <= 32'd0;
            fcs_index          <= 2'd0;
            gap_count          <= 19'd0;
            capture_take       <= 1'b0;
            capture_rd_addr    <= 14'd0;
            frame_id_latched   <= 32'd0;
            start_sample_index_latched <= 32'd0;
            mode_latched       <= 2'd0;
            family_latched     <= 1'b0;
            upload_source_latched <= 1'b0;
            transaction_id_latched <= 32'd0;
            // sample_latched 有意不设置复位值。每个样本都先在载荷第 0 字节锁存，
            // 随后第 1/2 字节才会读取；不复位还能避免复位控制进入推断 BRAM 的
            // 可选输出寄存器。
        end else begin
            // capture_take 是保持型翻转信号，而非脉冲。音频时钟低于本时钟域，
            // 否则单周期脉冲可能被 CDC 同步器漏采。
            case (state)
                ST_IDLE: begin
                    if (capture_valid) begin
                        frame_id_latched <= capture_frame_id;
                        start_sample_index_latched <= capture_start_sample_index;
                        mode_latched     <= capture_mode;
                        family_latched   <= capture_family_48k;
                        upload_source_latched <= capture_upload_source;
                        transaction_id_latched <= capture_transaction_id;
                        packet_index     <= 6'd0;
                        capture_rd_addr  <= 14'd0;
                        state            <= ST_PRIME;
                    end
                end

                ST_PRIME: begin
                    // 为同步 BRAM 读取预留一个周期。
                    byte_index <= 11'd0;
                    crc_reg    <= 32'hFFFFFFFF;
                    capture_rd_addr <= {packet_index, 8'd0};
                    state      <= ST_SEND;
                end

                ST_SEND: if (tx_ready) begin
                    if (byte_index >= 11'd8)
                        crc_reg <= crc_next;

                    // 在每个 24 位样本的首字节锁存完整数据。再过一个字节后请求下一个
                    // BRAM 地址；同步 BRAM 读端口切换期间，第 3 个字节仍保持稳定。
                    if (byte_index >= (8+14+20+8+APP_HEADER_BYTES)) begin
                        if (sample_byte_lane == 2'd0)
                            sample_latched <= capture_rd_data;
                        if (sample_byte_lane == 2'd1)
                            capture_rd_addr <= capture_rd_addr + 14'd1;
                    end

                    if (byte_index == FRAME_NO_FCS_BYTES-1) begin
                        fcs_word  <= ~crc_next;
                        fcs_index <= 2'd0;
                        state     <= ST_FCS;
                    end else begin
                        byte_index <= byte_index + 11'd1;
                    end
                end

                ST_FCS: if (tx_ready) begin
                    if (fcs_index == 2'd3) begin
                        gap_count <= FRAME_GAP_CYCLES-1;
                        state     <= ST_GAP;
                    end else begin
                        fcs_index <= fcs_index + 2'd1;
                    end
                end

                ST_GAP: begin
                    if (gap_count != 0)
                        gap_count <= gap_count - 19'd1;
                    else if (packet_index == PACKET_COUNT-1) begin
                        capture_take <= ~capture_take;
                        state        <= ST_ACK;
                    end else begin
                        packet_index      <= packet_index + 6'd1;
                        state             <= ST_PRIME;
                    end
                end

                // 捕获模块观察到保持型 capture_take 翻转后，会在一个网络时钟周期后
                // 清除 frame_valid。在此等待可防止 ST_IDLE 重新锁存旧描述符并重复发送同一帧。
                ST_ACK: begin
                    if (!capture_valid)
                        state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
