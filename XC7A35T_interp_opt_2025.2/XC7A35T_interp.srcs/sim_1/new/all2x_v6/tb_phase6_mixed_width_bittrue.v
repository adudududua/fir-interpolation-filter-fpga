`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_phase6_mixed_width_bittrue.v
// 模块名       : tb_phase6_mixed_width_bittrue
// 功能简述     : Phase 6 混合字长七级链 RTL bit-true 测试。
//                对冲激和随机 PCM 并行仿真，在 Stage 2、Stage 3
//                和完整 128x 输出处直接与 MATLAB golden 比较。
//                级联 RTL 每经过一级会引入 1 个本级输出样点的
//                固定启动延迟，因此 Stage 2、Stage 3 和完整链
//                分别使用固定 shift=3、7、127，不搜索最佳延迟。
//
// 当前默认配置：
//                  字长配置：24/22/20/18/18/18/18bit
//                  冲激输入：256 点
//                  随机输入：128 点
//                  比较标准：所有有效样点误差 0 LSB
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-13
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-13：新增混合字长冲激/随机 RTL 对拍。
//=============================================================
//=============================================================
// 1）模块名称：tb_phase6_mixed_width_bittrue
// 功能说明：仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 工程版本：Vivado 2025.2。
//=============================================================

module tb_phase6_mixed_width_bittrue;

    localparam integer IMPULSE_INPUT_COUNT = 256;
    localparam integer RANDOM_INPUT_COUNT = 128;
    localparam integer IMPULSE_STAGE2_COUNT = 1245;
    localparam integer RANDOM_STAGE2_COUNT = 733;
    localparam integer IMPULSE_STAGE3_COUNT = 2499;
    localparam integer RANDOM_STAGE3_COUNT = 1475;
    localparam integer IMPULSE_FULL_COUNT = 40059;
    localparam integer RANDOM_FULL_COUNT = 23675;
    localparam integer STAGE2_FIXED_SHIFT = 3;
    localparam integer STAGE3_FIXED_SHIFT = 7;
    localparam integer FULL_FIXED_SHIFT = 127;

    reg clk;
    reg rst_n;
    reg [6:0] ce_cnt;
    reg input_phase;
    reg signed [23:0] impulse_x;
    reg signed [23:0] random_x;
    reg signed [23:0] impulse_input_mem [0:IMPULSE_INPUT_COUNT-1];
    reg signed [23:0] random_input_mem [0:RANDOM_INPUT_COUNT-1];
    reg signed [23:0] impulse_stage2_golden [0:IMPULSE_STAGE2_COUNT-1];
    reg signed [23:0] random_stage2_golden [0:RANDOM_STAGE2_COUNT-1];
    reg signed [23:0] impulse_stage3_golden [0:IMPULSE_STAGE3_COUNT-1];
    reg signed [23:0] random_stage3_golden [0:RANDOM_STAGE3_COUNT-1];
    reg signed [23:0] impulse_full_golden [0:IMPULSE_FULL_COUNT-1];
    reg signed [23:0] random_full_golden [0:RANDOM_FULL_COUNT-1];

    integer impulse_input_index;
    integer random_input_index;
    integer impulse_stage2_index;
    integer random_stage2_index;
    integer impulse_stage3_index;
    integer random_stage3_index;
    integer impulse_full_index;
    integer random_full_index;

    wire ce2_out = (ce_cnt[5:0] == 6'b000000);
    wire ce4_out = (ce_cnt[4:0] == 5'b00000);
    wire ce8_out = (ce_cnt[3:0] == 4'b0000);
    wire ce16_out = (ce_cnt[2:0] == 3'b000);
    wire ce32_out = (ce_cnt[1:0] == 2'b00);
    wire ce64_out = (ce_cnt[0] == 1'b0);
    wire ce128_out = 1'b1;

    wire signed [23:0] impulse_y4;
    wire signed [23:0] impulse_y8;
    wire signed [23:0] impulse_y128;
    wire impulse_y4_valid;
    wire impulse_y8_valid;
    wire impulse_y128_valid;
    wire signed [23:0] random_y4;
    wire signed [23:0] random_y8;
    wire signed [23:0] random_y128;
    wire random_y4_valid;
    wire random_y8_valid;
    wire random_y128_valid;

    // 例化说明：调用 interp128_all2x_v6_mixed_width_top_ce 插值链顶层，完成所选倍率的数据率提升与有效信号传递。
    interp128_all2x_v6_mixed_width_top_ce u_impulse (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(impulse_x), .x_in_valid(1'b1),
        .y_out(impulse_y128), .y_out_valid(impulse_y128_valid),
        .dbg_y2(), .dbg_y2_valid(),
        .dbg_y4(impulse_y4), .dbg_y4_valid(impulse_y4_valid),
        .dbg_y8(impulse_y8), .dbg_y8_valid(impulse_y8_valid),
        .dbg_y16(), .dbg_y16_valid(),
        .dbg_y32(), .dbg_y32_valid(),
        .dbg_y64(), .dbg_y64_valid()
    );

    // 例化说明：调用 interp128_all2x_v6_mixed_width_top_ce 插值链顶层，完成所选倍率的数据率提升与有效信号传递。
    interp128_all2x_v6_mixed_width_top_ce u_random (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(random_x), .x_in_valid(1'b1),
        .y_out(random_y128), .y_out_valid(random_y128_valid),
        .dbg_y2(), .dbg_y2_valid(),
        .dbg_y4(random_y4), .dbg_y4_valid(random_y4_valid),
        .dbg_y8(random_y8), .dbg_y8_valid(random_y8_valid),
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
            if (impulse_y4_valid) begin
                if (impulse_stage2_index < STAGE2_FIXED_SHIFT) begin
                    if (impulse_y4 !== 24'sd0)
                        $fatal(1, "impulse Stage2 nonzero before fixed shift");
                end
                else if (impulse_stage2_index <
                         STAGE2_FIXED_SHIFT + IMPULSE_STAGE2_COUNT &&
                    impulse_y4 !== impulse_stage2_golden[
                        impulse_stage2_index-STAGE2_FIXED_SHIFT])
                    $fatal(1, "impulse Stage2 mismatch index=%0d ref=%0d dut=%0d",
                           impulse_stage2_index-STAGE2_FIXED_SHIFT,
                           impulse_stage2_golden[
                               impulse_stage2_index-STAGE2_FIXED_SHIFT],
                           impulse_y4);
                impulse_stage2_index <= impulse_stage2_index + 1;
            end
            if (random_y4_valid) begin
                if (random_stage2_index < STAGE2_FIXED_SHIFT) begin
                    if (random_y4 !== 24'sd0)
                        $fatal(1, "random Stage2 nonzero before fixed shift");
                end
                else if (random_stage2_index <
                         STAGE2_FIXED_SHIFT + RANDOM_STAGE2_COUNT &&
                    random_y4 !== random_stage2_golden[
                        random_stage2_index-STAGE2_FIXED_SHIFT])
                    $fatal(1, "random Stage2 mismatch index=%0d ref=%0d dut=%0d",
                           random_stage2_index-STAGE2_FIXED_SHIFT,
                           random_stage2_golden[
                               random_stage2_index-STAGE2_FIXED_SHIFT],
                           random_y4);
                random_stage2_index <= random_stage2_index + 1;
            end
            if (impulse_y8_valid) begin
                if (impulse_stage3_index < STAGE3_FIXED_SHIFT) begin
                    if (impulse_y8 !== 24'sd0)
                        $fatal(1, "impulse Stage3 nonzero before fixed shift");
                end
                else if (impulse_stage3_index <
                         STAGE3_FIXED_SHIFT + IMPULSE_STAGE3_COUNT &&
                    impulse_y8 !== impulse_stage3_golden[
                        impulse_stage3_index-STAGE3_FIXED_SHIFT])
                    $fatal(1, "impulse Stage3 mismatch index=%0d ref=%0d dut=%0d",
                           impulse_stage3_index-STAGE3_FIXED_SHIFT,
                           impulse_stage3_golden[
                               impulse_stage3_index-STAGE3_FIXED_SHIFT],
                           impulse_y8);
                impulse_stage3_index <= impulse_stage3_index + 1;
            end
            if (random_y8_valid) begin
                if (random_stage3_index < STAGE3_FIXED_SHIFT) begin
                    if (random_y8 !== 24'sd0)
                        $fatal(1, "random Stage3 nonzero before fixed shift");
                end
                else if (random_stage3_index <
                         STAGE3_FIXED_SHIFT + RANDOM_STAGE3_COUNT &&
                    random_y8 !== random_stage3_golden[
                        random_stage3_index-STAGE3_FIXED_SHIFT])
                    $fatal(1, "random Stage3 mismatch index=%0d ref=%0d dut=%0d",
                           random_stage3_index-STAGE3_FIXED_SHIFT,
                           random_stage3_golden[
                               random_stage3_index-STAGE3_FIXED_SHIFT],
                           random_y8);
                random_stage3_index <= random_stage3_index + 1;
            end

            if (impulse_y128_valid) begin
                if (impulse_full_index < FULL_FIXED_SHIFT) begin
                    if (impulse_y128 !== 24'sd0)
                        $fatal(1, "impulse full nonzero before fixed shift");
                end
                else if (impulse_full_index <
                         FULL_FIXED_SHIFT + IMPULSE_FULL_COUNT &&
                         impulse_y128 !== impulse_full_golden[
                             impulse_full_index-FULL_FIXED_SHIFT])
                    $fatal(1, "impulse full mismatch index=%0d ref=%0d dut=%0d",
                           impulse_full_index-FULL_FIXED_SHIFT,
                           impulse_full_golden[
                               impulse_full_index-FULL_FIXED_SHIFT],
                           impulse_y128);
                impulse_full_index <= impulse_full_index + 1;
            end

            if (random_y128_valid) begin
                if (random_full_index < FULL_FIXED_SHIFT) begin
                    if (random_y128 !== 24'sd0)
                        $fatal(1, "random full nonzero before fixed shift");
                end
                else if (random_full_index <
                         FULL_FIXED_SHIFT + RANDOM_FULL_COUNT &&
                         random_y128 !== random_full_golden[
                             random_full_index-FULL_FIXED_SHIFT])
                    $fatal(1, "random full mismatch index=%0d ref=%0d dut=%0d",
                           random_full_index-FULL_FIXED_SHIFT,
                           random_full_golden[
                               random_full_index-FULL_FIXED_SHIFT],
                           random_y128);
                random_full_index <= random_full_index + 1;
            end
        end
    end

    initial begin
        $readmemh("phase6_impulse_input_24bit.mem", impulse_input_mem);
        $readmemh("phase6_random_input_24bit.mem", random_input_mem);
        $readmemh("phase6_stage2_impulse_golden_24bit.mem",
                  impulse_stage2_golden);
        $readmemh("phase6_stage2_random_golden_24bit.mem",
                  random_stage2_golden);
        $readmemh("phase6_stage3_impulse_golden_24bit.mem",
                  impulse_stage3_golden);
        $readmemh("phase6_stage3_random_golden_24bit.mem",
                  random_stage3_golden);
        $readmemh("phase6_full_impulse_golden_24bit.mem",
                  impulse_full_golden);
        $readmemh("phase6_full_random_golden_24bit.mem",
                  random_full_golden);

        impulse_stage2_index = 0;
        random_stage2_index = 0;
        impulse_stage3_index = 0;
        random_stage3_index = 0;
        impulse_full_index = 0;
        random_full_index = 0;
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (70000) @(posedge clk);

        if (impulse_stage2_index < STAGE2_FIXED_SHIFT +
                                     IMPULSE_STAGE2_COUNT ||
            random_stage2_index < STAGE2_FIXED_SHIFT +
                                    RANDOM_STAGE2_COUNT ||
            impulse_stage3_index < STAGE3_FIXED_SHIFT +
                                     IMPULSE_STAGE3_COUNT ||
            random_stage3_index < STAGE3_FIXED_SHIFT +
                                    RANDOM_STAGE3_COUNT ||
            impulse_full_index < FULL_FIXED_SHIFT + IMPULSE_FULL_COUNT ||
            random_full_index < FULL_FIXED_SHIFT + RANDOM_FULL_COUNT)
            $fatal(1, "Phase 6 mixed-width output count is insufficient");

        $display("PASS: Phase 6 mixed-width impulse/random bit-true test");
        $display("S2 imp=%0d rnd=%0d S3 imp=%0d rnd=%0d full imp=%0d rnd=%0d",
                 IMPULSE_STAGE2_COUNT, RANDOM_STAGE2_COUNT,
                 IMPULSE_STAGE3_COUNT, RANDOM_STAGE3_COUNT,
                 IMPULSE_FULL_COUNT, RANDOM_FULL_COUNT);
        $finish;
    end

endmodule
