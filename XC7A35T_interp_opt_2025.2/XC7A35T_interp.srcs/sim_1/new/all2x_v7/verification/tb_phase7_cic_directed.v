`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_phase7_cic_directed.v
// 模块名       : tb_phase7_cic_directed
// 功能简述     : Phase 7 正式 N=3 CIC16 核心定向位真测试。
//                检查三级 comb 冲激符号、每输入恰好 16 个连续
//                有效输出、burst 剩余计数以及 MATLAB/RTL 0 LSB。
//
// 当前默认配置：
//                  输入位宽：20bit signed
//                  CIC 参数：R=16，M=1，N=3
//                  末级裁剪：0 LSB
//                  定向向量：653 点
//                  有效冲洗：3 点
//                  期望输出：(653+3)*16=10496 点
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-14
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-14：新增 CIC 定向、节拍与位真联合测试。
//=============================================================

module tb_phase7_cic_directed;

    localparam integer VECTOR_INPUT_COUNT = 653;
    localparam integer FLUSH_INPUT_COUNT = 3;
    localparam integer ACTUAL_INPUT_COUNT =
        VECTOR_INPUT_COUNT + FLUSH_INPUT_COUNT;
    localparam integer OUTPUT_COUNT = ACTUAL_INPUT_COUNT * 16;

    reg clk;
    reg rst_n;
    reg signed [19:0] x_in;
    reg x_in_valid;
    reg signed [19:0] input_mem [0:VECTOR_INPUT_COUNT-1];
    reg signed [19:0] expected_mem [0:OUTPUT_COUNT-1];

    wire signed [19:0] y_out;
    wire y_out_valid;
    wire [4:0] burst_remaining;
    wire burst_pending;

    integer input_index;
    integer flush_index;
    integer output_index;
    integer mismatch_count;
    integer hole_count;
    integer stream_started;
    integer expected_comb;
    integer phase_index;

    cic_interp16_core_ce #(
        .DATA_W          (20),
        .CIC_ORDER       (3),
        .FINAL_PRUNE_LSB (0)
    ) u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .ce_out(1'b1),
        .x_in(x_in),
        .x_in_valid(x_in_valid),
        .y_out(y_out),
        .y_out_valid(y_out_valid),
        .burst_remaining_dbg(burst_remaining),
        .pending_dbg(burst_pending)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(negedge clk) begin
        if (rst_n) begin
            if (y_out_valid) begin
                stream_started = 1;
                if (^y_out === 1'bx) begin
                    mismatch_count = mismatch_count + 1;
                    $display("CIC unknown output index=%0d", output_index);
                end
                else if (output_index >= OUTPUT_COUNT) begin
                    mismatch_count = mismatch_count + 1;
                    $display("CIC produced extra output index=%0d value=%0d",
                        output_index, $signed(y_out));
                end
                else if (y_out !== expected_mem[output_index]) begin
                    mismatch_count = mismatch_count + 1;
                    if (mismatch_count <= 20)
                        $display("CIC mismatch index=%0d actual=%0d expected=%0d",
                            output_index, $signed(y_out),
                            $signed(expected_mem[output_index]));
                end

                phase_index = output_index % 16;
                if (burst_remaining !== 15-phase_index) begin
                    mismatch_count = mismatch_count + 1;
                    if (mismatch_count <= 20)
                        $display("CIC burst count error index=%0d phase=%0d remaining=%0d",
                            output_index, phase_index, burst_remaining);
                end
                output_index = output_index + 1;
            end
            else if (stream_started != 0 && output_index < OUTPUT_COUNT) begin
                hole_count = hole_count + 1;
                mismatch_count = mismatch_count + 1;
                $display("CIC valid hole before output index=%0d", output_index);
            end
        end
    end

    task check_comb_impulse;
        input integer impulse_index;
        begin
            case (impulse_index)
                0: expected_comb = 1;
                1: expected_comb = -3;
                2: expected_comb = 3;
                default: expected_comb = -1;
            endcase
            #1;
            if ($signed(u_dut.comb_stage_output[2]) !== expected_comb) begin
                mismatch_count = mismatch_count + 1;
                $display("Comb impulse error index=%0d actual=%0d expected=%0d",
                    impulse_index,
                    $signed(u_dut.comb_stage_output[2]), expected_comb);
            end
        end
    endtask

    task check_reset_state;
        begin
            #1;
            if (y_out_valid !== 1'b0 || burst_pending !== 1'b0 ||
                    burst_remaining !== 5'd0 ||
                    u_dut.comb_delay[0] !== 32'sd0 ||
                    u_dut.comb_delay[1] !== 32'sd0 ||
                    u_dut.comb_delay[2] !== 32'sd0 ||
                    u_dut.integrator_state[0] !== 32'sd0 ||
                    u_dut.integrator_state[1] !== 32'sd0 ||
                    u_dut.final_integrator_state !== 32'sd0 ||
                    u_dut.burst_sample !== 32'sd0) begin
                mismatch_count = mismatch_count + 1;
                $display("CIC reset state is not completely zero");
            end
        end
    endtask

    initial begin
        $readmemh("cic_directed_input_20bit.mem", input_mem);
        $readmemh("cic_directed_golden_20bit.mem", expected_mem);

        rst_n = 1'b0;
        x_in = 20'sd0;
        x_in_valid = 1'b0;
        input_index = 0;
        output_index = 0;
        mismatch_count = 0;
        hole_count = 0;
        stream_started = 0;

        repeat (5) @(negedge clk);
        check_reset_state();
        rst_n = 1'b1;

        for (input_index = 0; input_index < VECTOR_INPUT_COUNT;
             input_index = input_index + 1) begin
            @(negedge clk);
            x_in = input_mem[input_index];
            x_in_valid = 1'b1;
            if (input_index < 4)
                check_comb_impulse(input_index);
            @(negedge clk);
            x_in_valid = 1'b0;
            x_in = 20'sd0;
            repeat (14) @(negedge clk);
        end

        for (flush_index = 0; flush_index < FLUSH_INPUT_COUNT;
             flush_index = flush_index + 1) begin
            @(negedge clk);
            x_in = 20'sd0;
            x_in_valid = 1'b1;
            @(negedge clk);
            x_in_valid = 1'b0;
            repeat (14) @(negedge clk);
        end

        while (output_index < OUTPUT_COUNT)
            @(negedge clk);
        repeat (2) @(negedge clk);

        if (output_index != OUTPUT_COUNT || hole_count != 0 ||
                mismatch_count != 0)
            $fatal(1, "PHASE7 CIC DIRECTED FAIL output=%0d/%0d holes=%0d mismatch=%0d",
                output_index, OUTPUT_COUNT, hole_count, mismatch_count);

        $display("PHASE7 CIC DIRECTED PASS: %0d actual valid inputs, comb, cadence and %0d outputs all 0 LSB.",
            ACTUAL_INPUT_COUNT, OUTPUT_COUNT);
        $finish;
    end

endmodule
