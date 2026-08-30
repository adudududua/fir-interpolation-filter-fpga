`timescale 1ns / 1ps

//=============================================================
// 文件名       : dac24_upload_protocol_rx.v
// 模块名       : dac24_upload_protocol_rx
// 功能简述     : DACU 应用层协议解析器。解析 32 字节小端头、CONTROL/WAVE/COMMIT 正文及 payload CRC32，向上传事务控制器输出结构化字段。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
// DAC24 PC->FPGA 上传协议头解析器。
//
// UDP 目的端口为 4001。载荷前 32 字节固定为：
//   0  magic[4]          ASCII "DACU"
//   4  version           1
//   5  msg_type          01 CONTROL, 02 WAVE_DATA, 03 COMMIT,
//                        81 ACK, 82 STATUS
//   6  flags             bit0 ACK_REQUIRED, bit1 LOOP,
//                        bit2 RESET_PIPELINE, bit3 ONE_SHOT
//   7  header_bytes      32
//   8  transaction_id    u32 little-endian
//   12 sequence          u32 little-endian
//   16 total_samples     u32 little-endian
//   20 sample_offset     u32 little-endian；ACK 中复用为 next_offset
//   24 sample_count      u16 little-endian；ACK 中复用为 status_code
//   26 sample_bits       24
//   27 sample_format     1 = signed little-endian
//   28 payload_crc32     u32 little-endian；对头后数据做反射式 CRC-32，
//                        初值/终值均为全 1 取反惯例
//
// WAVE_DATA 的头后紧随 sample_count 个三字节有符号小端样本，最多 256 个。
// 本模块只验证并输出事务描述符和数据字节；BRAM 写入、包序号去重、完整性
// 位图、COMMIT 原子换 bank 及 ACK 由后续事务控制器实现。
module dac24_upload_protocol_rx(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] payload_data,
    input  wire       payload_valid,
    input  wire       payload_last,
    input  wire       packet_start,
    input  wire [15:0] packet_length,

    output reg        header_valid,
    output reg        packet_error,
    output reg  [7:0] msg_type,
    output reg  [7:0] flags,
    output reg  [31:0] transaction_id,
    output reg  [31:0] sequence,
    output reg  [31:0] total_samples,
    output reg  [31:0] sample_offset,
    output reg  [15:0] sample_count,
    output reg  [31:0] payload_crc32,
    output reg  [7:0] body_data,
    output reg        body_valid,
    output reg        body_last
);
    localparam [7:0] VERSION = 8'd1;
    localparam [7:0] HEADER_BYTES = 8'd32;
    localparam [7:0] MSG_CONTROL = 8'h01;
    localparam [7:0] MSG_WAVE    = 8'h02;
    localparam [7:0] MSG_COMMIT  = 8'h03;

    reg        active;
    reg [15:0] byte_index;
    reg [15:0] body_received;
    reg [31:0] body_crc;
    reg        malformed;
    reg [7:0]  magic0, magic1, magic2, magic3;
    reg [7:0]  version_latched;
    reg [7:0]  header_bytes_latched;
    reg [7:0]  sample_bits;
    reg [7:0]  sample_format;
    wire [31:0] body_crc_next;
    wire [31:0] final_payload_crc =
        (byte_index >= HEADER_BYTES) ? ~body_crc_next : 32'd0;
    wire [15:0] final_body_count = body_received +
        ((byte_index >= HEADER_BYTES) ? 16'd1 : 16'd0);
    wire [15:0] final_sample_count =
        (byte_index == 16'd25) ? {payload_data, sample_count[7:0]} : sample_count;
    wire [31:0] final_header_payload_crc =
        (byte_index == 16'd31) ? {payload_data, payload_crc32[23:0]} : payload_crc32;
    wire [7:0] final_version =
        (byte_index == 16'd4) ? payload_data : version_latched;
    wire [7:0] final_msg_type =
        (byte_index == 16'd5) ? payload_data : msg_type;
    wire [7:0] final_header_bytes =
        (byte_index == 16'd7) ? payload_data : header_bytes_latched;
    wire [7:0] final_sample_bits =
        (byte_index == 16'd26) ? payload_data : sample_bits;
    wire [7:0] final_sample_format =
        (byte_index == 16'd27) ? payload_data : sample_format;
    wire [7:0] final_flags =
        (byte_index == 16'd6) ? payload_data : flags;

    ethernet_crc32 u_body_crc32 (
        .crc_in (body_crc),
        .data_in(payload_data),
        .crc_out(body_crc_next)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            header_valid         <= 1'b0;
            packet_error         <= 1'b0;
            msg_type             <= 8'd0;
            flags                <= 8'd0;
            transaction_id       <= 32'd0;
            sequence             <= 32'd0;
            total_samples        <= 32'd0;
            sample_offset        <= 32'd0;
            sample_count         <= 16'd0;
            payload_crc32        <= 32'd0;
            body_data            <= 8'd0;
            body_valid           <= 1'b0;
            body_last            <= 1'b0;
            active               <= 1'b0;
            byte_index           <= 16'd0;
            body_received        <= 16'd0;
            body_crc             <= 32'hFFFFFFFF;
            malformed            <= 1'b0;
            magic0               <= 8'd0;
            magic1               <= 8'd0;
            magic2               <= 8'd0;
            magic3               <= 8'd0;
            version_latched      <= 8'd0;
            header_bytes_latched <= 8'd0;
            sample_bits          <= 8'd0;
            sample_format        <= 8'd0;
        end else begin
            header_valid <= 1'b0;
            packet_error <= 1'b0;
            body_valid   <= 1'b0;
            body_last    <= 1'b0;

            if (packet_start) begin
                active               <= 1'b1;
                byte_index           <= 16'd0;
                body_received        <= 16'd0;
                body_crc             <= 32'hFFFFFFFF;
                malformed            <= (packet_length < HEADER_BYTES);
                magic0               <= 8'd0;
                magic1               <= 8'd0;
                magic2               <= 8'd0;
                magic3               <= 8'd0;
                version_latched      <= 8'd0;
                header_bytes_latched <= 8'd0;
                sample_bits          <= 8'd0;
                sample_format        <= 8'd0;
                msg_type             <= 8'd0;
                flags                <= 8'd0;
                transaction_id       <= 32'd0;
                sequence             <= 32'd0;
                total_samples        <= 32'd0;
                sample_offset        <= 32'd0;
                sample_count         <= 16'd0;
                payload_crc32        <= 32'd0;
            end

            if (active && payload_valid) begin
                byte_index <= byte_index + 16'd1;
                case (byte_index)
                    16'd0: magic0 <= payload_data;
                    16'd1: magic1 <= payload_data;
                    16'd2: magic2 <= payload_data;
                    16'd3: magic3 <= payload_data;
                    16'd4: version_latched <= payload_data;
                    16'd5: msg_type <= payload_data;
                    16'd6: flags <= payload_data;
                    16'd7: header_bytes_latched <= payload_data;
                    16'd8: transaction_id[7:0] <= payload_data;
                    16'd9: transaction_id[15:8] <= payload_data;
                    16'd10: transaction_id[23:16] <= payload_data;
                    16'd11: transaction_id[31:24] <= payload_data;
                    16'd12: sequence[7:0] <= payload_data;
                    16'd13: sequence[15:8] <= payload_data;
                    16'd14: sequence[23:16] <= payload_data;
                    16'd15: sequence[31:24] <= payload_data;
                    16'd16: total_samples[7:0] <= payload_data;
                    16'd17: total_samples[15:8] <= payload_data;
                    16'd18: total_samples[23:16] <= payload_data;
                    16'd19: total_samples[31:24] <= payload_data;
                    16'd20: sample_offset[7:0] <= payload_data;
                    16'd21: sample_offset[15:8] <= payload_data;
                    16'd22: sample_offset[23:16] <= payload_data;
                    16'd23: sample_offset[31:24] <= payload_data;
                    16'd24: sample_count[7:0] <= payload_data;
                    16'd25: sample_count[15:8] <= payload_data;
                    16'd26: sample_bits <= payload_data;
                    16'd27: sample_format <= payload_data;
                    16'd28: payload_crc32[7:0] <= payload_data;
                    16'd29: payload_crc32[15:8] <= payload_data;
                    16'd30: payload_crc32[23:16] <= payload_data;
                    16'd31: payload_crc32[31:24] <= payload_data;
                    default: begin
                        body_data     <= payload_data;
                        body_valid    <= 1'b1;
                        body_last     <= payload_last;
                        body_received <= body_received + 16'd1;
                        body_crc      <= body_crc_next;
                    end
                endcase

                if (payload_last) begin
                    active <= 1'b0;
                    if (malformed || (byte_index + 16'd1 != packet_length) ||
                        ({magic0, magic1, magic2,
                          (byte_index == 16'd3 ? payload_data : magic3)} !=
                         32'h44414355) ||
                        (final_version != VERSION) ||
                        (final_header_bytes != HEADER_BYTES) ||
                        ((final_flags & 8'hF0) != 8'd0) ||
                        ((final_msg_type != MSG_CONTROL) &&
                         (final_msg_type != MSG_WAVE) &&
                         (final_msg_type != MSG_COMMIT)) ||
                        ((final_msg_type == MSG_WAVE) &&
                         ((final_sample_bits != 8'd24) ||
                          (final_sample_format != 8'd1) ||
                         (final_sample_count > 16'd256) ||
                          (final_body_count != (final_sample_count * 16'd3)))) ||
                        ((final_msg_type != MSG_WAVE) &&
                         ((final_sample_count != 16'd0) ||
                          (final_sample_bits != 8'd24) ||
                          (final_sample_format != 8'd1))) ||
                        ((final_msg_type == MSG_CONTROL) &&
                         (final_body_count != 16'd8)) ||
                        ((final_msg_type == MSG_COMMIT) &&
                         (final_body_count != 16'd0)) ||
                        (final_header_payload_crc != final_payload_crc)) begin
                        packet_error <= 1'b1;
                    end else begin
                        header_valid <= 1'b1;
                    end
                end
            end
        end
    end
endmodule
