`timescale 1ns / 1ps
//=============================================================
// 文件名       : tb_ila_image_rejection_demo.v
// 模块名       : tb_ila_image_rejection_demo
// 功能简述     : 验证 4.1kHz+15kHz 演示源、板级真实第一级
//                2x FIR 以及 15kHz/40kHz 固定频点检测结果。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-19
// 版本         : V2018.3
// 开发工具     : Vivado Simulator
// 修订记录     :
//                2026-07-19：新增 ILA 镜像抑制端到端验证。
//=============================================================

module tb_ila_image_rejection_demo;

    reg clk_audio_128x = 1'b0;
    reg rst_n = 1'b0;
    reg ila_demo_enable = 1'b0;

    reg [6:0] ce_cnt = 7'd0;
    wire ce2_out;
    wire input_sample_ce;
    wire signed [23:0] source_sample;
    wire source_sample_update;
    wire [8:0] source_index_unused;
    wire signed [23:0] stage1_output;
    wire stage1_output_valid;
    wire stage1_phase_unused;
    wire signed [23:0] stage1_fir_input;
    wire stage1_fir_input_valid;
    reg signed [23:0] pre2_hold;
    wire [15:0] magnitude_15k_pre;
    wire [15:0] magnitude_15k_post;
    wire [15:0] magnitude_40k_pre;
    wire [15:0] magnitude_40k_post;
    wire [7:0] suppression_40k_db;
    wire measurement_valid;

    integer timeout_cycles;

    // 5.6448MHz，周期约 177.154ns。
    always #88.5771 clk_audio_128x = ~clk_audio_128x;

    assign ce2_out = (ce_cnt[5:0] == 6'd0);
    assign input_sample_ce = (ce_cnt == 7'd127);

    always @(posedge clk_audio_128x) begin
        if (!rst_n)
            ce_cnt <= 7'd0;
        else
            ce_cnt <= ce_cnt + 7'd1;
    end

    ila_demo_multitone_source u_source (
        .clk(clk_audio_128x),
        .rst_n(rst_n),
        .enable(ila_demo_enable),
        .sample_ce(input_sample_ce),
        .sample_out(source_sample),
        .sample_update(source_sample_update),
        .sample_index_dbg(source_index_unused)
    );

    interp2_stage1_strict_halfband_bram_ce u_stage1 (
        .clk(clk_audio_128x),
        .rst_n(rst_n),
        .ce_out(ce2_out),
        .x_in(source_sample),
        .x_in_valid(1'b1),
        .y_out(stage1_output),
        .y_out_valid(stage1_output_valid),
        .phase_dbg(stage1_phase_unused),
        .fir_in_dbg(stage1_fir_input),
        .fir_in_valid_dbg(stage1_fir_input_valid)
    );

    always @(posedge clk_audio_128x) begin
        if (!rst_n)
            pre2_hold <= 24'sd0;
        else if (ce2_out)
            pre2_hold <= stage1_fir_input_valid ? stage1_fir_input : 24'sd0;
    end

    ila_image_rejection_monitor #(
        // 真实硬件使用 2048/882；仿真用 64/441 缩短运行，
        // 441 点对 15kHz 和 40kHz 参考仍为整数周期。
        .WARMUP_SAMPLES(64),
        .BLOCK_SAMPLES(441)
    ) u_monitor (
        .clk(clk_audio_128x),
        .rst_n(rst_n),
        .enable(ila_demo_enable),
        .sample_ce(stage1_output_valid),
        .sample_pre(pre2_hold),
        .sample_post(stage1_output),
        .magnitude_15k_pre(magnitude_15k_pre),
        .magnitude_15k_post(magnitude_15k_post),
        .magnitude_40k_pre(magnitude_40k_pre),
        .magnitude_40k_post(magnitude_40k_post),
        .suppression_40k_db(suppression_40k_db),
        .measurement_valid(measurement_valid),
        .result_strobe()
    );

    initial begin
        repeat (20) @(posedge clk_audio_128x);
        rst_n <= 1'b1;
        repeat (20) @(posedge clk_audio_128x);
        ila_demo_enable <= 1'b1;

        timeout_cycles = 0;
        while (!measurement_valid && timeout_cycles < 80000) begin
            @(posedge clk_audio_128x);
            timeout_cycles = timeout_cycles + 1;
        end

        if (!measurement_valid)
            $fatal(1, "ILA demo monitor timeout");

        $display("ILA_DEMO_RESULT 15k_pre=%0d 15k_post=%0d 40k_pre=%0d 40k_post=%0d suppression=%0d dB",
                 magnitude_15k_pre, magnitude_15k_post,
                 magnitude_40k_pre, magnitude_40k_post,
                 suppression_40k_db);

        if (magnitude_15k_pre < 16'd1000)
            $fatal(1, "15kHz PRE magnitude is unexpectedly small");
        if (magnitude_15k_post < 16'd1000)
            $fatal(1, "15kHz POST magnitude is unexpectedly small");
        if (magnitude_40k_pre < 16'd1000)
            $fatal(1, "40kHz PRE image was not detected");
        if (magnitude_40k_post >= magnitude_40k_pre)
            $fatal(1, "40kHz image was not attenuated");
        if (suppression_40k_db < 8'd24)
            $fatal(1, "40kHz suppression is below 24dB");

        // 退出演示后固定频点结果应复位，原可调 NCO 数据路恢复。
        ila_demo_enable <= 1'b0;
        repeat (4) @(posedge clk_audio_128x);
        if (measurement_valid !== 1'b0)
            $fatal(1, "Measurement valid did not clear after demo exit");

        $display("PASS: coherent 15kHz passband and 40kHz image rejection verified");
        $finish;
    end

endmodule
