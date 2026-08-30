`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_interp128_all2x_v2_ce.v
// 模块名       : tb_interp128_all2x_v2_ce
// 功能简述     : V2 canonical halfband7 四组尾级候选并行对拍测试。
//                四个 DUT 共用输入与 CE，分别记录 Stage 7、
//                Stage 6～7、Stage 5～7、Stage 4～7 替换结果。
//
//                输入文件：canonical_test_input_24bit.mem
//                输出文件：
//                  v2_stage7_output.csv
//                  v2_stage6_7_output.csv
//                  v2_stage5_7_output.csv
//                  v2_stage4_7_output.csv
//
// 当前默认配置：
//                  仿真时钟周期：10ns
//                  输入缓存长度：256 点，不足部分预填 0
//                  仿真时钟数  ：50000 拍
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-11
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-11：新增 V2 四候选并行对拍测试模块。
//=============================================================
//=============================================================
// 1）模块名称：tb_interp128_all2x_v2_ce
// 功能说明：仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 工程版本：Vivado 2025.2。
//=============================================================

module tb_interp128_all2x_v2_ce;

    localparam integer INPUT_COUNT = 256;

    reg clk;
    reg rst_n;
    reg [6:0] ce_cnt;
    reg signed [23:0] x_in;
    reg signed [23:0] input_mem [0:INPUT_COUNT-1];
    reg [15:0] input_idx;

    wire ce2_out;
    wire ce4_out;
    wire ce8_out;
    wire ce16_out;
    wire ce32_out;
    wire ce64_out;
    wire ce128_out;
    wire x_in_update_ce;

    wire signed [23:0] y_stage7;
    wire signed [23:0] y_stage6_7;
    wire signed [23:0] y_stage5_7;
    wire signed [23:0] y_stage4_7;
    wire valid_stage7;
    wire valid_stage6_7;
    wire valid_stage5_7;
    wire valid_stage4_7;

    integer fp_stage7;
    integer fp_stage6_7;
    integer fp_stage5_7;
    integer fp_stage4_7;
    integer count_stage7;
    integer count_stage6_7;
    integer count_stage5_7;
    integer count_stage4_7;
    integer init_idx;

    assign ce128_out      = 1'b1;
    assign ce64_out       = (ce_cnt[0]   == 1'b0);
    assign ce32_out       = (ce_cnt[1:0] == 2'b00);
    assign ce16_out       = (ce_cnt[2:0] == 3'b000);
    assign ce8_out        = (ce_cnt[3:0] == 4'b0000);
    assign ce4_out        = (ce_cnt[4:0] == 5'b00000);
    assign ce2_out        = (ce_cnt[5:0] == 6'b000000);
    assign x_in_update_ce = (ce_cnt == 7'd127);

    // 例化说明：调用 interp128_all2x_v2_top_ce 插值链顶层，完成所选倍率的数据率提升与有效信号传递。
    interp128_all2x_v2_top_ce #(
        .DATA_W                  (24),
        .FIRST_CANONICAL_STAGE   (7)
    ) dut_stage7 (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(x_in), .x_in_valid(1'b1),
        .y_out(y_stage7), .y_out_valid(valid_stage7),
        .dbg_y2(), .dbg_y2_valid(), .dbg_y4(), .dbg_y4_valid(),
        .dbg_y8(), .dbg_y8_valid(), .dbg_y16(), .dbg_y16_valid(),
        .dbg_y32(), .dbg_y32_valid(), .dbg_y64(), .dbg_y64_valid()
    );

    // 例化说明：调用 interp128_all2x_v2_top_ce 插值链顶层，完成所选倍率的数据率提升与有效信号传递。
    interp128_all2x_v2_top_ce #(
        .DATA_W                  (24),
        .FIRST_CANONICAL_STAGE   (6)
    ) dut_stage6_7 (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(x_in), .x_in_valid(1'b1),
        .y_out(y_stage6_7), .y_out_valid(valid_stage6_7),
        .dbg_y2(), .dbg_y2_valid(), .dbg_y4(), .dbg_y4_valid(),
        .dbg_y8(), .dbg_y8_valid(), .dbg_y16(), .dbg_y16_valid(),
        .dbg_y32(), .dbg_y32_valid(), .dbg_y64(), .dbg_y64_valid()
    );

    // 例化说明：调用 interp128_all2x_v2_top_ce 插值链顶层，完成所选倍率的数据率提升与有效信号传递。
    interp128_all2x_v2_top_ce #(
        .DATA_W                  (24),
        .FIRST_CANONICAL_STAGE   (5)
    ) dut_stage5_7 (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(x_in), .x_in_valid(1'b1),
        .y_out(y_stage5_7), .y_out_valid(valid_stage5_7),
        .dbg_y2(), .dbg_y2_valid(), .dbg_y4(), .dbg_y4_valid(),
        .dbg_y8(), .dbg_y8_valid(), .dbg_y16(), .dbg_y16_valid(),
        .dbg_y32(), .dbg_y32_valid(), .dbg_y64(), .dbg_y64_valid()
    );

    // 例化说明：调用 interp128_all2x_v2_top_ce 插值链顶层，完成所选倍率的数据率提升与有效信号传递。
    interp128_all2x_v2_top_ce #(
        .DATA_W                  (24),
        .FIRST_CANONICAL_STAGE   (4)
    ) dut_stage4_7 (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(x_in), .x_in_valid(1'b1),
        .y_out(y_stage4_7), .y_out_valid(valid_stage4_7),
        .dbg_y2(), .dbg_y2_valid(), .dbg_y4(), .dbg_y4_valid(),
        .dbg_y8(), .dbg_y8_valid(), .dbg_y16(), .dbg_y16_valid(),
        .dbg_y32(), .dbg_y32_valid(), .dbg_y64(), .dbg_y64_valid()
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ce_cnt <= 7'd0;
        else
            ce_cnt <= ce_cnt + 7'd1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_in      <= 24'sd0;
            input_idx <= 16'd0;
        end
        else if (x_in_update_ce) begin
            if (input_idx < INPUT_COUNT)
                x_in <= input_mem[input_idx];
            else
                x_in <= 24'sd0;

            input_idx <= input_idx + 16'd1;
        end
    end

    always @(posedge clk) begin
        if (valid_stage7) begin
            $fwrite(fp_stage7, "%0d,%0d\n", count_stage7, y_stage7);
            count_stage7 <= count_stage7 + 1;
        end
        if (valid_stage6_7) begin
            $fwrite(fp_stage6_7, "%0d,%0d\n", count_stage6_7, y_stage6_7);
            count_stage6_7 <= count_stage6_7 + 1;
        end
        if (valid_stage5_7) begin
            $fwrite(fp_stage5_7, "%0d,%0d\n", count_stage5_7, y_stage5_7);
            count_stage5_7 <= count_stage5_7 + 1;
        end
        if (valid_stage4_7) begin
            $fwrite(fp_stage4_7, "%0d,%0d\n", count_stage4_7, y_stage4_7);
            count_stage4_7 <= count_stage4_7 + 1;
        end
    end

    initial begin
        for (init_idx = 0; init_idx < INPUT_COUNT; init_idx = init_idx + 1)
            input_mem[init_idx] = 24'sd0;
        $readmemh("canonical_test_input_24bit.mem", input_mem);

        fp_stage7 = $fopen("v2_stage7_output.csv", "w");
        fp_stage6_7 = $fopen("v2_stage6_7_output.csv", "w");
        fp_stage5_7 = $fopen("v2_stage5_7_output.csv", "w");
        fp_stage4_7 = $fopen("v2_stage4_7_output.csv", "w");
        $fwrite(fp_stage7, "index,y_out\n");
        $fwrite(fp_stage6_7, "index,y_out\n");
        $fwrite(fp_stage5_7, "index,y_out\n");
        $fwrite(fp_stage4_7, "index,y_out\n");

        count_stage7 = 0;
        count_stage6_7 = 0;
        count_stage5_7 = 0;
        count_stage4_7 = 0;
        rst_n = 1'b0;
        #200;
        rst_n = 1'b1;

        repeat (50000) @(posedge clk);

        $display("V2 valid counts: S7=%0d S6_7=%0d S5_7=%0d S4_7=%0d",
                 count_stage7, count_stage6_7,
                 count_stage5_7, count_stage4_7);
        $fclose(fp_stage7);
        $fclose(fp_stage6_7);
        $fclose(fp_stage5_7);
        $fclose(fp_stage4_7);
        $finish;
    end

endmodule
