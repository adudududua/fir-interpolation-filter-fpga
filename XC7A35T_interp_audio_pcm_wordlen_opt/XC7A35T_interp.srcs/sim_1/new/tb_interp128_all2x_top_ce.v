`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_interp128_all2x_top_ce.v
// 模块名       : tb_interp128_all2x_top_ce
// 功能简述     : 全 2x 结构 128 倍插值顶层的基础仿真测试模块。
//                本 testbench 在 128x 最终时钟域中产生 ce2_out 到
//                ce128_out 的多级时钟使能信号，并向全 2x 插值链路
//                输入一个 44.1kHz 采样率下的脉冲测试序列。
//
//                仿真输出会写入：
//                  interp128_all2x_tb_output.csv
//
//                当前默认配置：
//                  仿真时钟周期：10ns
//                  输入激励    ：单点脉冲
//                  输出数据    ：最终 128x 输出采样点
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-10
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-10：新增全 2x 顶层基础仿真测试模块。
//=============================================================

module tb_interp128_all2x_top_ce;

    reg clk;
    reg rst_n;

    reg [6:0] ce_cnt;
    reg signed [23:0] x_in;
    reg [15:0] sample_idx;

    wire ce2_out;
    wire ce4_out;
    wire ce8_out;
    wire ce16_out;
    wire ce32_out;
    wire ce64_out;
    wire ce128_out;
    wire x_in_update_ce;

    wire signed [23:0] y_out;
    wire               y_out_valid;

    wire signed [23:0] dbg_y2;
    wire               dbg_y2_valid;
    wire signed [23:0] dbg_y4;
    wire               dbg_y4_valid;
    wire signed [23:0] dbg_y8;
    wire               dbg_y8_valid;
    wire signed [23:0] dbg_y16;
    wire               dbg_y16_valid;
    wire signed [23:0] dbg_y32;
    wire               dbg_y32_valid;
    wire signed [23:0] dbg_y64;
    wire               dbg_y64_valid;

    integer fp_out;
    integer final_valid_count;

    assign ce128_out      = 1'b1;
    assign ce64_out       = (ce_cnt[0]   == 1'b0);
    assign ce32_out       = (ce_cnt[1:0] == 2'b00);
    assign ce16_out       = (ce_cnt[2:0] == 3'b000);
    assign ce8_out        = (ce_cnt[3:0] == 4'b0000);
    assign ce4_out        = (ce_cnt[4:0] == 5'b00000);
    assign ce2_out        = (ce_cnt[5:0] == 6'b000000);
    assign x_in_update_ce = (ce_cnt == 7'd127);

    interp128_all2x_top_ce #(
        .DATA_W (24)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),

        .ce2_out       (ce2_out),
        .ce4_out       (ce4_out),
        .ce8_out       (ce8_out),
        .ce16_out      (ce16_out),
        .ce32_out      (ce32_out),
        .ce64_out      (ce64_out),
        .ce128_out     (ce128_out),

        .x_in          (x_in),
        .x_in_valid    (1'b1),

        .y_out         (y_out),
        .y_out_valid   (y_out_valid),

        .dbg_y2        (dbg_y2),
        .dbg_y2_valid  (dbg_y2_valid),
        .dbg_y4        (dbg_y4),
        .dbg_y4_valid  (dbg_y4_valid),
        .dbg_y8        (dbg_y8),
        .dbg_y8_valid  (dbg_y8_valid),
        .dbg_y16       (dbg_y16),
        .dbg_y16_valid (dbg_y16_valid),
        .dbg_y32       (dbg_y32),
        .dbg_y32_valid (dbg_y32_valid),
        .dbg_y64       (dbg_y64),
        .dbg_y64_valid (dbg_y64_valid)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ce_cnt <= 7'd0;
        end
        else begin
            ce_cnt <= ce_cnt + 7'd1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_in       <= 24'sd0;
            sample_idx <= 16'd0;
        end
        else if (x_in_update_ce) begin
            if (sample_idx == 16'd0)
                x_in <= 24'sd1000000;
            else
                x_in <= 24'sd0;

            sample_idx <= sample_idx + 16'd1;
        end
    end

    always @(posedge clk) begin
        if (y_out_valid) begin
            final_valid_count <= final_valid_count + 1;
            $fwrite(fp_out, "%0d,%0d\n", final_valid_count, y_out);
        end
    end

    initial begin
        fp_out = $fopen("interp128_all2x_tb_output.csv", "w");
        $fwrite(fp_out, "index,y_out\n");

        final_valid_count = 0;
        rst_n = 1'b0;
        #200;
        rst_n = 1'b1;

        repeat (30000) @(posedge clk);

        $display("Final valid sample count = %0d", final_valid_count);
        $fclose(fp_out);
        $finish;
    end

endmodule
