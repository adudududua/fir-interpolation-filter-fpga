`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_interp128_all2x_v4_shared_dsp_ce.v
// 模块名       : tb_interp128_all2x_v4_shared_dsp_ce
// 功能简述     : V4 Stage 2/3 共享 DSP 完整七级回归测试平台。
//                V3 BRAM 参考链和 V4 共享 DSP 链并行接收相同的
//                冲激与随机 PCM，分别记录 Stage 2、Stage 3 和
//                最终 128x 输出，供 MATLAB 完成延迟对齐和 0 LSB
//                逐点比较；共享模块内部断言同时检查调度超期。
//
// 当前默认配置：
//                  仿真时钟周期：10ns
//                  仿真时钟数  ：70000 拍
//                  输入采样率  ：44.1kHz 等效 CE
//                  输出采样率  ：5.6448MHz 等效 CE
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-12
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-12：新增 V3/V4 分级并行回归测试平台。
//=============================================================
//=============================================================
// 1）模块名称：tb_interp128_all2x_v4_shared_dsp_ce
// 功能说明：仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 工程版本：Vivado 2025.2。
//=============================================================

module tb_interp128_all2x_v4_shared_dsp_ce;

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

    wire ce2_out = (ce_cnt[5:0] == 6'b000000);
    wire ce4_out = (ce_cnt[4:0] == 5'b00000);
    wire ce8_out = (ce_cnt[3:0] == 4'b0000);
    wire ce16_out = (ce_cnt[2:0] == 3'b000);
    wire ce32_out = (ce_cnt[1:0] == 2'b00);
    wire ce64_out = (ce_cnt[0] == 1'b0);
    wire ce128_out = 1'b1;

    wire signed [23:0] v3_imp_y4;
    wire signed [23:0] v3_imp_y8;
    wire signed [23:0] v3_imp_y128;
    wire v3_imp_y4_valid;
    wire v3_imp_y8_valid;
    wire v3_imp_y128_valid;
    wire signed [23:0] v4_imp_y4;
    wire signed [23:0] v4_imp_y8;
    wire signed [23:0] v4_imp_y128;
    wire v4_imp_y4_valid;
    wire v4_imp_y8_valid;
    wire v4_imp_y128_valid;

    wire signed [23:0] v3_rnd_y4;
    wire signed [23:0] v3_rnd_y8;
    wire signed [23:0] v3_rnd_y128;
    wire v3_rnd_y4_valid;
    wire v3_rnd_y8_valid;
    wire v3_rnd_y128_valid;
    wire signed [23:0] v4_rnd_y4;
    wire signed [23:0] v4_rnd_y8;
    wire signed [23:0] v4_rnd_y128;
    wire v4_rnd_y4_valid;
    wire v4_rnd_y8_valid;
    wire v4_rnd_y128_valid;

    integer fp_v3_imp_s2;
    integer fp_v3_imp_s3;
    integer fp_v3_rnd_s2;
    integer fp_v3_rnd_s3;
    integer fp_v4_imp_s2;
    integer fp_v4_imp_s3;
    integer fp_v4_imp_full;
    integer fp_v4_rnd_s2;
    integer fp_v4_rnd_s3;
    integer fp_v4_rnd_full;
    integer count_v3_imp_s2;
    integer count_v3_imp_s3;
    integer count_v3_rnd_s2;
    integer count_v3_rnd_s3;
    integer count_v4_imp_s2;
    integer count_v4_imp_s3;
    integer count_v4_imp_full;
    integer count_v4_rnd_s2;
    integer count_v4_rnd_s3;
    integer count_v4_rnd_full;

    // 例化说明：调用 interp128_all2x_v3_strict_s1_bram_top_ce 插值链顶层，完成所选倍率的数据率提升与有效信号传递。
    interp128_all2x_v3_strict_s1_bram_top_ce u_v3_impulse (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(impulse_x), .x_in_valid(1'b1),
        .y_out(v3_imp_y128), .y_out_valid(v3_imp_y128_valid),
        .dbg_y2(), .dbg_y2_valid(),
        .dbg_y4(v3_imp_y4), .dbg_y4_valid(v3_imp_y4_valid),
        .dbg_y8(v3_imp_y8), .dbg_y8_valid(v3_imp_y8_valid),
        .dbg_y16(), .dbg_y16_valid(), .dbg_y32(), .dbg_y32_valid(),
        .dbg_y64(), .dbg_y64_valid()
    );

    // 例化说明：调用 interp128_all2x_v4_shared_dsp_top_ce 插值链顶层，完成所选倍率的数据率提升与有效信号传递。
    interp128_all2x_v4_shared_dsp_top_ce u_v4_impulse (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(impulse_x), .x_in_valid(1'b1),
        .y_out(v4_imp_y128), .y_out_valid(v4_imp_y128_valid),
        .dbg_y2(), .dbg_y2_valid(),
        .dbg_y4(v4_imp_y4), .dbg_y4_valid(v4_imp_y4_valid),
        .dbg_y8(v4_imp_y8), .dbg_y8_valid(v4_imp_y8_valid),
        .dbg_y16(), .dbg_y16_valid(), .dbg_y32(), .dbg_y32_valid(),
        .dbg_y64(), .dbg_y64_valid()
    );

    // 例化说明：调用 interp128_all2x_v3_strict_s1_bram_top_ce 插值链顶层，完成所选倍率的数据率提升与有效信号传递。
    interp128_all2x_v3_strict_s1_bram_top_ce u_v3_random (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(random_x), .x_in_valid(1'b1),
        .y_out(v3_rnd_y128), .y_out_valid(v3_rnd_y128_valid),
        .dbg_y2(), .dbg_y2_valid(),
        .dbg_y4(v3_rnd_y4), .dbg_y4_valid(v3_rnd_y4_valid),
        .dbg_y8(v3_rnd_y8), .dbg_y8_valid(v3_rnd_y8_valid),
        .dbg_y16(), .dbg_y16_valid(), .dbg_y32(), .dbg_y32_valid(),
        .dbg_y64(), .dbg_y64_valid()
    );

    // 例化说明：调用 interp128_all2x_v4_shared_dsp_top_ce 插值链顶层，完成所选倍率的数据率提升与有效信号传递。
    interp128_all2x_v4_shared_dsp_top_ce u_v4_random (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(random_x), .x_in_valid(1'b1),
        .y_out(v4_rnd_y128), .y_out_valid(v4_rnd_y128_valid),
        .dbg_y2(), .dbg_y2_valid(),
        .dbg_y4(v4_rnd_y4), .dbg_y4_valid(v4_rnd_y4_valid),
        .dbg_y8(v4_rnd_y8), .dbg_y8_valid(v4_rnd_y8_valid),
        .dbg_y16(), .dbg_y16_valid(), .dbg_y32(), .dbg_y32_valid(),
        .dbg_y64(), .dbg_y64_valid()
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
        if (v3_imp_y4_valid) begin
            $fwrite(fp_v3_imp_s2, "%0d,%0d\n", count_v3_imp_s2, v3_imp_y4);
            count_v3_imp_s2 <= count_v3_imp_s2 + 1;
        end
        if (v3_imp_y8_valid) begin
            $fwrite(fp_v3_imp_s3, "%0d,%0d\n", count_v3_imp_s3, v3_imp_y8);
            count_v3_imp_s3 <= count_v3_imp_s3 + 1;
        end
        if (v3_rnd_y4_valid) begin
            $fwrite(fp_v3_rnd_s2, "%0d,%0d\n", count_v3_rnd_s2, v3_rnd_y4);
            count_v3_rnd_s2 <= count_v3_rnd_s2 + 1;
        end
        if (v3_rnd_y8_valid) begin
            $fwrite(fp_v3_rnd_s3, "%0d,%0d\n", count_v3_rnd_s3, v3_rnd_y8);
            count_v3_rnd_s3 <= count_v3_rnd_s3 + 1;
        end
        if (v4_imp_y4_valid) begin
            $fwrite(fp_v4_imp_s2, "%0d,%0d\n", count_v4_imp_s2, v4_imp_y4);
            count_v4_imp_s2 <= count_v4_imp_s2 + 1;
        end
        if (v4_imp_y8_valid) begin
            $fwrite(fp_v4_imp_s3, "%0d,%0d\n", count_v4_imp_s3, v4_imp_y8);
            count_v4_imp_s3 <= count_v4_imp_s3 + 1;
        end
        if (v4_imp_y128_valid) begin
            $fwrite(fp_v4_imp_full, "%0d,%0d\n", count_v4_imp_full, v4_imp_y128);
            count_v4_imp_full <= count_v4_imp_full + 1;
        end
        if (v4_rnd_y4_valid) begin
            $fwrite(fp_v4_rnd_s2, "%0d,%0d\n", count_v4_rnd_s2, v4_rnd_y4);
            count_v4_rnd_s2 <= count_v4_rnd_s2 + 1;
        end
        if (v4_rnd_y8_valid) begin
            $fwrite(fp_v4_rnd_s3, "%0d,%0d\n", count_v4_rnd_s3, v4_rnd_y8);
            count_v4_rnd_s3 <= count_v4_rnd_s3 + 1;
        end
        if (v4_rnd_y128_valid) begin
            $fwrite(fp_v4_rnd_full, "%0d,%0d\n", count_v4_rnd_full, v4_rnd_y128);
            count_v4_rnd_full <= count_v4_rnd_full + 1;
        end
    end

    initial begin
        $readmemh("stage1_strict_impulse_input_24bit.mem", impulse_input_mem);
        $readmemh("stage1_strict_random_input_24bit.mem", random_input_mem);

        fp_v3_imp_s2 = $fopen("v3_stage2_impulse.csv", "w");
        fp_v3_imp_s3 = $fopen("v3_stage3_impulse.csv", "w");
        fp_v3_rnd_s2 = $fopen("v3_stage2_random.csv", "w");
        fp_v3_rnd_s3 = $fopen("v3_stage3_random.csv", "w");
        fp_v4_imp_s2 = $fopen("v4_stage2_impulse.csv", "w");
        fp_v4_imp_s3 = $fopen("v4_stage3_impulse.csv", "w");
        fp_v4_imp_full = $fopen("v4_full_impulse.csv", "w");
        fp_v4_rnd_s2 = $fopen("v4_stage2_random.csv", "w");
        fp_v4_rnd_s3 = $fopen("v4_stage3_random.csv", "w");
        fp_v4_rnd_full = $fopen("v4_full_random.csv", "w");

        $fwrite(fp_v3_imp_s2, "index,y_out\n");
        $fwrite(fp_v3_imp_s3, "index,y_out\n");
        $fwrite(fp_v3_rnd_s2, "index,y_out\n");
        $fwrite(fp_v3_rnd_s3, "index,y_out\n");
        $fwrite(fp_v4_imp_s2, "index,y_out\n");
        $fwrite(fp_v4_imp_s3, "index,y_out\n");
        $fwrite(fp_v4_imp_full, "index,y_out\n");
        $fwrite(fp_v4_rnd_s2, "index,y_out\n");
        $fwrite(fp_v4_rnd_s3, "index,y_out\n");
        $fwrite(fp_v4_rnd_full, "index,y_out\n");

        count_v3_imp_s2 = 0; count_v3_imp_s3 = 0;
        count_v3_rnd_s2 = 0; count_v3_rnd_s3 = 0;
        count_v4_imp_s2 = 0; count_v4_imp_s3 = 0; count_v4_imp_full = 0;
        count_v4_rnd_s2 = 0; count_v4_rnd_s3 = 0; count_v4_rnd_full = 0;
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (70000) @(posedge clk);

        $display("V4 regression counts: S2=%0d S3=%0d full=%0d",
                 count_v4_imp_s2, count_v4_imp_s3, count_v4_imp_full);
        $fclose(fp_v3_imp_s2); $fclose(fp_v3_imp_s3);
        $fclose(fp_v3_rnd_s2); $fclose(fp_v3_rnd_s3);
        $fclose(fp_v4_imp_s2); $fclose(fp_v4_imp_s3);
        $fclose(fp_v4_imp_full); $fclose(fp_v4_rnd_s2);
        $fclose(fp_v4_rnd_s3); $fclose(fp_v4_rnd_full);
        $finish;
    end

endmodule
