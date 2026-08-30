`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_interp2_stage1_strict_halfband_ce.v
// 模块名       : tb_interp2_stage1_strict_halfband_ce
// 功能简述     : Stage 1 strict-halfband true-polyphase 单元测试。
//                同时输入冲激和随机 PCM，逐样点对比 MATLAB
//                bit-true golden，并检查输出数量和 MAC 截止时间。
//
//                输入文件：
//                  v3_stage1_impulse_input_24bit.mem
//                  v3_stage1_random_input_24bit.mem
//                Golden 文件：
//                  v3_stage1_impulse_golden_24bit.mem
//                  v3_stage1_random_golden_24bit.mem
//
// 当前默认配置：
//                  仿真时钟周期：10ns
//                  Stage 1 CE   ：每 64 拍一次
//                  冲激输入     ：256 点
//                  随机输入     ：128 点
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-11
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-11：新增 Stage 1 strict-halfband 单元测试。
//=============================================================

module tb_interp2_stage1_strict_halfband_ce;

    localparam integer IMPULSE_INPUT_COUNT = 256;
    localparam integer IMPULSE_GOLDEN_COUNT = 615;
    localparam integer RANDOM_INPUT_COUNT = 128;
    localparam integer RANDOM_GOLDEN_COUNT = 359;

    reg clk;
    reg rst_n;
    reg [6:0] ce_cnt;
    reg tb_phase;

    reg signed [23:0] impulse_input_mem [0:IMPULSE_INPUT_COUNT-1];
    reg signed [23:0] impulse_golden_mem [0:IMPULSE_GOLDEN_COUNT-1];
    reg signed [23:0] random_input_mem [0:RANDOM_INPUT_COUNT-1];
    reg signed [23:0] random_golden_mem [0:RANDOM_GOLDEN_COUNT-1];

    reg signed [23:0] impulse_x;
    reg signed [23:0] random_x;
    integer impulse_input_idx;
    integer random_input_idx;
    integer impulse_golden_idx;
    integer random_golden_idx;
    integer impulse_skip_count;
    integer random_skip_count;
    integer cycle_count;

    wire ce2_out;
    wire signed [23:0] impulse_y;
    wire signed [23:0] random_y;
    wire impulse_y_valid;
    wire random_y_valid;

    assign ce2_out = (ce_cnt[5:0] == 6'b000000);

    interp2_stage1_strict_halfband_mac_ce dut_impulse (
        .clk              (clk),
        .rst_n            (rst_n),
        .ce_out           (ce2_out),
        .x_in             (impulse_x),
        .x_in_valid       (1'b1),
        .y_out            (impulse_y),
        .y_out_valid      (impulse_y_valid),
        .phase_dbg        (),
        .fir_in_dbg       (),
        .fir_in_valid_dbg ()
    );

    interp2_stage1_strict_halfband_mac_ce dut_random (
        .clk              (clk),
        .rst_n            (rst_n),
        .ce_out           (ce2_out),
        .x_in             (random_x),
        .x_in_valid       (1'b1),
        .y_out            (random_y),
        .y_out_valid      (random_y_valid),
        .phase_dbg        (),
        .fir_in_dbg       (),
        .fir_in_valid_dbg ()
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
        if (rst_n && impulse_y_valid) begin
            if (impulse_skip_count == 0) begin
                impulse_skip_count <= 1;
            end
            else if (impulse_golden_idx < IMPULSE_GOLDEN_COUNT) begin
                if (impulse_y !== impulse_golden_mem[impulse_golden_idx]) begin
                    $display("Impulse mismatch index=%0d rtl=%0d golden=%0d",
                             impulse_golden_idx, impulse_y,
                             impulse_golden_mem[impulse_golden_idx]);
                    $fatal(1, "Stage 1 impulse mismatch");
                end
                impulse_golden_idx <= impulse_golden_idx + 1;
            end
        end

        if (rst_n && random_y_valid) begin
            if (random_skip_count == 0) begin
                random_skip_count <= 1;
            end
            else if (random_golden_idx < RANDOM_GOLDEN_COUNT) begin
                if (random_y !== random_golden_mem[random_golden_idx]) begin
                    $display("Random mismatch index=%0d rtl=%0d golden=%0d",
                             random_golden_idx, random_y,
                             random_golden_mem[random_golden_idx]);
                    $fatal(1, "Stage 1 random mismatch");
                end
                random_golden_idx <= random_golden_idx + 1;
            end
        end
    end

    initial begin
        $readmemh("v3_stage1_impulse_input_24bit.mem", impulse_input_mem);
        $readmemh("v3_stage1_impulse_golden_24bit.mem", impulse_golden_mem);
        $readmemh("v3_stage1_random_input_24bit.mem", random_input_mem);
        $readmemh("v3_stage1_random_golden_24bit.mem", random_golden_mem);

        impulse_golden_idx = 0;
        random_golden_idx = 0;
        impulse_skip_count = 0;
        random_skip_count = 0;
        cycle_count = 0;
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        while ((impulse_golden_idx < IMPULSE_GOLDEN_COUNT ||
                random_golden_idx < RANDOM_GOLDEN_COUNT) &&
               cycle_count < 50000) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        if (impulse_golden_idx != IMPULSE_GOLDEN_COUNT)
            $fatal(1, "Impulse output count mismatch: %0d/%0d",
                   impulse_golden_idx, IMPULSE_GOLDEN_COUNT);
        if (random_golden_idx != RANDOM_GOLDEN_COUNT)
            $fatal(1, "Random output count mismatch: %0d/%0d",
                   random_golden_idx, RANDOM_GOLDEN_COUNT);

        $display("STAGE1_STRICT_UNIT_PASS impulse=%0d random=%0d cycles=%0d",
                 impulse_golden_idx, random_golden_idx, cycle_count);
        $finish;
    end

endmodule
