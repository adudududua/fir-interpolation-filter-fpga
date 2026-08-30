`timescale 1ns / 1ps

//=============================================================
// 文件名       : arp_reply_tx.v
// 模块名       : arp_reply_tx
// 功能简述     : ARP 应答帧发送器。根据合法请求构造单播 ARP Reply，补齐最小以太网帧并生成 IEEE CRC32/FCS。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
// ARP reply Ethernet 帧发送器。输入事件与输出字节流位于同一时钟域。
// 输出包含 7 字节前导码、SFD、最小长度 Ethernet II 帧、填充和 FCS。
module arp_reply_tx #(
    parameter [47:0] LOCAL_MAC = 48'h02_35_24_00_00_01,
    parameter [31:0] LOCAL_IP  = 32'hC0A8_010A
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        request_valid,
    output wire        request_ready,
    input  wire [47:0] requester_mac,
    input  wire [31:0] requester_ip,
    output reg  [7:0]  tx_data,
    output reg         tx_valid,
    input  wire        tx_ready,
    output reg         tx_last
);
    localparam integer FRAME_NO_FCS_BYTES = 8 + 60;
    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_SEND = 2'd1;
    localparam [1:0] ST_FCS  = 2'd2;

    reg [1:0] state;
    reg [6:0] byte_index;
    reg [1:0] fcs_index;
    reg [47:0] requester_mac_latched;
    reg [31:0] requester_ip_latched;
    reg [31:0] crc_reg;
    reg [31:0] fcs_word;

    wire [6:0] eth_index = byte_index - 7'd8;
    wire [6:0] arp_index = eth_index - 7'd14;
    wire [7:0] frame_byte;
    wire [31:0] crc_next;

    function [7:0] mac_byte;
        input [47:0] mac;
        input [2:0] index;
        begin mac_byte = mac[47-index*8 -: 8]; end
    endfunction

    function [7:0] ip_byte;
        input [31:0] ip;
        input [1:0] index;
        begin ip_byte = ip[31-index*8 -: 8]; end
    endfunction

    assign request_ready = (state == ST_IDLE);

    assign frame_byte =
        (byte_index < 7) ? 8'h55 :
        (byte_index == 7) ? 8'hD5 :
        (eth_index < 6) ? mac_byte(requester_mac_latched, eth_index[2:0]) :
        (eth_index < 12) ? mac_byte(LOCAL_MAC, eth_index[2:0] - 3'd6) :
        (eth_index == 12) ? 8'h08 :
        (eth_index == 13) ? 8'h06 :
        (arp_index == 0) ? 8'h00 :
        (arp_index == 1) ? 8'h01 :
        (arp_index == 2) ? 8'h08 :
        (arp_index == 3) ? 8'h00 :
        (arp_index == 4) ? 8'h06 :
        (arp_index == 5) ? 8'h04 :
        (arp_index == 6) ? 8'h00 :
        (arp_index == 7) ? 8'h02 :
        (arp_index >= 8 && arp_index <= 13) ?
            mac_byte(LOCAL_MAC, arp_index[2:0]) :
        (arp_index >= 14 && arp_index <= 17) ?
            ip_byte(LOCAL_IP, arp_index[1:0] - 2'd2) :
        (arp_index >= 18 && arp_index <= 23) ?
            mac_byte(requester_mac_latched, arp_index[2:0] - 3'd2) :
        (arp_index >= 24 && arp_index <= 27) ?
            ip_byte(requester_ip_latched, arp_index[1:0]) :
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
            state                   <= ST_IDLE;
            byte_index              <= 7'd0;
            fcs_index               <= 2'd0;
            requester_mac_latched   <= 48'd0;
            requester_ip_latched    <= 32'd0;
            crc_reg                 <= 32'hFFFF_FFFF;
            fcs_word                <= 32'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (request_valid) begin
                        requester_mac_latched <= requester_mac;
                        requester_ip_latched  <= requester_ip;
                        byte_index            <= 7'd0;
                        crc_reg               <= 32'hFFFF_FFFF;
                        state                 <= ST_SEND;
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
