`timescale 1ns / 1ps

//=============================================================
// 文件名       : udp_control_ack_tx.v
// 模块名       : udp_control_ack_tx
// 功能简述     : UDP4001 控制 ACK 发送器。回显 transaction/sequence/total/next_offset/status，构造完整 Ethernet/IPv4/UDP/DACU ACK 帧。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
// DAC24 控制通道 ACK 帧发送器。
//
// 接受一个单项事件后，产生一帧完整的 Ethernet II / IPv4 / UDP 数据，
// 字节流包含前导码、SFD 和 Ethernet FCS，可直接接入 rgmii100_tx。
// 目的 MAC 使用广播地址，避免控制通道依赖 ARP；目的 IP 和 UDP 端口来自
// 最近一帧合法请求的源地址。IPv4 头校验和随目的 IP 动态计算，UDP 校验和为 0。
//
// 应用层为固定 32 字节 DACU ACK 头：
//   0..3   "DACU"，4=版本 1，5=ACK(0x81)，6=flags 0，7=头长 32
//   8..11  transaction_id，小端
//   12..15 sequence，小端
//   16..19 total_samples，小端，回显当前请求
//   20..23 next_offset，小端
//   24..25 status_code，小端
//   26=24 位，27=有符号小端格式 1，28..31=空正文 CRC32 0
module udp_control_ack_tx #(
    parameter [47:0] SRC_MAC  = 48'h02_35_24_00_00_01,
    parameter [31:0] SRC_IP   = 32'hC0A8_010A,
    parameter [15:0] SRC_PORT = 16'd4001
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        event_valid,
    output wire        event_ready,
    input  wire [15:0] status_code,
    input  wire [31:0] transaction_id,
    input  wire [31:0] sequence,
    input  wire [31:0] total_samples,
    input  wire [31:0] next_offset,
    input  wire [31:0] dest_ip,
    input  wire [15:0] dest_port,

    output reg  [7:0]  tx_data,
    output reg         tx_valid,
    input  wire        tx_ready,
    output reg         tx_last
);
    localparam [15:0] APP_LENGTH      = 16'd32;
    localparam [15:0] UDP_LENGTH      = 16'd40; // UDP 头 8 + DACU 头 32
    localparam [15:0] IP_TOTAL_LENGTH = 16'd60; // IPv4 头 20 + UDP 40
    localparam integer FRAME_NO_FCS_BYTES = 82; // 前导码 8 + Ethernet 正文 74

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_SEND = 2'd1;
    localparam [1:0] ST_FCS  = 2'd2;

    reg [1:0] state;
    reg [6:0] byte_index;
    reg [1:0] fcs_index;
    reg [31:0] crc_reg;
    reg [31:0] fcs_word;

    reg [15:0] status_code_latched;
    reg [31:0] transaction_id_latched;
    reg [31:0] sequence_latched;
    reg [31:0] total_samples_latched;
    reg [31:0] next_offset_latched;
    reg [31:0] dest_ip_latched;
    reg [15:0] dest_port_latched;

    wire [7:0] frame_byte;
    wire [31:0] crc_next;
    wire [15:0] ip_checksum;

    assign event_ready = (state == ST_IDLE);

    function [7:0] mac_byte;
        input [47:0] mac;
        input [2:0] index;
        begin
            case (index)
                3'd0: mac_byte = mac[47:40];
                3'd1: mac_byte = mac[39:32];
                3'd2: mac_byte = mac[31:24];
                3'd3: mac_byte = mac[23:16];
                3'd4: mac_byte = mac[15:8];
                default: mac_byte = mac[7:0];
            endcase
        end
    endfunction

    function [7:0] u32_le;
        input [31:0] value;
        input [1:0] index;
        begin
            case (index)
                2'd0: u32_le = value[7:0];
                2'd1: u32_le = value[15:8];
                2'd2: u32_le = value[23:16];
                default: u32_le = value[31:24];
            endcase
        end
    endfunction

    // 对无选项的 20 字节 IPv4 头做一补校验和。IP identification 固定为 0，
    // DF 置 1、TTL=64、协议号=17；因此只有目的 IP 是运行时变量。
    function [15:0] ipv4_header_checksum;
        input [31:0] destination_ip;
        reg [31:0] sum;
        begin
            sum = 32'h0000_4500 + IP_TOTAL_LENGTH + 32'h0000_0000
                + 32'h0000_4000 + 32'h0000_4011
                + SRC_IP[31:16] + SRC_IP[15:0]
                + destination_ip[31:16] + destination_ip[15:0];
            sum = {16'd0, sum[15:0]} + sum[31:16];
            sum = {16'd0, sum[15:0]} + sum[31:16];
            ipv4_header_checksum = ~sum[15:0];
        end
    endfunction

    assign ip_checksum = ipv4_header_checksum(dest_ip_latched);

    // byte_index 0..7 为前导码/SFD，8..81 为参与 CRC 的 Ethernet 帧正文。
    assign frame_byte =
        (byte_index < 7) ? 8'h55 :
        (byte_index == 7) ? 8'hD5 :
        (byte_index < 14) ? 8'hFF :
        (byte_index < 20) ? mac_byte(SRC_MAC, byte_index - 7'd14) :
        (byte_index == 20) ? 8'h08 :
        (byte_index == 21) ? 8'h00 :
        // IPv4 头从索引 22 开始。
        (byte_index == 22) ? 8'h45 :
        (byte_index == 23) ? 8'h00 :
        (byte_index == 24) ? IP_TOTAL_LENGTH[15:8] :
        (byte_index == 25) ? IP_TOTAL_LENGTH[7:0] :
        (byte_index == 26 || byte_index == 27) ? 8'h00 :
        (byte_index == 28) ? 8'h40 :
        (byte_index == 29) ? 8'h00 :
        (byte_index == 30) ? 8'h40 :
        (byte_index == 31) ? 8'h11 :
        (byte_index == 32) ? ip_checksum[15:8] :
        (byte_index == 33) ? ip_checksum[7:0] :
        (byte_index == 34) ? SRC_IP[31:24] :
        (byte_index == 35) ? SRC_IP[23:16] :
        (byte_index == 36) ? SRC_IP[15:8] :
        (byte_index == 37) ? SRC_IP[7:0] :
        (byte_index == 38) ? dest_ip_latched[31:24] :
        (byte_index == 39) ? dest_ip_latched[23:16] :
        (byte_index == 40) ? dest_ip_latched[15:8] :
        (byte_index == 41) ? dest_ip_latched[7:0] :
        // UDP 头从索引 42 开始。
        (byte_index == 42) ? SRC_PORT[15:8] :
        (byte_index == 43) ? SRC_PORT[7:0] :
        (byte_index == 44) ? dest_port_latched[15:8] :
        (byte_index == 45) ? dest_port_latched[7:0] :
        (byte_index == 46) ? UDP_LENGTH[15:8] :
        (byte_index == 47) ? UDP_LENGTH[7:0] :
        (byte_index == 48 || byte_index == 49) ? 8'h00 :
        // DACU ACK 头从索引 50 开始。
        (byte_index == 50) ? 8'h44 :
        (byte_index == 51) ? 8'h41 :
        (byte_index == 52) ? 8'h43 :
        (byte_index == 53) ? 8'h55 :
        (byte_index == 54) ? 8'h01 :
        (byte_index == 55) ? 8'h81 :
        (byte_index == 56) ? 8'h00 :
        (byte_index == 57) ? APP_LENGTH[7:0] :
        (byte_index >= 58 && byte_index <= 61) ?
            u32_le(transaction_id_latched, byte_index - 7'd58) :
        (byte_index >= 62 && byte_index <= 65) ?
            u32_le(sequence_latched, byte_index - 7'd62) :
        (byte_index >= 66 && byte_index <= 69) ?
            u32_le(total_samples_latched, byte_index - 7'd66) :
        (byte_index >= 70 && byte_index <= 73) ?
            u32_le(next_offset_latched, byte_index - 7'd70) :
        (byte_index == 74) ? status_code_latched[7:0] :
        (byte_index == 75) ? status_code_latched[15:8] :
        (byte_index == 76) ? 8'h18 :
        (byte_index == 77) ? 8'h01 :
        8'h00;

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
            state                  <= ST_IDLE;
            byte_index             <= 7'd0;
            fcs_index              <= 2'd0;
            crc_reg                <= 32'hFFFF_FFFF;
            fcs_word               <= 32'd0;
            status_code_latched    <= 16'd0;
            transaction_id_latched <= 32'd0;
            sequence_latched       <= 32'd0;
            total_samples_latched  <= 32'd0;
            next_offset_latched    <= 32'd0;
            dest_ip_latched        <= 32'd0;
            dest_port_latched      <= 16'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (event_valid) begin
                        status_code_latched    <= status_code;
                        transaction_id_latched <= transaction_id;
                        sequence_latched       <= sequence;
                        total_samples_latched  <= total_samples;
                        next_offset_latched    <= next_offset;
                        dest_ip_latched        <= dest_ip;
                        dest_port_latched      <= dest_port;
                        byte_index             <= 7'd0;
                        crc_reg                <= 32'hFFFF_FFFF;
                        state                  <= ST_SEND;
                    end
                end

                ST_SEND: begin
                    if (tx_valid && tx_ready) begin
                        if (byte_index >= 7'd8)
                            crc_reg <= crc_next;
                        if (byte_index == FRAME_NO_FCS_BYTES-1) begin
                            fcs_word  <= ~crc_next;
                            fcs_index <= 2'd0;
                            state     <= ST_FCS;
                        end else begin
                            byte_index <= byte_index + 7'd1;
                        end
                    end
                end

                ST_FCS: begin
                    if (tx_valid && tx_ready) begin
                        if (fcs_index == 2'd3)
                            state <= ST_IDLE;
                        else
                            fcs_index <= fcs_index + 2'd1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
