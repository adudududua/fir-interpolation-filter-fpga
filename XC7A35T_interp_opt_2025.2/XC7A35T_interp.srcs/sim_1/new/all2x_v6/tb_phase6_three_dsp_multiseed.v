`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_phase6_three_dsp_multiseed.v
// 模块名       : tb_phase6_three_dsp_multiseed
// 功能简述     : Phase 6 三 DSP 候选链多种子逐级 bit-true 测试。
//                同时驱动 Phase 5 两 DSP 参考链和 Phase 6 三 DSP
//                候选链，在 Stage 2、Stage 3 和完整 128x 输出处
//                按有效样点流逐点比较。
//
//                测试覆盖：
//                  1. 24bit 最大值、最小值、零和正负小量；
//                  2. 5 组确定性 LFSR 随机满幅 PCM；
//                  3. valid=0 的输入零样点；
//                  4. 输出样点数和所有数据均要求完全一致。
//
// 当前默认配置：
//                  输入样点数：640
//                  比较标准  ：所有节点最大误差 0 LSB
//                  主时钟周期：10ns，仅用于加速功能仿真
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-13
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-13：新增 Phase 6 三 DSP 多种子测试。
//=============================================================
//=============================================================
// 1）模块名称：tb_phase6_three_dsp_multiseed
// 功能说明：仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 工程版本：Vivado 2025.2。
//=============================================================

module tb_phase6_three_dsp_multiseed;

    localparam integer INPUT_COUNT = 640;
    localparam integer FLUSH_CYCLES = 40000;

    reg clk;
    reg rst_n;
    reg [6:0] ce_cnt;
    reg input_phase;
    reg signed [23:0] x_in;
    reg x_in_valid;
    reg [31:0] lfsr;

    integer input_count;
    integer ref_stage2_count;
    integer dut_stage2_count;
    integer ref_stage3_count;
    integer dut_stage3_count;
    integer ref_full_count;
    integer dut_full_count;
    integer check_index;

    reg signed [23:0] ref_stage2_stream [0:8191];
    reg signed [23:0] dut_stage2_stream [0:8191];
    reg signed [23:0] ref_stage3_stream [0:16383];
    reg signed [23:0] dut_stage3_stream [0:16383];
    reg signed [23:0] ref_full_stream [0:131071];
    reg signed [23:0] dut_full_stream [0:131071];

    wire ce2_out = (ce_cnt[5:0] == 6'b000000);
    wire ce4_out = (ce_cnt[4:0] == 5'b00000);
    wire ce8_out = (ce_cnt[3:0] == 4'b0000);
    wire ce16_out = (ce_cnt[2:0] == 3'b000);
    wire ce32_out = (ce_cnt[1:0] == 2'b00);
    wire ce64_out = (ce_cnt[0] == 1'b0);
    wire ce128_out = 1'b1;

    wire signed [23:0] ref_y4;
    wire signed [23:0] ref_y8;
    wire signed [23:0] ref_y128;
    wire ref_y4_valid;
    wire ref_y8_valid;
    wire ref_y128_valid;
    wire signed [23:0] dut_y4;
    wire signed [23:0] dut_y8;
    wire signed [23:0] dut_y128;
    wire dut_y4_valid;
    wire dut_y8_valid;
    wire dut_y128_valid;

    function [31:0] next_lfsr;
        input [31:0] value;
        begin
            next_lfsr = {value[30:0],
                         value[31] ^ value[21] ^ value[1] ^ value[0]};
        end
    endfunction

    function signed [23:0] next_sample;
        input integer index;
        input [31:0] random_value;
        begin
            case (index)
                0: next_sample = 24'sh7fffff;
                1: next_sample = -24'sh800000;
                2: next_sample = 24'sd0;
                3: next_sample = 24'sd1;
                4: next_sample = -24'sd1;
                5: next_sample = 24'sh555555;
                6: next_sample = -24'sh555555;
                7: next_sample = 24'sh400000;
                default: next_sample = random_value[23:0];
            endcase
        end
    endfunction

    function [31:0] seed_for_block;
        input integer block_index;
        begin
            case (block_index)
                0: seed_for_block = 32'h13579bdf;
                1: seed_for_block = 32'h2468ace1;
                2: seed_for_block = 32'hdeadbeef;
                3: seed_for_block = 32'h10203041;
                default: seed_for_block = 32'h89abcdef;
            endcase
        end
    endfunction

    // 例化说明：调用 interp128_all2x_v4_shared_dsp_top_ce 插值链顶层，完成所选倍率的数据率提升与有效信号传递。
    interp128_all2x_v4_shared_dsp_top_ce #(
        .STAGE23_ACC_W (40)
    ) u_reference (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(ref_y128), .y_out_valid(ref_y128_valid),
        .dbg_y2(), .dbg_y2_valid(),
        .dbg_y4(ref_y4), .dbg_y4_valid(ref_y4_valid),
        .dbg_y8(ref_y8), .dbg_y8_valid(ref_y8_valid),
        .dbg_y16(), .dbg_y16_valid(),
        .dbg_y32(), .dbg_y32_valid(),
        .dbg_y64(), .dbg_y64_valid()
    );

    // 例化说明：调用 interp128_all2x_v6_three_dsp_top_ce 插值链顶层，完成所选倍率的数据率提升与有效信号传递。
    interp128_all2x_v6_three_dsp_top_ce #(
        .STAGE23_ACC_W (40)
    ) u_candidate (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(dut_y128), .y_out_valid(dut_y128_valid),
        .dbg_y2(), .dbg_y2_valid(),
        .dbg_y4(dut_y4), .dbg_y4_valid(dut_y4_valid),
        .dbg_y8(dut_y8), .dbg_y8_valid(dut_y8_valid),
        .dbg_y16(), .dbg_y16_valid(),
        .dbg_y32(), .dbg_y32_valid(),
        .dbg_y64(), .dbg_y64_valid()
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            ce_cnt <= 7'd0;
            input_phase <= 1'b1;
            input_count <= 0;
            x_in <= 24'sh7fffff;
            x_in_valid <= 1'b1;
            lfsr <= 32'h13579bdf;
        end
        else begin
            ce_cnt <= ce_cnt + 7'd1;
            if (ce2_out) begin
                if (input_phase == 1'b0 && input_count < INPUT_COUNT) begin
                    input_count <= input_count + 1;
                    if (((input_count + 1) % 128) == 0)
                        lfsr <= seed_for_block((input_count + 1) / 128);
                    else
                        lfsr <= next_lfsr(lfsr);
                    x_in <= next_sample(input_count + 1, next_lfsr(lfsr));
                    x_in_valid <= ((next_lfsr(lfsr) & 32'h1f) != 0);
                end
                else if (input_phase == 1'b0) begin
                    x_in <= 24'sd0;
                    x_in_valid <= 1'b1;
                end
                input_phase <= ~input_phase;
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (ref_y4_valid) begin
                ref_stage2_stream[ref_stage2_count] <= ref_y4;
                ref_stage2_count <= ref_stage2_count + 1;
            end
            if (dut_y4_valid) begin
                dut_stage2_stream[dut_stage2_count] <= dut_y4;
                dut_stage2_count <= dut_stage2_count + 1;
            end
            if (ref_y8_valid) begin
                ref_stage3_stream[ref_stage3_count] <= ref_y8;
                ref_stage3_count <= ref_stage3_count + 1;
            end
            if (dut_y8_valid) begin
                dut_stage3_stream[dut_stage3_count] <= dut_y8;
                dut_stage3_count <= dut_stage3_count + 1;
            end
            if (ref_y128_valid) begin
                ref_full_stream[ref_full_count] <= ref_y128;
                ref_full_count <= ref_full_count + 1;
            end
            if (dut_y128_valid) begin
                dut_full_stream[dut_full_count] <= dut_y128;
                dut_full_count <= dut_full_count + 1;
            end
        end
    end

    initial begin
        rst_n = 1'b0;
        ref_stage2_count = 0;
        dut_stage2_count = 0;
        ref_stage3_count = 0;
        dut_stage3_count = 0;
        ref_full_count = 0;
        dut_full_count = 0;
        repeat (20) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        wait (input_count == INPUT_COUNT);
        repeat (FLUSH_CYCLES) @(posedge clk);

        if (ref_stage2_count == 0 || ref_stage3_count == 0 ||
            ref_full_count == 0)
            $fatal(1, "Phase 6 multiseed test produced no output");

        if (ref_stage2_count != dut_stage2_count)
            $fatal(1, "Stage 2 count mismatch: ref=%0d dut=%0d",
                   ref_stage2_count, dut_stage2_count);
        if (ref_stage3_count != dut_stage3_count)
            $fatal(1, "Stage 3 count mismatch: ref=%0d dut=%0d",
                   ref_stage3_count, dut_stage3_count);
        if (ref_full_count != dut_full_count)
            $fatal(1, "Full count mismatch: ref=%0d dut=%0d",
                   ref_full_count, dut_full_count);

        for (check_index = 0; check_index < ref_stage2_count;
             check_index = check_index + 1)
            if (ref_stage2_stream[check_index] !==
                dut_stage2_stream[check_index])
                $fatal(1, "Stage 2 mismatch index=%0d ref=%0d dut=%0d",
                       check_index, ref_stage2_stream[check_index],
                       dut_stage2_stream[check_index]);

        for (check_index = 0; check_index < ref_stage3_count;
             check_index = check_index + 1)
            if (ref_stage3_stream[check_index] !==
                dut_stage3_stream[check_index])
                $fatal(1, "Stage 3 mismatch index=%0d ref=%0d dut=%0d",
                       check_index, ref_stage3_stream[check_index],
                       dut_stage3_stream[check_index]);

        for (check_index = 0; check_index < ref_full_count;
             check_index = check_index + 1)
            if (ref_full_stream[check_index] !== dut_full_stream[check_index])
                $fatal(1, "Full mismatch index=%0d ref=%0d dut=%0d",
                       check_index, ref_full_stream[check_index],
                       dut_full_stream[check_index]);

        $display("PASS: Phase 6 three-DSP multiseed bit-true test");
        $display("inputs=%0d stage2=%0d stage3=%0d full=%0d",
                 input_count, ref_stage2_count, ref_stage3_count,
                 ref_full_count);
        $finish;
    end

endmodule

