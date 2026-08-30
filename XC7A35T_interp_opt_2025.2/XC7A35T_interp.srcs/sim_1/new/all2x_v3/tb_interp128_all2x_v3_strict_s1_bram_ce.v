`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_interp128_all2x_v3_strict_s1_bram_ce.v
// 模块名       : tb_interp128_all2x_v3_strict_s1_bram_ce
// 功能简述     : V3 strict Stage 1 BRAM 完整七级测试平台。
//                两个 DUT 分别输入冲激和随机 PCM，记录最终输出，
//                供 MATLAB 与完整七级 bit-true golden 对齐对拍。
//
//                输入文件：
//                  stage1_strict_impulse_input_24bit.mem
//                  stage1_strict_random_input_24bit.mem
//                输出文件：
//                  v3_strict_bram_impulse_output.csv
//                  v3_strict_bram_random_output.csv
//
// 当前默认配置：
//                  仿真时钟周期：10ns
//                  仿真时钟数  ：70000 拍
//                  Stage 1     ：105 tap Q15 strict-halfband
//                  Stage 2/3   ：V2 true-polyphase
//                  Stage 4～7  ：canonical Q4
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-11
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-11：新增 V3 BRAM 完整七级对拍测试平台。
//=============================================================
//=============================================================
// 1）模块名称：tb_interp128_all2x_v3_strict_s1_bram_ce
// 功能说明：仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 工程版本：Vivado 2025.2。
//=============================================================

module tb_interp128_all2x_v3_strict_s1_bram_ce;

    localparam integer IMPULSE_INPUT_COUNT = 256;
    localparam integer RANDOM_INPUT_COUNT = 128;

    reg clk;
    reg rst_n;
    reg [6:0] ce_cnt;
    reg tb_phase;
    reg signed [23:0] impulse_input_mem [0:IMPULSE_INPUT_COUNT-1];
    reg signed [23:0] random_input_mem [0:RANDOM_INPUT_COUNT-1];
    reg signed [23:0] impulse_x;
    reg signed [23:0] random_x;
    integer impulse_input_idx;
    integer random_input_idx;
    integer impulse_output_count;
    integer random_output_count;
    integer fp_impulse;
    integer fp_random;

    wire ce2_out;
    wire ce4_out;
    wire ce8_out;
    wire ce16_out;
    wire ce32_out;
    wire ce64_out;
    wire ce128_out;
    wire signed [23:0] impulse_y;
    wire signed [23:0] random_y;
    wire impulse_y_valid;
    wire random_y_valid;

    assign ce128_out = 1'b1;
    assign ce64_out = (ce_cnt[0] == 1'b0);
    assign ce32_out = (ce_cnt[1:0] == 2'b00);
    assign ce16_out = (ce_cnt[2:0] == 3'b000);
    assign ce8_out = (ce_cnt[3:0] == 4'b0000);
    assign ce4_out = (ce_cnt[4:0] == 5'b00000);
    assign ce2_out = (ce_cnt[5:0] == 6'b000000);

    // 例化说明：调用 interp128_all2x_v3_strict_s1_bram_top_ce 插值链顶层，完成所选倍率的数据率提升与有效信号传递。
    interp128_all2x_v3_strict_s1_bram_top_ce dut_impulse (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(impulse_x), .x_in_valid(1'b1),
        .y_out(impulse_y), .y_out_valid(impulse_y_valid),
        .dbg_y2(), .dbg_y2_valid(), .dbg_y4(), .dbg_y4_valid(),
        .dbg_y8(), .dbg_y8_valid(), .dbg_y16(), .dbg_y16_valid(),
        .dbg_y32(), .dbg_y32_valid(), .dbg_y64(), .dbg_y64_valid()
    );

    // 例化说明：调用 interp128_all2x_v3_strict_s1_bram_top_ce 插值链顶层，完成所选倍率的数据率提升与有效信号传递。
    interp128_all2x_v3_strict_s1_bram_top_ce dut_random (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(random_x), .x_in_valid(1'b1),
        .y_out(random_y), .y_out_valid(random_y_valid),
        .dbg_y2(), .dbg_y2_valid(), .dbg_y4(), .dbg_y4_valid(),
        .dbg_y8(), .dbg_y8_valid(), .dbg_y16(), .dbg_y16_valid(),
        .dbg_y32(), .dbg_y32_valid(), .dbg_y64(), .dbg_y64_valid()
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            ce_cnt <= 7'd0;
            tb_phase <= 1'b1;
            impulse_x <= impulse_input_mem[0];
            random_x <= random_input_mem[0];
            impulse_input_idx <= 0;
            random_input_idx <= 0;
        end
        else begin
            ce_cnt <= ce_cnt + 7'd1;

            if (ce2_out) begin
                if (tb_phase == 1'b0) begin
                    impulse_input_idx <= impulse_input_idx + 1;
                    random_input_idx <= random_input_idx + 1;

                    if (impulse_input_idx + 1 < IMPULSE_INPUT_COUNT)
                        impulse_x <= impulse_input_mem[impulse_input_idx + 1];
                    else
                        impulse_x <= 24'sd0;

                    if (random_input_idx + 1 < RANDOM_INPUT_COUNT)
                        random_x <= random_input_mem[random_input_idx + 1];
                    else
                        random_x <= 24'sd0;
                end

                tb_phase <= ~tb_phase;
            end
        end
    end

    always @(posedge clk) begin
        if (impulse_y_valid) begin
            $fwrite(fp_impulse, "%0d,%0d\n",
                    impulse_output_count, impulse_y);
            impulse_output_count <= impulse_output_count + 1;
        end
        if (random_y_valid) begin
            $fwrite(fp_random, "%0d,%0d\n",
                    random_output_count, random_y);
            random_output_count <= random_output_count + 1;
        end
    end

    initial begin
        $readmemh("stage1_strict_impulse_input_24bit.mem",
                  impulse_input_mem);
        $readmemh("stage1_strict_random_input_24bit.mem",
                  random_input_mem);

        fp_impulse = $fopen("v3_strict_bram_impulse_output.csv", "w");
        fp_random = $fopen("v3_strict_bram_random_output.csv", "w");
        $fwrite(fp_impulse, "index,y_out\n");
        $fwrite(fp_random, "index,y_out\n");

        impulse_output_count = 0;
        random_output_count = 0;
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        repeat (70000) @(posedge clk);

        $display("V3 strict BRAM full-chain counts: impulse=%0d random=%0d",
                 impulse_output_count, random_output_count);
        $fclose(fp_impulse);
        $fclose(fp_random);
        $finish;
    end

endmodule
