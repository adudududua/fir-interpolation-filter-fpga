`timescale 1ns / 1ps

//=============================================================
// 文件名       : udp_ipv4_rx_parser.v
// 模块名       : udp_ipv4_rx_parser
// 功能简述     : 精简 Ethernet/IPv4/UDP 接收解析器。验证目的地址、EtherType、IPv4 头校验和、长度、分片条件和 FCS，并用双 1 KiB Bank 后验回放 UDP payload。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
// 精简 Ethernet II / IPv4 / UDP 接收解析器。
//
// 输入必须从目的 MAC 第一个字节开始，并包含最后 4 字节以太网 FCS；
// 前导码、SFD 和线间隙由下层移除。解析器仅接收：
//   * EtherType 0x0800；IPv4、IHL=5、无分片、协议 UDP；
//   * 目的 MAC 为 LOCAL_MAC 或广播；
//   * 目的 IP 为 LOCAL_IP 或 255.255.255.255；
//   * UDP 目的端口为 UDP_PORT，长度字段彼此一致。
//
// 为了在确认尾部 FCS 之前不泄漏错误包，UDP 载荷先写入内部缓冲区；
// frame_end 到达且全部检查通过后，才从 payload_* 接口回放。
// 载荷最大 MAX_PAYLOAD 字节。UDP 校验和允许为零；非零校验和本阶段不验证。
module udp_ipv4_rx_parser #(
    parameter [47:0] LOCAL_MAC = 48'h02_35_24_00_00_01,
    parameter [31:0] LOCAL_IP  = 32'hC0A8010A,
    parameter [15:0] UDP_PORT  = 16'd4001,
    parameter integer MAX_PAYLOAD = 1024
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] frame_data,
    input  wire       frame_data_valid,
    input  wire       frame_start,
    input  wire       frame_end,
    input  wire       frame_error,

    output wire [7:0] payload_data,
    output reg        payload_valid,
    output reg        payload_last,
    output reg        packet_valid,
    output reg        packet_drop,
    output reg  [15:0] payload_length,
    output reg  [31:0] source_ip,
    output reg  [15:0] source_port
);
    localparam integer AW = (MAX_PAYLOAD <= 2) ? 1 : $clog2(MAX_PAYLOAD);

    // 两个包缓冲区允许前一包回放时继续接收下一包。100M RGMII 输入为
    // 每两个 rx_clk 一个字节，而回放端每个 clk 输出一个字节。
    localparam integer BANK_DEPTH = (1 << AW);
    reg [7:0] payload_mem [0:2*BANK_DEPTH-1];
    reg [AW:0] payload_wr_addr;
    reg [AW:0] payload_rd_addr;
    reg        write_bank;
    reg        next_write_bank;
    reg        write_conflict;
    reg [15:0] replay_remaining;
    reg        replay_active;

    reg        receiving;
    reg [15:0] byte_index;
    reg [15:0] ip_total_length;
    reg [15:0] udp_length;
    reg [15:0] expected_frame_bytes;
    reg [15:0] payload_expected;
    reg [15:0] payload_received;
    reg [47:0] destination_mac;
    reg [15:0] ether_type;
    reg [7:0]  ip_vihl;
    reg [15:0] ip_flags_fragment;
    reg [7:0]  ip_protocol;
    reg [15:0] ip_checksum_sum;
    reg [7:0]  ip_word_high;
    reg [31:0] destination_ip;
    reg [15:0] udp_destination_port;
    reg        malformed;

    reg [31:0] crc_reg;
    reg [7:0]  fcs_byte0;
    reg [7:0]  fcs_byte1;
    reg [7:0]  fcs_byte2;
    reg [7:0]  fcs_byte3;
    wire [31:0] crc_step_in = (frame_start && frame_data_valid) ?
                              32'hFFFFFFFF : crc_reg;
    wire [31:0] crc_next;

    ethernet_crc32 u_crc32 (
        .crc_in (crc_step_in),
        .data_in(frame_data),
        .crc_out(crc_next)
    );

    function [15:0] checksum_add;
        input [15:0] sum_in;
        input [15:0] word_in;
        reg [16:0] sum_ext;
        begin
            sum_ext = {1'b0, sum_in} + {1'b0, word_in};
            checksum_add = sum_ext[15:0] + sum_ext[16];
        end
    endfunction

    wire [15:0] ip_payload_length = ip_total_length - 16'd20;
    wire [15:0] fcs_start_index = expected_frame_bytes - 16'd4;
    wire current_is_payload_byte = (byte_index >= 16'd42) &&
                                   (byte_index < (16'd42 + payload_expected));
    wire current_is_fcs_byte = (expected_frame_bytes >= 16'd46) &&
                               (byte_index >= fcs_start_index);
    wire frame_byte_is_payload = frame_data_valid && receiving &&
                                 (byte_index >= 16'd42) &&
                                 (byte_index < (16'd42 + payload_expected));
    wire [15:0] payload_received_after_byte = payload_received +
                                               (frame_byte_is_payload ? 16'd1 : 16'd0);
    wire [15:0] frame_bytes_after_byte = byte_index +
                                          ((frame_data_valid && receiving) ?
                                           16'd1 : 16'd0);
    wire frame_byte_is_last_fcs = frame_data_valid && receiving &&
                                  current_is_fcs_byte &&
                                  ((byte_index - fcs_start_index) == 16'd3);
    wire [31:0] received_fcs_after_byte = frame_byte_is_last_fcs ?
                                          {frame_data, fcs_byte2,
                                           fcs_byte1, fcs_byte0} :
                                           {fcs_byte3, fcs_byte2,
                                            fcs_byte1, fcs_byte0};

    // 缓冲 RAM 的读写寄存器均不带复位。复位只清 valid/地址/状态，旧 RAM
    // 内容不会对外有效，从而避免异步复位进入 RAMB 的 WEA/EN/RST 控制脚。
    wire payload_mem_write_en = frame_byte_is_payload &&
                                (payload_received < MAX_PAYLOAD);
    reg        payload_mem_write_en_q = 1'b0;
    reg [AW:0] payload_mem_write_addr_q;
    reg [7:0]  payload_mem_write_data_q;
    reg [7:0]  payload_mem_read_data_q;

    assign payload_data = payload_mem_read_data_q;

    // 先把写命令寄存一拍，再送入 BRAM。三个流水寄存器都不使用复位；
    // 复位期间 RAM 内容本来就无效，下一帧会完整覆盖自己的有效地址范围。
    // 这样 RAMB 的 EN/WE 控制锥中完全没有异步复位源。
    always @(posedge clk) begin
        payload_mem_write_en_q   <= payload_mem_write_en;
        payload_mem_write_addr_q <= payload_wr_addr;
        payload_mem_write_data_q <= frame_data;

        if (payload_mem_write_en_q)
            payload_mem[payload_mem_write_addr_q] <= payload_mem_write_data_q;
    end

    // 独立的同步读端严格匹配简单双口 BRAM 模板。读数据寄存器不复位；
    // payload_valid=0 时其内容无效，因此冷启动残值不会被上层消费。
    always @(posedge clk) begin
        payload_mem_read_data_q <= payload_mem[payload_rd_addr];
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            payload_valid        <= 1'b0;
            payload_last         <= 1'b0;
            packet_valid         <= 1'b0;
            packet_drop          <= 1'b0;
            payload_length       <= 16'd0;
            source_ip            <= 32'd0;
            source_port          <= 16'd0;
            payload_wr_addr      <= {(AW+1){1'b0}};
            payload_rd_addr      <= {(AW+1){1'b0}};
            write_bank           <= 1'b0;
            next_write_bank      <= 1'b0;
            write_conflict       <= 1'b0;
            replay_remaining     <= 16'd0;
            replay_active        <= 1'b0;
            receiving            <= 1'b0;
            byte_index           <= 16'd0;
            ip_total_length      <= 16'd0;
            udp_length           <= 16'd0;
            expected_frame_bytes <= 16'd0;
            payload_expected     <= 16'd0;
            payload_received     <= 16'd0;
            destination_mac      <= 48'd0;
            ether_type           <= 16'd0;
            ip_vihl              <= 8'd0;
            ip_flags_fragment    <= 16'd0;
            ip_protocol          <= 8'd0;
            ip_checksum_sum      <= 16'd0;
            ip_word_high         <= 8'd0;
            destination_ip       <= 32'd0;
            udp_destination_port <= 16'd0;
            malformed            <= 1'b0;
            crc_reg              <= 32'hFFFFFFFF;
            fcs_byte0            <= 8'd0;
            fcs_byte1            <= 8'd0;
            fcs_byte2            <= 8'd0;
            fcs_byte3            <= 8'd0;
        end else begin
            payload_valid <= 1'b0;
            payload_last  <= 1'b0;
            packet_valid  <= 1'b0;
            packet_drop   <= 1'b0;

            if (replay_active) begin
                payload_valid <= 1'b1;
                payload_last  <= (replay_remaining == 16'd1);
                if (replay_remaining == 16'd1) begin
                    replay_active    <= 1'b0;
                    replay_remaining <= 16'd0;
                end else begin
                    payload_rd_addr  <= payload_rd_addr + {{AW{1'b0}}, 1'b1};
                    replay_remaining <= replay_remaining - 16'd1;
                end
            end

            if (frame_start && frame_data_valid) begin
                receiving            <= 1'b1;
                byte_index           <= 16'd1;
                write_bank           <= next_write_bank;
                payload_wr_addr      <= {next_write_bank, {AW{1'b0}}};
                write_conflict       <= replay_active &&
                                        (next_write_bank == payload_rd_addr[AW]);
                payload_received     <= 16'd0;
                payload_expected     <= 16'd0;
                expected_frame_bytes <= 16'd0;
                ip_total_length      <= 16'd0;
                udp_length           <= 16'd0;
                destination_mac      <= {frame_data, 40'd0};
                ether_type           <= 16'd0;
                ip_vihl              <= 8'd0;
                ip_flags_fragment    <= 16'd0;
                ip_protocol          <= 8'd0;
                ip_checksum_sum      <= 16'd0;
                ip_word_high         <= 8'd0;
                source_ip            <= 32'd0;
                destination_ip       <= 32'd0;
                source_port          <= 16'd0;
                udp_destination_port <= 16'd0;
                malformed            <= 1'b0;
                crc_reg              <= crc_next;
                fcs_byte0            <= 8'd0;
                fcs_byte1            <= 8'd0;
                fcs_byte2            <= 8'd0;
                fcs_byte3            <= 8'd0;
            end else if (receiving && frame_data_valid) begin
                byte_index <= byte_index + 16'd1;

                case (byte_index)
                    16'd1:  destination_mac[39:32] <= frame_data;
                    16'd2:  destination_mac[31:24] <= frame_data;
                    16'd3:  destination_mac[23:16] <= frame_data;
                    16'd4:  destination_mac[15:8]  <= frame_data;
                    16'd5:  destination_mac[7:0]   <= frame_data;
                    16'd12: ether_type[15:8] <= frame_data;
                    16'd13: ether_type[7:0]  <= frame_data;
                    16'd14: ip_vihl <= frame_data;
                    16'd16: ip_total_length[15:8] <= frame_data;
                    16'd17: begin
                        ip_total_length[7:0] <= frame_data;
                        expected_frame_bytes <= {ip_total_length[15:8], frame_data} + 16'd18;
                    end
                    16'd20: ip_flags_fragment[15:8] <= frame_data;
                    16'd21: ip_flags_fragment[7:0]  <= frame_data;
                    16'd23: ip_protocol <= frame_data;
                    16'd26: source_ip[31:24] <= frame_data;
                    16'd27: source_ip[23:16] <= frame_data;
                    16'd28: source_ip[15:8]  <= frame_data;
                    16'd29: source_ip[7:0]   <= frame_data;
                    16'd30: destination_ip[31:24] <= frame_data;
                    16'd31: destination_ip[23:16] <= frame_data;
                    16'd32: destination_ip[15:8]  <= frame_data;
                    16'd33: destination_ip[7:0]   <= frame_data;
                    16'd34: source_port[15:8] <= frame_data;
                    16'd35: source_port[7:0]  <= frame_data;
                    16'd36: udp_destination_port[15:8] <= frame_data;
                    16'd37: udp_destination_port[7:0]  <= frame_data;
                    16'd38: udp_length[15:8] <= frame_data;
                    16'd39: begin
                        udp_length[7:0] <= frame_data;
                        if ({udp_length[15:8], frame_data} >= 16'd8)
                            payload_expected <= {udp_length[15:8], frame_data} - 16'd8;
                        else begin
                            payload_expected <= 16'd0;
                            malformed <= 1'b1;
                        end
                        if (({udp_length[15:8], frame_data} < 16'd8) ||
                            (({udp_length[15:8], frame_data} - 16'd8) > MAX_PAYLOAD))
                            malformed <= 1'b1;
                    end
                    default: begin end
                endcase

                if ((byte_index >= 16'd14) && (byte_index <= 16'd33)) begin
                    if (!byte_index[0]) begin
                        ip_word_high <= frame_data;
                    end else begin
                        ip_checksum_sum <= checksum_add(
                            ip_checksum_sum, {ip_word_high, frame_data});
                        if ((byte_index == 16'd33) &&
                            (checksum_add(ip_checksum_sum,
                                          {ip_word_high, frame_data}) != 16'hFFFF))
                            malformed <= 1'b1;
                    end
                end

                if (current_is_payload_byte) begin
                    if (payload_received < MAX_PAYLOAD) begin
                        payload_wr_addr  <= payload_wr_addr + {{AW{1'b0}}, 1'b1};
                        payload_received <= payload_received + 16'd1;
                    end else begin
                        malformed <= 1'b1;
                    end
                end

                if (current_is_fcs_byte) begin
                    case (byte_index - fcs_start_index)
                        16'd0: fcs_byte0 <= frame_data;
                        16'd1: fcs_byte1 <= frame_data;
                        16'd2: fcs_byte2 <= frame_data;
                        default: fcs_byte3 <= frame_data;
                    endcase
                end else begin
                    crc_reg <= crc_next;
                end
            end

            if (frame_end && receiving) begin
                receiving <= 1'b0;
                if (!frame_error && !malformed && !write_conflict &&
                         (frame_bytes_after_byte == expected_frame_bytes) &&
                         ((destination_mac == LOCAL_MAC) ||
                          (destination_mac == 48'hFFFFFFFFFFFF)) &&
                         (ether_type == 16'h0800) &&
                         (ip_vihl == 8'h45) &&
                         (ip_total_length >= 16'd28) &&
                         // MF 标志与 13 位分片偏移必须为零；DF 可为任意值。
                         ((ip_flags_fragment & 16'h3FFF) == 16'd0) &&
                         (ip_protocol == 8'h11) &&
                         ((destination_ip == LOCAL_IP) ||
                          (destination_ip == 32'hFFFFFFFF)) &&
                         (udp_destination_port == UDP_PORT) &&
                         (udp_length == ip_payload_length) &&
                         (payload_received_after_byte == payload_expected) &&
                         (received_fcs_after_byte == ~crc_reg) &&
                         !replay_active) begin
                    packet_valid     <= 1'b1;
                    payload_length   <= payload_expected;
                    payload_rd_addr  <= {write_bank, {AW{1'b0}}};
                    next_write_bank  <= ~write_bank;
                    replay_remaining <= payload_expected;
                    replay_active    <= (payload_expected != 16'd0);
                end else begin
                    packet_drop <= 1'b1;
                end
            end
        end
    end
endmodule
