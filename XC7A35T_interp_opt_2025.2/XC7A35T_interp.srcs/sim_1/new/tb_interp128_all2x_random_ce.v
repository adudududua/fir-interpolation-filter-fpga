`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_interp128_all2x_random_ce.v
// 模块名       : tb_interp128_all2x_random_ce
// 功能简述     : 全 2x 结构 128 倍插值顶层的随机 PCM 对拍测试模块。
//                本模块通过 $readmemh 读取 MATLAB bit-true 模型导出的
//                128 点 24bit signed 随机输入，并记录最终输出 CSV。
//
//                输入文件：
//                  all2x_random_input_24bit.mem
//
//                输出文件：
//                  interp128_all2x_random_tb_output.csv
//
// 当前默认配置：
//                  仿真时钟周期：10ns
//                  输入样点数  ：128 点
//                  最终仿真点数：30000 点
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-10
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-10：新增全 2x 随机 PCM 对拍测试模块。
//=============================================================
//=============================================================
// 1）模块名称：tb_interp128_all2x_random_ce
// 功能说明：仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 工程版本：Vivado 2025.2。
//=============================================================

module tb_interp128_all2x_random_ce;

    localparam integer INPUT_COUNT = 128;

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

    wire signed [23:0] y_out;
    wire               y_out_valid;

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

    // 例化说明：调用 interp128_all2x_top_ce 插值链顶层，完成所选倍率的数据率提升与有效信号传递。
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
        .dbg_y2        (),
        .dbg_y2_valid  (),
        .dbg_y4        (),
        .dbg_y4_valid  (),
        .dbg_y8        (),
        .dbg_y8_valid  (),
        .dbg_y16       (),
        .dbg_y16_valid (),
        .dbg_y32       (),
        .dbg_y32_valid (),
        .dbg_y64       (),
        .dbg_y64_valid ()
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
        if (y_out_valid) begin
            final_valid_count <= final_valid_count + 1;
            $fwrite(fp_out, "%0d,%0d\n", final_valid_count, y_out);
        end
    end

    initial begin
        $readmemh("all2x_random_input_24bit.mem", input_mem);
        fp_out = $fopen("interp128_all2x_random_tb_output.csv", "w");
        $fwrite(fp_out, "index,y_out\n");

        final_valid_count = 0;
        rst_n = 1'b0;
        #200;
        rst_n = 1'b1;

        repeat (30000) @(posedge clk);

        $display("Random input samples = %0d", INPUT_COUNT);
        $display("Final valid sample count = %0d", final_valid_count);
        $fclose(fp_out);
        $finish;
    end

endmodule
