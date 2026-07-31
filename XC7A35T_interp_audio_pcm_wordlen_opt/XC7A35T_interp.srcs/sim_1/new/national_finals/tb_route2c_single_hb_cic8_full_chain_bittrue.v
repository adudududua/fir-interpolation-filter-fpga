`timescale 1ns / 1ps

module tb_route2c_single_hb_cic8_full_chain_bittrue;

    localparam integer MAX_INPUT_COUNT = 1024;
    localparam integer MAX_Y4_COUNT = 4301;
    localparam integer MAX_Y8_COUNT = 8611;
    localparam integer MAX_Y128_COUNT = 137840;
    localparam integer SHIFT_4X = 3;
    localparam integer SHIFT_8X = 7;
    localparam integer SHIFT_128X = 136;

    reg clk;
    reg rst_n;
    reg [6:0] ce_cnt;
    reg input_phase;
    reg signed [23:0] x_in;
    reg x_in_valid;

    reg signed [23:0] input_mem [0:MAX_INPUT_COUNT-1];
    reg signed [23:0] y4_expected [0:MAX_Y4_COUNT-1];
    reg signed [23:0] y8_expected [0:MAX_Y8_COUNT-1];
    reg signed [23:0] y128_expected [0:MAX_Y128_COUNT-1];

    integer active_case;
    integer active_input_count;
    integer expected_y4_count;
    integer expected_y8_count;
    integer expected_y128_count;
    integer input_index;
    integer y4_skip_count;
    integer y8_skip_count;
    integer y128_skip_count;
    integer y4_index;
    integer y8_index;
    integer y128_index;
    integer mismatch_count;
    integer timeout_count;
    integer case_index;

    wire ce2_out = (ce_cnt[5:0] == 6'b000000);
    wire ce4_out = (ce_cnt[4:0] == 5'b00000);
    wire ce8_out = (ce_cnt[3:0] == 4'b0000);
    wire ce16_out = (ce_cnt[2:0] == 3'b000);
    wire ce32_out = (ce_cnt[1:0] == 2'b00);
    wire ce64_out = (ce_cnt[0] == 1'b0);
    wire ce128_out = 1'b1;

    wire signed [23:0] y_out;
    wire y_out_valid;
    wire signed [23:0] dbg_y4;
    wire dbg_y4_valid;
    wire signed [23:0] dbg_y8;
    wire dbg_y8_valid;

    interp128_route2_single_hb_cic8_top_ce u_dut (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out),
        .ce8_out(ce8_out), .ce16_out(ce16_out),
        .ce32_out(ce32_out), .ce64_out(ce64_out),
        .ce128_out(ce128_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(y_out), .y_out_valid(y_out_valid),
        .dbg_y2(), .dbg_y2_valid(),
        .dbg_y4(dbg_y4), .dbg_y4_valid(dbg_y4_valid),
        .dbg_y8(dbg_y8), .dbg_y8_valid(dbg_y8_valid),
        .dbg_y16(), .dbg_y16_valid(),
        .dbg_y32(), .dbg_y32_valid(),
        .dbg_y64(), .dbg_y64_valid()
    );

    initial begin
        clk = 1'b0;
        forever #10.416667 clk = ~clk;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ce_cnt <= 7'd0;
            input_phase <= 1'b1;
            input_index <= 0;
            x_in <= input_mem[0];
        end
        else begin
            ce_cnt <= ce_cnt+7'd1;
            if (ce2_out) begin
                if (!input_phase) begin
                    input_index <= input_index+1;
                    if (input_index+1 < active_input_count)
                        x_in <= input_mem[input_index+1];
                    else
                        x_in <= 24'sd0;
                end
                input_phase <= ~input_phase;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y4_skip_count <= 0;
            y8_skip_count <= 0;
            y128_skip_count <= 0;
            y4_index <= 0;
            y8_index <= 0;
            y128_index <= 0;
            mismatch_count <= 0;
        end
        else if (active_case != 0) begin
            if (dbg_y4_valid) begin
                if (^dbg_y4 === 1'bx)
                    report_unknown(4, y4_index);
                else if (y4_skip_count < SHIFT_4X)
                    y4_skip_count <= y4_skip_count+1;
                else if (y4_index < expected_y4_count) begin
                    if (dbg_y4 !== y4_expected[y4_index])
                        report_mismatch(4, y4_index, dbg_y4,
                            y4_expected[y4_index]);
                    y4_index <= y4_index+1;
                end
            end
            if (dbg_y8_valid) begin
                if (^dbg_y8 === 1'bx)
                    report_unknown(8, y8_index);
                else if (y8_skip_count < SHIFT_8X)
                    y8_skip_count <= y8_skip_count+1;
                else if (y8_index < expected_y8_count) begin
                    if (dbg_y8 !== y8_expected[y8_index])
                        report_mismatch(8, y8_index, dbg_y8,
                            y8_expected[y8_index]);
                    y8_index <= y8_index+1;
                end
            end
            if (y_out_valid) begin
                if (^y_out === 1'bx)
                    report_unknown(128, y128_index);
                else if (y128_skip_count < SHIFT_128X)
                    y128_skip_count <= y128_skip_count+1;
                else if (y128_index < expected_y128_count) begin
                    if (y_out !== y128_expected[y128_index])
                        report_mismatch(128, y128_index, y_out,
                            y128_expected[y128_index]);
                    y128_index <= y128_index+1;
                end
            end
        end
    end

    task report_mismatch;
        input integer rate_value;
        input integer sample_index;
        input signed [23:0] actual_value;
        input signed [23:0] expected_value;
        begin
            mismatch_count = mismatch_count+1;
            if (mismatch_count <= 20)
                $display("Mismatch case=%0d rate=%0dx index=%0d actual=%0d expected=%0d",
                    active_case, rate_value, sample_index,
                    actual_value, expected_value);
        end
    endtask

    task report_unknown;
        input integer rate_value;
        input integer sample_index;
        begin
            mismatch_count = mismatch_count+1;
            $display("Unknown case=%0d rate=%0dx index=%0d",
                active_case, rate_value, sample_index);
        end
    endtask

    task apply_reset;
        begin
            rst_n = 1'b0;
            x_in_valid = 1'b0;
            repeat (8) @(negedge clk);
            rst_n = 1'b1;
            x_in_valid = 1'b1;
            repeat (4) @(negedge clk);
        end
    endtask

    task load_case;
        input integer case_value;
        begin
            case (case_value)
                1: begin
                    $readmemh("impulse_input_24bit.mem", input_mem);
                    $readmemh("impulse_y4_golden_24bit.mem", y4_expected);
                    $readmemh("impulse_y8_golden_24bit.mem", y8_expected);
                    $readmemh("impulse_y128_golden_24bit.mem", y128_expected);
                    active_input_count = 256;
                    expected_y4_count = 1229;
                    expected_y8_count = 2467;
                    expected_y128_count = 39536;
                end
                2: begin
                    $readmemh("random_seed01_input_24bit.mem", input_mem);
                    $readmemh("random_seed01_y4_golden_24bit.mem", y4_expected);
                    $readmemh("random_seed01_y8_golden_24bit.mem", y8_expected);
                    $readmemh("random_seed01_y128_golden_24bit.mem", y128_expected);
                    active_input_count = 1024;
                    expected_y4_count = 4301;
                    expected_y8_count = 8611;
                    expected_y128_count = 137840;
                end
                default: begin
                    $readmemh("random_fullscale_input_24bit.mem", input_mem);
                    $readmemh("random_fullscale_y4_golden_24bit.mem", y4_expected);
                    $readmemh("random_fullscale_y8_golden_24bit.mem", y8_expected);
                    $readmemh("random_fullscale_y128_golden_24bit.mem", y128_expected);
                    active_input_count = 512;
                    expected_y4_count = 2253;
                    expected_y8_count = 4515;
                    expected_y128_count = 72304;
                end
            endcase
        end
    endtask

    task run_case;
        input integer case_value;
        begin
            active_case = 0;
            load_case(case_value);
            active_case = case_value;
            apply_reset();
            timeout_count = 0;
            while ((y128_index < expected_y128_count ||
                    y8_index < expected_y8_count ||
                    y4_index < expected_y4_count) &&
                   timeout_count < expected_y128_count+200000) begin
                @(negedge clk);
                timeout_count = timeout_count+1;
            end
            if (y4_index != expected_y4_count ||
                    y8_index != expected_y8_count ||
                    y128_index != expected_y128_count) begin
                $display("Count case=%0d y4=%0d/%0d y8=%0d/%0d y128=%0d/%0d",
                    case_value, y4_index, expected_y4_count,
                    y8_index, expected_y8_count,
                    y128_index, expected_y128_count);
                mismatch_count = mismatch_count+1;
            end
            if (mismatch_count != 0)
                $fatal(1, "ROUTE2C FULL CHAIN case=%0d FAIL mismatches=%0d",
                    case_value, mismatch_count);
            $display("ROUTE2C FULL CHAIN case=%0d PASS y4=%0d y8=%0d y128=%0d",
                case_value, y4_index, y8_index, y128_index);
            active_case = 0;
        end
    endtask

    initial begin
        rst_n = 1'b0;
        x_in = 24'sd0;
        x_in_valid = 1'b0;
        active_case = 0;
        active_input_count = 0;
        expected_y4_count = 0;
        expected_y8_count = 0;
        expected_y128_count = 0;
        for (case_index = 1; case_index <= 3;
             case_index = case_index+1)
            run_case(case_index);
        $display("ROUTE2C FULL CHAIN BITTRUE PASS: impulse + nominal + full-scale random, all nodes 0 LSB.");
        $finish;
    end

endmodule
