`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_interp128_all2x_v2_lightbridge_ce.v
// 模块名       : tb_interp128_all2x_v2_lightbridge_ce
// 功能简述     : Phase 2 最优 S2～S3 true-polyphase 加 valid-only
//                轻量桥接结构的冲激与随机 PCM 对拍测试平台。
//
//                输入文件：canonical_test_input_24bit.mem
//                输出文件：v2_lightbridge_output.csv
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-11
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-11：新增 Phase 2 轻量桥接对拍平台。
//=============================================================

module tb_interp128_all2x_v2_lightbridge_ce;

    localparam integer INPUT_COUNT = 256;

    reg clk;
    reg rst_n;
    reg [6:0] ce_cnt;
    reg signed [23:0] x_in;
    reg signed [23:0] input_mem [0:INPUT_COUNT-1];
    reg [15:0] input_idx;

    wire ce2_out = (ce_cnt[5:0] == 6'b000000);
    wire ce4_out = (ce_cnt[4:0] == 5'b00000);
    wire ce8_out = (ce_cnt[3:0] == 4'b0000);
    wire ce16_out = (ce_cnt[2:0] == 3'b000);
    wire ce32_out = (ce_cnt[1:0] == 2'b00);
    wire ce64_out = (ce_cnt[0] == 1'b0);
    wire ce128_out = 1'b1;
    wire x_in_update_ce = (ce_cnt == 7'd127);

    wire signed [23:0] y_out;
    wire y_out_valid;

    integer fp_out;
    integer valid_count;
    integer init_idx;

    interp128_all2x_v2_lightbridge_top_ce #(
        .DATA_W                       (24),
        .FIRST_CANONICAL_STAGE        (4),
        .FIRST_TRUE_POLYPHASE_STAGE   (2)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(x_in), .x_in_valid(1'b1),
        .y_out(y_out), .y_out_valid(y_out_valid),
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
        if (y_out_valid) begin
            $fwrite(fp_out, "%0d,%0d\n", valid_count, y_out);
            valid_count <= valid_count + 1;
        end
    end

    initial begin
        for (init_idx = 0; init_idx < INPUT_COUNT; init_idx = init_idx + 1)
            input_mem[init_idx] = 24'sd0;
        $readmemh("canonical_test_input_24bit.mem", input_mem);

        fp_out = $fopen("v2_lightbridge_output.csv", "w");
        $fwrite(fp_out, "index,y_out\n");
        valid_count = 0;
        rst_n = 1'b0;
        #200;
        rst_n = 1'b1;

        repeat (50000) @(posedge clk);

        $display("Phase 2 lightbridge valid count = %0d", valid_count);
        $fclose(fp_out);
        $finish;
    end

endmodule
