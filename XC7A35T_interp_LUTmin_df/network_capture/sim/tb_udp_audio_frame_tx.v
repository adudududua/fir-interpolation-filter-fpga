`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_udp_audio_frame_tx.v
// 模块名       : tb_udp_audio_frame_tx
// 功能简述     : DAC2 回传帧测试。生成 64 个包并核对应用头、16384 点顺序、IPv4 校验和、FCS、ACK 后不重复发送。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
module tb_udp_audio_frame_tx;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #20 clk = ~clk;

    reg capture_valid = 1'b0;
    wire capture_take;
    reg capture_take_seen = 1'b0;
    wire [13:0] rd_addr;
    reg [23:0] rd_data = 24'd0;
    wire [7:0] tx_data;
    wire tx_valid;
    wire tx_last;
    integer out_file;
    integer packet_done = 0;
    integer i;
    reg [23:0] memory [0:16383];

    always @(posedge clk)
        rd_data <= memory[rd_addr];

    udp_audio_frame_tx #(.FRAME_GAP_CYCLES(4)) dut (
        .clk(clk), .rst_n(rst_n),
        .capture_valid(capture_valid),
        .capture_frame_id(32'h12345678),
        .capture_start_sample_index(32'h11223344),
        .capture_mode(2'd3),
        .capture_family_48k(1'b1),
        .capture_upload_source(1'b0),
        .capture_transaction_id(32'd0),
        .capture_take(capture_take),
        .capture_rd_addr(rd_addr),
        .capture_rd_data(rd_data),
        .tx_data(tx_data), .tx_valid(tx_valid),
        .tx_ready(1'b1), .tx_last(tx_last)
    );

    always @(posedge clk) begin
        if (capture_take != capture_take_seen) begin
            capture_take_seen <= capture_take;
            capture_valid <= 1'b0;
        end
        if (tx_valid) begin
            $fwrite(out_file, "%c", tx_data);
            if (tx_last)
                packet_done <= packet_done + 1;
        end
    end

    initial begin
        for (i = 0; i < 16384; i = i + 1)
            memory[i] = i[23:0];
        out_file = $fopen("network_capture/results/tx_frames.bin", "wb");
        #200;
        rst_n = 1'b1;
        #80;
        capture_valid = 1'b1;
        wait(packet_done == 64);
        repeat (12) @(posedge clk);
        if (packet_done != 64 || tx_valid)
            $fatal(1, "确认应答后又重复发送了旧抓取帧");
        $fclose(out_file);
        $display("通过：已发送 64 个以太网帧");
        $finish;
    end

    initial begin
        #5000000;
        $fatal(1, "仿真超时");
    end
endmodule
