`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_phase7_folded_front3_bittrue.v
// 模块名       : tb_phase7_folded_front3_bittrue
// 功能简述     : Phase 7 折叠补偿方案前三个 2x 级位真测试。
//                从 24bit 原始冲激和随机 PCM 开始，同时运行
//                N=3/N=4 两套 Stage3 折叠系数，在 8x 调试节点
//                与 MATLAB 20bit golden 执行严格 0 LSB 比较。
//
// 当前默认配置：
//                  字长配置：24/22/20bit
//                  Stage3  ：11tap Q15 / 17bit
//                  固定启动延迟：7 个 Stage3 输出样点
//                  比较标准：所有有效样点误差 0 LSB
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-13
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-13：新增 N=3/N=4 折叠 Stage3 位真对拍。
//=============================================================

module tb_phase7_folded_front3_bittrue;

    localparam integer IMPULSE_INPUT_COUNT = 256;
    localparam integer RANDOM_INPUT_COUNT = 128;
    localparam integer IMPULSE_STAGE3_COUNT = 2499;
    localparam integer RANDOM_STAGE3_COUNT = 1475;
    localparam integer STAGE3_FIXED_SHIFT = 7;

    reg clk;
    reg rst_n;
    reg [6:0] ce_cnt;
    reg input_phase;
    reg signed [23:0] impulse_x;
    reg signed [23:0] random_x;
    reg signed [23:0] impulse_input_mem [0:IMPULSE_INPUT_COUNT-1];
    reg signed [23:0] random_input_mem [0:RANDOM_INPUT_COUNT-1];
    reg signed [19:0] n3_impulse_expected [0:IMPULSE_STAGE3_COUNT-1];
    reg signed [19:0] n4_impulse_expected [0:IMPULSE_STAGE3_COUNT-1];
    reg signed [19:0] n3_random_expected [0:RANDOM_STAGE3_COUNT-1];
    reg signed [19:0] n4_random_expected [0:RANDOM_STAGE3_COUNT-1];

    integer impulse_input_index;
    integer random_input_index;
    integer n3_impulse_index;
    integer n4_impulse_index;
    integer n3_random_index;
    integer n4_random_index;
    integer mismatch_count;

    wire ce2_out = (ce_cnt[5:0] == 6'b000000);
    wire ce4_out = (ce_cnt[4:0] == 5'b00000);
    wire ce8_out = (ce_cnt[3:0] == 4'b0000);
    wire ce16_out = (ce_cnt[2:0] == 3'b000);
    wire ce32_out = (ce_cnt[1:0] == 2'b00);
    wire ce64_out = (ce_cnt[0] == 1'b0);
    wire ce128_out = 1'b1;

    wire signed [23:0] n3_impulse_y8;
    wire n3_impulse_y8_valid;
    wire signed [23:0] n4_impulse_y8;
    wire n4_impulse_y8_valid;
    wire signed [23:0] n3_random_y8;
    wire n3_random_y8_valid;
    wire signed [23:0] n4_random_y8;
    wire n4_random_y8_valid;

    interp128_all2x_v7_folded_fir_cic_top_ce #(
        .CIC_ORDER(3), .FINAL_PRUNE_LSB(0)
    ) u_n3_impulse (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(impulse_x), .x_in_valid(1'b1),
        .y_out(), .y_out_valid(),
        .dbg_y2(), .dbg_y2_valid(), .dbg_y4(), .dbg_y4_valid(),
        .dbg_y8(n3_impulse_y8), .dbg_y8_valid(n3_impulse_y8_valid),
        .dbg_y16(), .dbg_y16_valid(), .dbg_y32(), .dbg_y32_valid(),
        .dbg_y64(), .dbg_y64_valid()
    );

    interp128_all2x_v7_folded_fir_cic_top_ce #(
        .CIC_ORDER(4), .FINAL_PRUNE_LSB(7)
    ) u_n4_impulse (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(impulse_x), .x_in_valid(1'b1),
        .y_out(), .y_out_valid(),
        .dbg_y2(), .dbg_y2_valid(), .dbg_y4(), .dbg_y4_valid(),
        .dbg_y8(n4_impulse_y8), .dbg_y8_valid(n4_impulse_y8_valid),
        .dbg_y16(), .dbg_y16_valid(), .dbg_y32(), .dbg_y32_valid(),
        .dbg_y64(), .dbg_y64_valid()
    );

    interp128_all2x_v7_folded_fir_cic_top_ce #(
        .CIC_ORDER(3), .FINAL_PRUNE_LSB(0)
    ) u_n3_random (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(random_x), .x_in_valid(1'b1),
        .y_out(), .y_out_valid(),
        .dbg_y2(), .dbg_y2_valid(), .dbg_y4(), .dbg_y4_valid(),
        .dbg_y8(n3_random_y8), .dbg_y8_valid(n3_random_y8_valid),
        .dbg_y16(), .dbg_y16_valid(), .dbg_y32(), .dbg_y32_valid(),
        .dbg_y64(), .dbg_y64_valid()
    );

    interp128_all2x_v7_folded_fir_cic_top_ce #(
        .CIC_ORDER(4), .FINAL_PRUNE_LSB(7)
    ) u_n4_random (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(random_x), .x_in_valid(1'b1),
        .y_out(), .y_out_valid(),
        .dbg_y2(), .dbg_y2_valid(), .dbg_y4(), .dbg_y4_valid(),
        .dbg_y8(n4_random_y8), .dbg_y8_valid(n4_random_y8_valid),
        .dbg_y16(), .dbg_y16_valid(), .dbg_y32(), .dbg_y32_valid(),
        .dbg_y64(), .dbg_y64_valid()
    );

    initial begin
        clk = 1'b0;
        forever #10.416667 clk = ~clk;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            ce_cnt <= 7'd0;
            input_phase <= 1'b1;
            impulse_x <= impulse_input_mem[0];
            random_x <= random_input_mem[0];
            impulse_input_index <= 0;
            random_input_index <= 0;
        end
        else begin
            ce_cnt <= ce_cnt + 7'd1;
            if (ce2_out) begin
                if (input_phase == 1'b0) begin
                    impulse_input_index <= impulse_input_index + 1;
                    random_input_index <= random_input_index + 1;
                    if (impulse_input_index + 1 < IMPULSE_INPUT_COUNT)
                        impulse_x <= impulse_input_mem[impulse_input_index + 1];
                    else
                        impulse_x <= 24'sd0;
                    if (random_input_index + 1 < RANDOM_INPUT_COUNT)
                        random_x <= random_input_mem[random_input_index + 1];
                    else
                        random_x <= 24'sd0;
                end
                input_phase <= ~input_phase;
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (n3_impulse_y8_valid)
                compare_stage3(n3_impulse_index, n3_impulse_y8,
                    n3_impulse_expected[n3_impulse_index-STAGE3_FIXED_SHIFT],
                    IMPULSE_STAGE3_COUNT, "N3 impulse");
            if (n4_impulse_y8_valid)
                compare_stage3(n4_impulse_index, n4_impulse_y8,
                    n4_impulse_expected[n4_impulse_index-STAGE3_FIXED_SHIFT],
                    IMPULSE_STAGE3_COUNT, "N4 impulse");
            if (n3_random_y8_valid)
                compare_stage3(n3_random_index, n3_random_y8,
                    n3_random_expected[n3_random_index-STAGE3_FIXED_SHIFT],
                    RANDOM_STAGE3_COUNT, "N3 random");
            if (n4_random_y8_valid)
                compare_stage3(n4_random_index, n4_random_y8,
                    n4_random_expected[n4_random_index-STAGE3_FIXED_SHIFT],
                    RANDOM_STAGE3_COUNT, "N4 random");

            if (n3_impulse_y8_valid)
                n3_impulse_index <= n3_impulse_index + 1;
            if (n4_impulse_y8_valid)
                n4_impulse_index <= n4_impulse_index + 1;
            if (n3_random_y8_valid)
                n3_random_index <= n3_random_index + 1;
            if (n4_random_y8_valid)
                n4_random_index <= n4_random_index + 1;
        end
    end

    task compare_stage3;
        input integer stream_index;
        input signed [23:0] actual_24;
        input signed [19:0] expected_20;
        input integer expected_count;
        input [8*16-1:0] stream_name;
        begin
            if (stream_index < STAGE3_FIXED_SHIFT) begin
                if (actual_24 !== 24'sd0) begin
                    mismatch_count = mismatch_count + 1;
                    $display("%0s nonzero before shift index=%0d",
                        stream_name, stream_index);
                end
            end
            else if (stream_index < STAGE3_FIXED_SHIFT + expected_count) begin
                if (actual_24[3:0] !== 4'b0000 ||
                        $signed(actual_24[23:4]) !== expected_20) begin
                    mismatch_count = mismatch_count + 1;
                    if (mismatch_count <= 20)
                        $display("%0s mismatch index=%0d actual=%0d expected=%0d",
                            stream_name, stream_index-STAGE3_FIXED_SHIFT,
                            $signed(actual_24[23:4]), expected_20);
                end
            end
        end
    endtask

    initial begin
        $readmemh("phase6_impulse_input_24bit.mem", impulse_input_mem);
        $readmemh("phase6_random_input_24bit.mem", random_input_mem);
        $readmemh("phase7_folded_n3_stage3_impulse_20bit.mem",
            n3_impulse_expected);
        $readmemh("phase7_folded_n4_stage3_impulse_20bit.mem",
            n4_impulse_expected);
        $readmemh("phase7_folded_n3_stage3_random_20bit.mem",
            n3_random_expected);
        $readmemh("phase7_folded_n4_stage3_random_20bit.mem",
            n4_random_expected);

        n3_impulse_index = 0;
        n4_impulse_index = 0;
        n3_random_index = 0;
        n4_random_index = 0;
        mismatch_count = 0;
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (50000) @(posedge clk);

        if (n3_impulse_index < STAGE3_FIXED_SHIFT + IMPULSE_STAGE3_COUNT ||
            n4_impulse_index < STAGE3_FIXED_SHIFT + IMPULSE_STAGE3_COUNT ||
            n3_random_index < STAGE3_FIXED_SHIFT + RANDOM_STAGE3_COUNT ||
            n4_random_index < STAGE3_FIXED_SHIFT + RANDOM_STAGE3_COUNT)
            $fatal(1, "Phase 7 folded Stage3 output count is insufficient");
        if (mismatch_count != 0)
            $fatal(1, "Phase 7 folded Stage3 mismatch count=%0d",
                mismatch_count);

        $display("PHASE7 FOLDED FRONT3 BITTRUE PASS: all streams = 0 LSB.");
        $finish;
    end

endmodule
