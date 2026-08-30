`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_cic_interp16_folded_core.v
// 模块名       : tb_cic_interp16_folded_core
// 功能简述     : Phase 7 折叠补偿方案的 CIC 核心位真测试。
//                N=3 与 N=4 分别读取对应 Stage3 的 20bit 输出，
//                对冲激和随机 PCM 的每个 CIC 有效输出执行严格
//                0 LSB 比较。N=3 保持全精度，N=4 末级丢 7 LSB。
//
// 当前默认配置：
//                  系统时钟：48MHz 等效
//                  低速输入：每 128 个系统时钟一个样点
//                  高速 CE ：每 8 个系统时钟一个脉冲
//                  插值倍率：16
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-13
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-13：新增折叠补偿 N=3/N=4 CIC 0 LSB 对拍。
//=============================================================

module tb_cic_interp16_folded_core;

    localparam integer DATA_W = 20;
    localparam integer IMPULSE_INPUT_COUNT = 2499;
    localparam integer RANDOM_INPUT_COUNT = 1475;
    localparam integer N3_IMPULSE_OUTPUT_COUNT = 40032;
    localparam integer N4_IMPULSE_OUTPUT_COUNT = 40048;
    localparam integer N3_RANDOM_OUTPUT_COUNT = 23648;
    localparam integer N4_RANDOM_OUTPUT_COUNT = 23664;
    localparam integer FLUSH_LOW_SAMPLES = 4;

    reg clk;
    reg rst_n;
    reg [2:0] ce_divider;
    wire ce_out;
    reg signed [DATA_W-1:0] x_n3;
    reg signed [DATA_W-1:0] x_n4;
    reg x_in_valid;

    wire signed [DATA_W-1:0] y_n3;
    wire y_n3_valid;
    wire signed [DATA_W-1:0] y_n4;
    wire y_n4_valid;

    reg signed [DATA_W-1:0] n3_impulse_input
        [0:IMPULSE_INPUT_COUNT-1];
    reg signed [DATA_W-1:0] n4_impulse_input
        [0:IMPULSE_INPUT_COUNT-1];
    reg signed [DATA_W-1:0] n3_random_input
        [0:RANDOM_INPUT_COUNT-1];
    reg signed [DATA_W-1:0] n4_random_input
        [0:RANDOM_INPUT_COUNT-1];
    reg signed [DATA_W-1:0] n3_impulse_expected
        [0:N3_IMPULSE_OUTPUT_COUNT-1];
    reg signed [DATA_W-1:0] n4_impulse_expected
        [0:N4_IMPULSE_OUTPUT_COUNT-1];
    reg signed [DATA_W-1:0] n3_random_expected
        [0:N3_RANDOM_OUTPUT_COUNT-1];
    reg signed [DATA_W-1:0] n4_random_expected
        [0:N4_RANDOM_OUTPUT_COUNT-1];

    integer active_case;
    integer n3_output_index;
    integer n4_output_index;
    integer mismatch_count;
    integer drive_index;
    integer timeout_count;

    assign ce_out = rst_n && (ce_divider == 3'd0);

    cic_interp16_core_ce #(
        .DATA_W          (DATA_W),
        .CIC_ORDER       (3),
        .FINAL_PRUNE_LSB (0)
    ) u_cic_interp16_core_n3 (
        .clk(clk), .rst_n(rst_n), .ce_out(ce_out),
        .x_in(x_n3), .x_in_valid(x_in_valid),
        .y_out(y_n3), .y_out_valid(y_n3_valid),
        .burst_remaining_dbg(), .pending_dbg()
    );

    cic_interp16_core_ce #(
        .DATA_W          (DATA_W),
        .CIC_ORDER       (4),
        .FINAL_PRUNE_LSB (7)
    ) u_cic_interp16_core_n4 (
        .clk(clk), .rst_n(rst_n), .ce_out(ce_out),
        .x_in(x_n4), .x_in_valid(x_in_valid),
        .y_out(y_n4), .y_out_valid(y_n4_valid),
        .burst_remaining_dbg(), .pending_dbg()
    );

    initial begin
        clk = 1'b0;
        forever #10.416667 clk = ~clk;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ce_divider <= 3'd0;
        else if (ce_divider == 3'd7)
            ce_divider <= 3'd0;
        else
            ce_divider <= ce_divider + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            n3_output_index <= 0;
            n4_output_index <= 0;
            mismatch_count <= 0;
        end
        else begin
            if (y_n3_valid) begin
                if (active_case == 1) begin
                    if (n3_output_index < N3_IMPULSE_OUTPUT_COUNT) begin
                        if (y_n3 !== n3_impulse_expected[n3_output_index])
                            report_mismatch(3, n3_output_index, y_n3,
                                n3_impulse_expected[n3_output_index]);
                    end
                    else if (y_n3 !== {DATA_W{1'b0}})
                        report_mismatch(3, n3_output_index, y_n3,
                            {DATA_W{1'b0}});
                end
                else begin
                    if (n3_output_index < N3_RANDOM_OUTPUT_COUNT) begin
                        if (y_n3 !== n3_random_expected[n3_output_index])
                            report_mismatch(3, n3_output_index, y_n3,
                                n3_random_expected[n3_output_index]);
                    end
                    else if (y_n3 !== {DATA_W{1'b0}})
                        report_mismatch(3, n3_output_index, y_n3,
                            {DATA_W{1'b0}});
                end
                n3_output_index <= n3_output_index + 1;
            end

            if (y_n4_valid) begin
                if (active_case == 1) begin
                    if (n4_output_index < N4_IMPULSE_OUTPUT_COUNT &&
                            y_n4 !== n4_impulse_expected[n4_output_index])
                        report_mismatch(4, n4_output_index, y_n4,
                            n4_impulse_expected[n4_output_index]);
                end
                else begin
                    if (n4_output_index < N4_RANDOM_OUTPUT_COUNT &&
                            y_n4 !== n4_random_expected[n4_output_index])
                        report_mismatch(4, n4_output_index, y_n4,
                            n4_random_expected[n4_output_index]);
                end
                n4_output_index <= n4_output_index + 1;
            end
        end
    end

    task report_mismatch;
        input integer order_value;
        input integer sample_index;
        input signed [DATA_W-1:0] actual_value;
        input signed [DATA_W-1:0] expected_value;
        begin
            mismatch_count = mismatch_count + 1;
            if (mismatch_count <= 20)
                $display("Mismatch N=%0d index=%0d actual=%0d expected=%0d",
                    order_value, sample_index, actual_value, expected_value);
        end
    endtask

    task apply_reset;
        begin
            rst_n = 1'b0;
            x_n3 = {DATA_W{1'b0}};
            x_n4 = {DATA_W{1'b0}};
            x_in_valid = 1'b0;
            repeat (8) @(negedge clk);
            rst_n = 1'b1;
            repeat (8) @(negedge clk);
        end
    endtask

    task drive_one_case;
        input integer case_value;
        input integer input_count;
        input integer n3_expected_count;
        input integer n4_expected_count;
        begin
            active_case = case_value;
            apply_reset();

            for (drive_index = 0;
                 drive_index < input_count + FLUSH_LOW_SAMPLES;
                 drive_index = drive_index + 1) begin
                @(negedge clk);
                if (drive_index < input_count) begin
                    if (case_value == 1) begin
                        x_n3 = n3_impulse_input[drive_index];
                        x_n4 = n4_impulse_input[drive_index];
                    end
                    else begin
                        x_n3 = n3_random_input[drive_index];
                        x_n4 = n4_random_input[drive_index];
                    end
                end
                else begin
                    x_n3 = {DATA_W{1'b0}};
                    x_n4 = {DATA_W{1'b0}};
                end
                x_in_valid = 1'b1;
                @(negedge clk);
                x_in_valid = 1'b0;
                x_n3 = {DATA_W{1'b0}};
                x_n4 = {DATA_W{1'b0}};
                repeat (126) @(negedge clk);
            end

            timeout_count = 0;
            while (n4_output_index < n4_expected_count &&
                   timeout_count < 2000) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
            end

            if (n4_output_index != n4_expected_count ||
                    n3_output_index < n3_expected_count) begin
                $display("Output count error case=%0d N3=%0d N4=%0d",
                    case_value, n3_output_index, n4_output_index);
                mismatch_count = mismatch_count + 1;
            end
            if (mismatch_count == 0)
                $display("CASE %0d PASS: folded CIC N3/N4 = 0 LSB.",
                    case_value);
            else
                $fatal(1, "CASE %0d FAIL: mismatch_count=%0d",
                    case_value, mismatch_count);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        x_n3 = {DATA_W{1'b0}};
        x_n4 = {DATA_W{1'b0}};
        x_in_valid = 1'b0;
        active_case = 0;

        $readmemh("phase7_folded_n3_stage3_impulse_20bit.mem",
            n3_impulse_input);
        $readmemh("phase7_folded_n4_stage3_impulse_20bit.mem",
            n4_impulse_input);
        $readmemh("phase7_folded_n3_stage3_random_20bit.mem",
            n3_random_input);
        $readmemh("phase7_folded_n4_stage3_random_20bit.mem",
            n4_random_input);
        $readmemh("phase7_folded_n3_impulse_golden_20bit.mem",
            n3_impulse_expected);
        $readmemh("phase7_folded_n4_impulse_golden_20bit.mem",
            n4_impulse_expected);
        $readmemh("phase7_folded_n3_random_golden_20bit.mem",
            n3_random_expected);
        $readmemh("phase7_folded_n4_random_golden_20bit.mem",
            n4_random_expected);

        drive_one_case(1, IMPULSE_INPUT_COUNT,
            N3_IMPULSE_OUTPUT_COUNT, N4_IMPULSE_OUTPUT_COUNT);
        drive_one_case(2, RANDOM_INPUT_COUNT,
            N3_RANDOM_OUTPUT_COUNT, N4_RANDOM_OUTPUT_COUNT);

        $display("PHASE7 FOLDED CIC CORE BITTRUE PASS.");
        $finish;
    end

endmodule
