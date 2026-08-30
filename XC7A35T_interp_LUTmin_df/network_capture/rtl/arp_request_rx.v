`timescale 1ns / 1ps

//=============================================================
// 文件名       : arp_request_rx.v
// 模块名       : arp_request_rx
// 功能简述     : ARP 请求接收与校验模块。核对目标 MAC/IP、ARP 字段和 Ethernet FCS，并向应答通道提交来源地址描述符。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
// 精简 Ethernet II / ARP 请求接收器。
//
// 输入从目的 MAC 第一个字节开始并包含 Ethernet FCS；前导码与 SFD 已由
// rgmii100_rx 剥离。仅接受发往本机或广播 MAC、目标 IPv4 为 LOCAL_IP 的
// Ethernet/IPv4 ARP request。整帧 CRC residue 正确后，才发布请求方 MAC/IP。
// request_valid 会保持到 request_ready，避免发送器短暂忙时丢失 ARP 请求。
module arp_request_rx #(
    parameter [47:0] LOCAL_MAC = 48'h02_35_24_00_00_01,
    parameter [31:0] LOCAL_IP  = 32'hC0A8_010A
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  frame_data,
    input  wire        frame_data_valid,
    input  wire        frame_start,
    input  wire        frame_end,
    input  wire        frame_error,

    output reg         request_valid,
    input  wire        request_ready,
    output reg  [47:0] requester_mac,
    output reg  [31:0] requester_ip
);
    // 对目的 MAC 到 FCS 的全部字节执行反射式 CRC-32 后，合法 Ethernet 帧
    // 的固定 residue。这样无需预先知道填充长度，也无需单独缓存最后四字节。
    localparam [31:0] ETHERNET_CRC_RESIDUE = 32'hDEBB_20E3;

    reg        receiving;
    reg [15:0] byte_count;
    reg [47:0] destination_mac;
    reg [47:0] ethernet_source_mac;
    reg [15:0] ether_type;
    reg [15:0] arp_hardware_type;
    reg [15:0] arp_protocol_type;
    reg [7:0]  arp_hardware_length;
    reg [7:0]  arp_protocol_length;
    reg [15:0] arp_opcode;
    reg [47:0] arp_sender_mac;
    reg [31:0] arp_sender_ip;
    reg [31:0] arp_target_ip;
    reg [31:0] crc_reg;
    reg        pending_valid;
    reg [47:0] pending_requester_mac;
    reg [31:0] pending_requester_ip;

    wire input_byte = frame_data_valid && (frame_start || receiving);
    wire [31:0] crc_step_in = (frame_start && frame_data_valid) ?
                              32'hFFFF_FFFF : crc_reg;
    wire [31:0] crc_next;
    wire [31:0] crc_after_byte = input_byte ? crc_next : crc_reg;

    ethernet_crc32 u_crc32 (
        .crc_in (crc_step_in),
        .data_in(frame_data),
        .crc_out(crc_next)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            request_valid       <= 1'b0;
            requester_mac       <= 48'd0;
            requester_ip        <= 32'd0;
            receiving           <= 1'b0;
            byte_count          <= 16'd0;
            destination_mac     <= 48'd0;
            ethernet_source_mac <= 48'd0;
            ether_type          <= 16'd0;
            arp_hardware_type   <= 16'd0;
            arp_protocol_type   <= 16'd0;
            arp_hardware_length <= 8'd0;
            arp_protocol_length <= 8'd0;
            arp_opcode          <= 16'd0;
            arp_sender_mac      <= 48'd0;
            arp_sender_ip       <= 32'd0;
            arp_target_ip       <= 32'd0;
            crc_reg             <= 32'hFFFF_FFFF;
            pending_valid       <= 1'b0;
            pending_requester_mac <= 48'd0;
            pending_requester_ip  <= 32'd0;
        end else begin
            if (request_valid && request_ready) begin
                if (pending_valid) begin
                    requester_mac <= pending_requester_mac;
                    requester_ip  <= pending_requester_ip;
                    request_valid <= 1'b1;
                    pending_valid <= 1'b0;
                end else begin
                    request_valid <= 1'b0;
                end
            end

            if (frame_start && frame_data_valid) begin
                receiving           <= 1'b1;
                byte_count          <= 16'd1;
                destination_mac     <= {frame_data, 40'd0};
                ethernet_source_mac <= 48'd0;
                ether_type          <= 16'd0;
                arp_hardware_type   <= 16'd0;
                arp_protocol_type   <= 16'd0;
                arp_hardware_length <= 8'd0;
                arp_protocol_length <= 8'd0;
                arp_opcode          <= 16'd0;
                arp_sender_mac      <= 48'd0;
                arp_sender_ip       <= 32'd0;
                arp_target_ip       <= 32'd0;
                crc_reg             <= crc_next;
            end else if (receiving && frame_data_valid) begin
                byte_count <= byte_count + 16'd1;
                crc_reg    <= crc_next;

                case (byte_count)
                    16'd1:  destination_mac[39:32] <= frame_data;
                    16'd2:  destination_mac[31:24] <= frame_data;
                    16'd3:  destination_mac[23:16] <= frame_data;
                    16'd4:  destination_mac[15:8]  <= frame_data;
                    16'd5:  destination_mac[7:0]   <= frame_data;
                    16'd6:  ethernet_source_mac[47:40] <= frame_data;
                    16'd7:  ethernet_source_mac[39:32] <= frame_data;
                    16'd8:  ethernet_source_mac[31:24] <= frame_data;
                    16'd9:  ethernet_source_mac[23:16] <= frame_data;
                    16'd10: ethernet_source_mac[15:8]  <= frame_data;
                    16'd11: ethernet_source_mac[7:0]   <= frame_data;
                    16'd12: ether_type[15:8] <= frame_data;
                    16'd13: ether_type[7:0]  <= frame_data;
                    16'd14: arp_hardware_type[15:8] <= frame_data;
                    16'd15: arp_hardware_type[7:0]  <= frame_data;
                    16'd16: arp_protocol_type[15:8] <= frame_data;
                    16'd17: arp_protocol_type[7:0]  <= frame_data;
                    16'd18: arp_hardware_length <= frame_data;
                    16'd19: arp_protocol_length <= frame_data;
                    16'd20: arp_opcode[15:8] <= frame_data;
                    16'd21: arp_opcode[7:0]  <= frame_data;
                    16'd22: arp_sender_mac[47:40] <= frame_data;
                    16'd23: arp_sender_mac[39:32] <= frame_data;
                    16'd24: arp_sender_mac[31:24] <= frame_data;
                    16'd25: arp_sender_mac[23:16] <= frame_data;
                    16'd26: arp_sender_mac[15:8]  <= frame_data;
                    16'd27: arp_sender_mac[7:0]   <= frame_data;
                    16'd28: arp_sender_ip[31:24] <= frame_data;
                    16'd29: arp_sender_ip[23:16] <= frame_data;
                    16'd30: arp_sender_ip[15:8]  <= frame_data;
                    16'd31: arp_sender_ip[7:0]   <= frame_data;
                    16'd38: arp_target_ip[31:24] <= frame_data;
                    16'd39: arp_target_ip[23:16] <= frame_data;
                    16'd40: arp_target_ip[15:8]  <= frame_data;
                    16'd41: arp_target_ip[7:0]   <= frame_data;
                    default: begin end
                endcase
            end

            if (frame_end && receiving) begin
                receiving <= 1'b0;
                if (!frame_error &&
                    (byte_count >= 16'd46) &&
                    (crc_after_byte == ETHERNET_CRC_RESIDUE) &&
                    ((destination_mac == LOCAL_MAC) ||
                     (destination_mac == 48'hFFFF_FFFF_FFFF)) &&
                    (ethernet_source_mac == arp_sender_mac) &&
                    (ether_type == 16'h0806) &&
                    (arp_hardware_type == 16'h0001) &&
                    (arp_protocol_type == 16'h0800) &&
                    (arp_hardware_length == 8'd6) &&
                    (arp_protocol_length == 8'd4) &&
                    (arp_opcode == 16'h0001) &&
                    (arp_target_ip == LOCAL_IP)) begin
                    if (!request_valid || request_ready) begin
                        requester_mac <= arp_sender_mac;
                        requester_ip  <= arp_sender_ip;
                        request_valid <= 1'b1;
                    end else if (!pending_valid) begin
                        // 一个 reply 正在序列化时再容纳一个 ARP 请求，避免
                        // 普通 PC 的短促重试恰好落在忙窗口而无人应答。
                        pending_requester_mac <= arp_sender_mac;
                        pending_requester_ip  <= arp_sender_ip;
                        pending_valid         <= 1'b1;
                    end
                end
            end
        end
    end
endmodule
