`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_interp128_all2x_v2_polyphase_ce.v
// 模块名       : tb_interp128_all2x_v2_polyphase_ce
// 功能简述     : Phase 2 的 Stage 3、Stage 2～3 true-polyphase
//                两组候选并行对拍测试平台。两组 DUT 共用输入和 CE，
//                并分别导出最终 128x 输出 CSV。
//
//                输入文件：canonical_test_input_24bit.mem
//                输出文件：
//                  v2_poly_stage3_output.csv
//                  v2_poly_stage2_output.csv
//
// 当前默认配置：
//                  输入缓存长度：256 点，不足部分预填 0
//                  仿真时钟数  ：50000 拍
//                  最终输出频率：5.6448MHz
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-11
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-11：新增 Phase 2 两候选并行对拍平台。
//=============================================================

module tb_interp128_all2x_v2_polyphase_ce;

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

    wire signed [23:0] y_stage3;
    wire signed [23:0] y_stage2;
    wire valid_stage3;
    wire valid_stage2;

    integer fp_stage3;
    integer fp_stage2;
    integer count_stage3;
    integer count_stage2;
    integer init_idx;

    assign ce128_out      = 1'b1;
    assign ce64_out       = (ce_cnt[0]   == 1'b0);
    assign ce32_out       = (ce_cnt[1:0] == 2'b00);
    assign ce16_out       = (ce_cnt[2:0] == 3'b000);
    assign ce8_out        = (ce_cnt[3:0] == 4'b0000);
    assign ce4_out        = (ce_cnt[4:0] == 5'b00000);
    assign ce2_out        = (ce_cnt[5:0] == 6'b000000);
    assign x_in_update_ce = (ce_cnt == 7'd127);

    interp128_all2x_v2_polyphase_top_ce #(
        .DATA_W                       (24),
        .FIRST_CANONICAL_STAGE        (4),
        .FIRST_TRUE_POLYPHASE_STAGE   (3)
    ) dut_stage3 (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(x_in), .x_in_valid(1'b1),
        .y_out(y_stage3), .y_out_valid(valid_stage3),
        .dbg_y2(), .dbg_y2_valid(), .dbg_y4(), .dbg_y4_valid(),
        .dbg_y8(), .dbg_y8_valid(), .dbg_y16(), .dbg_y16_valid(),
        .dbg_y32(), .dbg_y32_valid(), .dbg_y64(), .dbg_y64_valid()
    );

    interp128_all2x_v2_polyphase_top_ce #(
        .DATA_W                       (24),
        .FIRST_CANONICAL_STAGE        (4),
        .FIRST_TRUE_POLYPHASE_STAGE   (2)
    ) dut_stage2 (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(x_in), .x_in_valid(1'b1),
        .y_out(y_stage2), .y_out_valid(valid_stage2),
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
        if (valid_stage3) begin
            $fwrite(fp_stage3, "%0d,%0d\n", count_stage3, y_stage3);
            count_stage3 <= count_stage3 + 1;
        end
        if (valid_stage2) begin
            $fwrite(fp_stage2, "%0d,%0d\n", count_stage2, y_stage2);
            count_stage2 <= count_stage2 + 1;
        end
    end

    initial begin
        for (init_idx = 0; init_idx < INPUT_COUNT; init_idx = init_idx + 1)
            input_mem[init_idx] = 24'sd0;
        $readmemh("canonical_test_input_24bit.mem", input_mem);

        fp_stage3 = $fopen("v2_poly_stage3_output.csv", "w");
        fp_stage2 = $fopen("v2_poly_stage2_output.csv", "w");
        $fwrite(fp_stage3, "index,y_out\n");
        $fwrite(fp_stage2, "index,y_out\n");

        count_stage3 = 0;
        count_stage2 = 0;
        rst_n = 1'b0;
        #200;
        rst_n = 1'b1;

        repeat (50000) @(posedge clk);

        $display("Phase 2 valid counts: S3=%0d S2_3=%0d",
                 count_stage3, count_stage2);
        $fclose(fp_stage3);
        $fclose(fp_stage2);
        $finish;
    end

endmodule
