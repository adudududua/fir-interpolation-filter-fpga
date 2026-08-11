`timescale 1ns / 1ps

module tb_cic_two24_simultaneous_equiv;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg signed [20:0] x_in = 21'sd0;
    reg x_in_valid = 1'b0;
    wire ce_out = 1'b1;

    wire signed [19:0] y_ref;
    wire y_ref_valid;
    wire signed [19:0] y_cand;
    wire y_cand_valid;

    integer seed = 32'h54c19a73;
    integer cycle_count = 0;
    integer input_count = 0;
    integer output_count = 0;
    integer mismatch_count = 0;
    integer reset_count = 0;

    always #5 clk = ~clk;

    cic_interp16_n3_hold2_dsp_ce #(
        .DATA_W(21), .OUTPUT_W(20), .FINAL_PRUNE_LSB(0),
        .BURST_COUNTER_USE_DSP(0), .INTEGRATOR_DSP_MODE(2)
    ) u_ref (
        .clk(clk), .rst_n(rst_n), .ce_out(ce_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(y_ref), .y_out_valid(y_ref_valid),
        .burst_remaining_dbg(), .pending_dbg(), .comb_busy_dbg()
    );

    cic_interp16_n3_hold2_two24_simultaneous_ce u_cand (
        .clk(clk), .rst_n(rst_n), .ce_out(ce_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(y_cand), .y_out_valid(y_cand_valid),
        .burst_remaining_dbg(), .pending_dbg(), .comb_busy_dbg()
    );

    always @(negedge clk) begin
        if (!rst_n) begin
            cycle_count <= 0;
            x_in_valid <= 1'b0;
        end
        else begin
            cycle_count <= cycle_count + 1;
            x_in_valid <= 1'b0;
            // The formal chain presents one CIC input every 16 clocks.
            if ((cycle_count & 15) == 0) begin
                case (input_count)
                    0: x_in <= 21'sd0;
                    1: x_in <= 21'sd1048575;
                    2: x_in <= -21'sd1048576;
                    3: x_in <= 21'sd1;
                    4: x_in <= -21'sd1;
                    default: x_in <= $random(seed);
                endcase
                x_in_valid <= 1'b1;
                input_count <= input_count + 1;
            end

            if (y_ref_valid !== y_cand_valid) begin
                $display("VALID mismatch cycle=%0d ref=%0b cand=%0b",
                         cycle_count, y_ref_valid, y_cand_valid);
                mismatch_count <= mismatch_count + 1;
            end
            if (y_ref_valid && y_cand_valid) begin
                if ($signed(y_ref) !== $signed(y_cand)) begin
                    $display("DATA mismatch output=%0d ref=%0d cand=%0d",
                             output_count, $signed(y_ref), $signed(y_cand));
                    mismatch_count <= mismatch_count + 1;
                end
                output_count <= output_count + 1;
            end
        end
    end

    initial begin
        // UNISIM GSR remains active for the first 100 ns.
        repeat (20) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        wait (output_count >= 2048);
        @(negedge clk);
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        reset_count = reset_count + 1;

        wait (output_count >= 6144);
        if (mismatch_count != 0 || reset_count != 1)
            $fatal(1,
                "SIMULTANEOUS TWO24 FAIL outputs=%0d mismatch=%0d reset=%0d",
                output_count, mismatch_count, reset_count);
        $display("SIMULTANEOUS TWO24 PASS: outputs=%0d, II=1, 0 LSB",
                 output_count);
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "SIMULTANEOUS TWO24 TIMEOUT outputs=%0d mismatch=%0d",
               output_count, mismatch_count);
    end
endmodule
