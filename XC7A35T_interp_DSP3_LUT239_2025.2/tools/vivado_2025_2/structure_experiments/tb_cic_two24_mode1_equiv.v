`timescale 1ns / 1ps

module tb_cic_two24_mode1_equiv;
    localparam integer INPUT_COUNT = 1024;
    localparam integer EXPECTED_OUTPUTS = INPUT_COUNT * 16;

    reg clk;
    reg rst_n;
    reg ce_out;
    reg signed [20:0] x_in;
    reg x_in_valid;
    wire signed [19:0] reference_y;
    wire reference_valid;
    wire signed [19:0] candidate_y;
    wire candidate_valid;
    integer input_count;
    integer output_count;
    integer cycle_count;
    reg [31:0] lfsr;

    cic_interp16_n3_hold2_dsp_ce #(
        .DATA_W(21), .OUTPUT_W(20), .FINAL_PRUNE_LSB(0),
        .BURST_COUNTER_USE_DSP(0), .INTEGRATOR_DSP_MODE(1)
    ) u_reference (
        .clk(clk), .rst_n(rst_n), .ce_out(ce_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(reference_y), .y_out_valid(reference_valid),
        .burst_remaining_dbg(), .pending_dbg(), .comb_busy_dbg()
    );

    cic_interp16_n3_hold2_dsp_ce_two24_candidate #(
        .DATA_W(21), .OUTPUT_W(20), .FINAL_PRUNE_LSB(0),
        .BURST_COUNTER_USE_DSP(0), .INTEGRATOR_DSP_MODE(1)
    ) u_candidate (
        .clk(clk), .rst_n(rst_n), .ce_out(ce_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(candidate_y), .y_out_valid(candidate_valid),
        .burst_remaining_dbg(), .pending_dbg(), .comb_busy_dbg()
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            ce_out <= 1'b0;
            x_in_valid <= 1'b0;
            x_in <= 21'sd0;
            input_count <= 0;
            output_count <= 0;
            cycle_count <= 0;
            lfsr <= 32'h6e624eb7;
        end
        else begin
            ce_out <= (cycle_count[3:0] == 4'd15);
            x_in_valid <= 1'b0;
            if (cycle_count[7:0] == 8'd15 && input_count < INPUT_COUNT) begin
                x_in_valid <= 1'b1;
                case (input_count)
                    0: x_in <= 21'sd1;
                    1: x_in <= 21'sh0fffff;
                    2: x_in <= -21'sh100000;
                    3: x_in <= 21'sd0;
                    default: x_in <= lfsr[20:0];
                endcase
                input_count <= input_count + 1;
                lfsr <= {lfsr[30:0],
                         lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
            end
            if (reference_valid !== candidate_valid) begin
                $display("FAIL valid mismatch at cycle %0d", cycle_count);
                $fatal(1);
            end
            if (reference_valid) begin
                if (reference_y !== candidate_y) begin
                    $display("FAIL output %0d candidate=%0d reference=%0d",
                             output_count, candidate_y, reference_y);
                    $fatal(1);
                end
                output_count <= output_count + 1;
            end
            cycle_count <= cycle_count + 1;
            if (output_count == EXPECTED_OUTPUTS) begin
                $display("PASS TWO24 mode-1 CIC: %0d outputs, max error 0 LSB",
                         output_count);
                $finish;
            end
            if (cycle_count > INPUT_COUNT*256 + 4096) begin
                $display("FAIL timeout inputs=%0d outputs=%0d",
                         input_count, output_count);
                $fatal(1);
            end
        end
    end

    initial begin
        rst_n = 1'b0;
        ce_out = 1'b0;
        x_in_valid = 1'b0;
        x_in = 21'sd0;
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
    end
endmodule
