`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_cic_interp16_n3_hold_equiv.v
// 模块名       : tb_cic_interp16_n3_hold_equiv
// 功能简述     : 仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 设计说明     : 本文件采用同步时序设计；复位、时钟使能、
//                有效信号和定点位宽关系均在对应代码段说明。
//                注释仅用于阐明实现，不参与综合结果。
// 设计作者     : kafeizizi
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     : 2026-08-30：统一中文文件头、模块编号与结构说明。
//=============================================================

// Cycle-accurate comparison of the signed-off N3 serial-comb CIC and the
// exact comb^2 -> Hold16 -> integrator^2 rewrite.
//=============================================================
// 1）模块名称：tb_cic_interp16_n3_hold_equiv
// 功能说明：仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 工程版本：Vivado 2025.2。
//=============================================================
module tb_cic_interp16_n3_hold_equiv;

    localparam integer DATA_W = 21;
    localparam integer OUTPUT_W = 20;

    reg clk;
    reg rst_n;
    reg ce_out;
    reg signed [DATA_W-1:0] x_in;
    reg x_in_valid;

    wire signed [OUTPUT_W-1:0] y_legacy;
    wire legacy_valid;
    wire signed [OUTPUT_W-1:0] y_hold;
    wire hold_valid;
    wire signed [OUTPUT_W-1:0] y_hold_3dsp;
    wire hold_3dsp_valid;
    wire signed [OUTPUT_W-1:0] y_hold_2dsp;
    wire hold_2dsp_valid;

    integer random_seed;
    integer enabled_phase;
    integer input_count;
    integer output_count;
    integer mismatch_count;
    integer seed_index;

    // 例化说明：调用 cic_interp16_serial_comb_dsp_ce CIC/补偿子模块，完成高倍率插值或通带下垂校正。
    cic_interp16_serial_comb_dsp_ce #(
        .DATA_W(DATA_W),
        .OUTPUT_W(OUTPUT_W),
        .FINAL_PRUNE_LSB(0),
        .BURST_COUNTER_USE_DSP(0),
        .COMB_USE_DSP(0)
    ) u_legacy (
        .clk(clk),
        .rst_n(rst_n),
        .ce_out(ce_out),
        .x_in(x_in),
        .x_in_valid(x_in_valid),
        .y_out(y_legacy),
        .y_out_valid(legacy_valid),
        .burst_remaining_dbg(),
        .pending_dbg(),
        .comb_busy_dbg()
    );

    // 例化说明：调用 cic_interp16_n3_hold2_dsp_ce CIC/补偿子模块，完成高倍率插值或通带下垂校正。
    cic_interp16_n3_hold2_dsp_ce #(
        .DATA_W(DATA_W),
        .OUTPUT_W(OUTPUT_W),
        .FINAL_PRUNE_LSB(0),
        .BURST_COUNTER_USE_DSP(0),
        .INTEGRATOR_DSP_MODE(1)
    ) u_hold_3dsp (
        .clk(clk),
        .rst_n(rst_n),
        .ce_out(ce_out),
        .x_in(x_in),
        .x_in_valid(x_in_valid),
        .y_out(y_hold_3dsp),
        .y_out_valid(hold_3dsp_valid),
        .burst_remaining_dbg(),
        .pending_dbg(),
        .comb_busy_dbg()
    );

    // 例化说明：调用 cic_interp16_n3_hold2_dsp_ce CIC/补偿子模块，完成高倍率插值或通带下垂校正。
    cic_interp16_n3_hold2_dsp_ce #(
        .DATA_W(DATA_W),
        .OUTPUT_W(OUTPUT_W),
        .FINAL_PRUNE_LSB(0),
        .BURST_COUNTER_USE_DSP(0),
        .INTEGRATOR_DSP_MODE(0)
    ) u_hold_2dsp (
        .clk(clk),
        .rst_n(rst_n),
        .ce_out(ce_out),
        .x_in(x_in),
        .x_in_valid(x_in_valid),
        .y_out(y_hold_2dsp),
        .y_out_valid(hold_2dsp_valid),
        .burst_remaining_dbg(),
        .pending_dbg(),
        .comb_busy_dbg()
    );

    // 例化说明：调用 cic_interp16_n3_hold2_dsp_ce CIC/补偿子模块，完成高倍率插值或通带下垂校正。
    cic_interp16_n3_hold2_dsp_ce #(
        .DATA_W(DATA_W),
        .OUTPUT_W(OUTPUT_W),
        .FINAL_PRUNE_LSB(0),
        .BURST_COUNTER_USE_DSP(0)
    ) u_hold (
        .clk(clk),
        .rst_n(rst_n),
        .ce_out(ce_out),
        .x_in(x_in),
        .x_in_valid(x_in_valid),
        .y_out(y_hold),
        .y_out_valid(hold_valid),
        .burst_remaining_dbg(),
        .pending_dbg(),
        .comb_busy_dbg()
    );

    always #5 clk = ~clk;

    always @(negedge clk) begin
        if (!rst_n) begin
            output_count = 0;
            mismatch_count = 0;
        end
        else begin
            if (legacy_valid !== hold_valid ||
                legacy_valid !== hold_3dsp_valid ||
                legacy_valid !== hold_2dsp_valid)
                $fatal(1, "N3 Hold valid mismatch legacy=%b dsp4=%b dsp3=%b dsp2=%b",
                       legacy_valid, hold_valid, hold_3dsp_valid,
                       hold_2dsp_valid);
            if (legacy_valid) begin
                if (y_legacy !== y_hold || y_legacy !== y_hold_3dsp ||
                    y_legacy !== y_hold_2dsp) begin
                    mismatch_count = mismatch_count + 1;
                    $display("N3 Hold mismatch output=%0d legacy=%0d dsp4=%0d dsp3=%0d dsp2=%0d legacy_comb=%0d hold_sample=%0d legacy_i0=%0d legacy_i1=%0d hold_i0=%0d legacy_final=%0d hold_final=%0d",
                             output_count, y_legacy, y_hold, y_hold_3dsp,
                             y_hold_2dsp,
                             u_legacy.comb_operand, u_hold.hold_sample,
                             u_legacy.integrator_state[0],
                             u_legacy.integrator_state[1],
                             u_hold.integrator_state,
                             u_legacy.final_integrator_state,
                             u_hold.final_integrator_state);
                    if (mismatch_count >= 8)
                        $fatal(1, "Too many N3 Hold mismatches");
                end
                output_count = output_count + 1;
            end
        end
    end

    task choose_sample;
        input integer sample_index;
        begin
            if (sample_index == 0)
                x_in = 21'sd256;
            else if (sample_index < 8)
                x_in = 21'sd0;
            else case (sample_index & 15)
                0: x_in = 21'sh0fffff;
                1: x_in = -21'sd1048576;
                2: x_in = 21'sd0;
                3: x_in = 21'sd1;
                4: x_in = -21'sd1;
                5: x_in = 21'sh055555;
                6: x_in = -21'sd349525;
                default: x_in = $random(random_seed);
            endcase
        end
    endtask

    task stream_inputs;
        input integer number_of_inputs;
        input integer insert_ce_stalls;
        begin
            input_count = 0;
            enabled_phase = 15;
            while (input_count < number_of_inputs) begin
                @(negedge clk);
                x_in_valid = 1'b0;
                if (insert_ce_stalls)
                    ce_out = (($random(random_seed) & 32'h7) != 0);
                else
                    ce_out = 1'b1;

                if (ce_out) begin
                    if (enabled_phase == 15) begin
                        choose_sample(input_count);
                        x_in_valid = 1'b1;
                        input_count = input_count + 1;
                        enabled_phase = 0;
                    end
                    else begin
                        enabled_phase = enabled_phase + 1;
                    end
                end
            end
        end
    endtask

    task drain_and_check;
        input integer expected_inputs;
        integer drain_index;
        begin
            for (drain_index = 0; drain_index < 48;
                 drain_index = drain_index + 1) begin
                @(negedge clk);
                x_in_valid = 1'b0;
                ce_out = 1'b1;
            end
            @(negedge clk);
            if (mismatch_count != 0)
                $fatal(1, "N3 Hold mismatch count=%0d", mismatch_count);
            if (output_count != expected_inputs*16)
                $fatal(1, "N3 Hold output count=%0d expected=%0d",
                       output_count, expected_inputs*16);
        end
    endtask

    task pulse_reset;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            x_in_valid = 1'b0;
            ce_out = 1'b0;
            repeat (3) @(negedge clk);
            rst_n = 1'b1;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        ce_out = 1'b0;
        x_in = {DATA_W{1'b0}};
        x_in_valid = 1'b0;
        random_seed = 32'h4a91_c35d;

        // Explicit DSP48E1 validation runs with the UNISIM glbl model.  Keep
        // reset asserted beyond its 100 ns configuration GSR interval so the
        // first accepted comb sample cannot be discarded by startup reset.
        repeat (12) @(negedge clk);
        rst_n = 1'b1;

        // Reset inside an active hold/burst epoch.
        stream_inputs(25, 0);
        @(negedge clk);
        x_in_valid = 1'b0;
        ce_out = 1'b1;
        repeat (7) @(negedge clk);
        if (!legacy_valid || !hold_valid)
            $fatal(1, "N3 Hold reset did not land inside a burst");
        rst_n = 1'b0;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        stream_inputs(320, 0);
        drain_and_check(320);

        pulse_reset();

        stream_inputs(480, 1);
        drain_and_check(480);

        // Ten independent random seeds exercise both CE stalls and signed
        // full-scale endpoints against the original 33-bit implementation.
        for (seed_index = 0; seed_index < 10;
             seed_index = seed_index + 1) begin
            pulse_reset();
            random_seed = 32'h1357_9bdf ^ (seed_index * 32'h1020_4081);
            stream_inputs(256, 1);
            drain_and_check(256);
        end

        $display("N3 HOLD CIC EQUIVALENCE PASS: narrow 26/29-bit states, DSP modes 2/1/0, continuous=320 stalled=480 seeds=10x256 reset-mid-burst=PASS outputs=%0d",
                 output_count);
        $finish;
    end

endmodule
