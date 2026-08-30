`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_capture_pingpong.v
// 模块名       : tb_capture_pingpong
// 功能简述     : 16384 点采集 BRAM 与 CDC 握手测试。验证帧描述符、读序、ACK 释放以及 COMMIT restart 后上传帧从索引 0 开始。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
module tb_capture_pingpong;
    reg audio_clk = 0;
    reg net_clk = 0;
    always #7 audio_clk = ~audio_clk;
    always #20 net_clk = ~net_clk;

    reg audio_rst_n = 0;
    reg net_rst_n = 0;
    reg signed [23:0] sample_data = 0;
    reg sample_valid = 0;
    reg capture_restart = 0;
    reg sample_upload_source = 0;
    reg [31:0] sample_transaction_id = 0;
    reg frame_take = 0;
    reg [3:0] frame_rd_addr = 0;
    wire frame_valid;
    wire [31:0] frame_id;
    wire [31:0] frame_start_sample_index;
    wire [1:0] frame_mode;
    wire frame_family;
    wire [23:0] frame_rd_data;
    integer i;

    dac24_capture_pingpong #(.ADDR_W(4), .DEPTH(16)) dut (
        .audio_clk(audio_clk), .audio_rst_n(audio_rst_n),
        .sample_data(sample_data), .sample_valid(sample_valid),
        .sample_index(i),
        .sample_mode(2'd2), .sample_family_48k(1'b1),
        .sample_upload_source(sample_upload_source),
        .sample_transaction_id(sample_transaction_id),
        .capture_restart(capture_restart),
        .net_clk(net_clk), .net_rst_n(net_rst_n),
        .frame_take(frame_take), .frame_valid(frame_valid),
        .frame_id(frame_id), .frame_mode(frame_mode),
        .frame_start_sample_index(frame_start_sample_index),
        .frame_family_48k(frame_family),
        .frame_upload_source(), .frame_transaction_id(),
        .capture_ready(),
        .frame_rd_addr(frame_rd_addr), .frame_rd_data(frame_rd_data)
    );

    initial begin
        #100; audio_rst_n=1; net_rst_n=1;
        @(negedge audio_clk); sample_valid=1;
        for (i=0; i<16; i=i+1) begin
            sample_data=i;
            @(negedge audio_clk);
        end
        sample_valid=0;
        wait(frame_valid);
        if (frame_id != 1 || frame_start_sample_index != 0 ||
            frame_mode != 2 || !frame_family)
            $fatal(1, "帧描述符不一致");
        for (i=0; i<16; i=i+1) begin
            frame_rd_addr=i;
            @(posedge net_clk); #1;
            if (frame_rd_data != i)
                $fatal(1, "样本 %0d：实际读到 %0d", i, frame_rd_data);
        end
        frame_take = ~frame_take;
        repeat (8) @(posedge net_clk);
        if (frame_valid) $fatal(1, "frame_valid 未清零");
        $display("通过：抓取 CDC、帧描述符及 BRAM 顺序完全正确");
        // COMMIT 边界回归：源/事务与 restart 同拍切换时，sample_index
        // 仍可能是复位前的旧值。该拍必须丢弃，下一拍的 index=0 才能
        // 成为新 UPLOAD RAM 帧的起点。
        @(negedge audio_clk);
        sample_valid = 1'b1;
        sample_upload_source = 1'b0;
        sample_transaction_id = 32'd0;
        i = 32'h02D4_B9E1;
        repeat (5) begin
            sample_data = i[23:0];
            i = i + 1;
            @(negedge audio_clk);
        end

        sample_upload_source = 1'b1;
        sample_transaction_id = 32'hCAFE_0001;
        capture_restart = 1'b1;
        i = 32'h02D4_B9E1;
        @(negedge audio_clk);
        capture_restart = 1'b0;

        for (i=0; i<16; i=i+1) begin
            sample_data = i + 24'h100;
            @(negedge audio_clk);
        end
        sample_valid = 1'b0;

        wait(frame_valid);
        if (frame_start_sample_index != 0 || !dut.frame_upload_source ||
            dut.frame_transaction_id != 32'hCAFE_0001)
            $fatal(1, "COMMIT restart first frame error: start=%0d source=%0d txid=%h",
                   frame_start_sample_index, dut.frame_upload_source,
                   dut.frame_transaction_id);
        $display("PASS: COMMIT restart starts uploaded capture at index zero");
        $finish;
    end
endmodule
