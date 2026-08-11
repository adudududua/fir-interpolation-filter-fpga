`timescale 1ns / 1ps

module tb_cic_two24_simultaneous_random_ce_equiv;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg ce_out = 1'b0;
    reg signed [20:0] x_in = 21'sd0;
    reg x_in_valid = 1'b0;

    wire signed [19:0] y_ref;
    wire y_ref_valid;
    wire signed [19:0] y_cand;
    wire y_cand_valid;

    integer seed = 32'h2a71c09d;
    integer ce_wait = 0;
    integer inputs_sent = 0;
    integer outputs_since_input = 16;
    integer outputs_checked = 0;
    integer mismatch_count = 0;
    integer settle_cycles = 0;
    reg reset_completed = 1'b0;

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
            ce_out <= 1'b0;
            x_in_valid <= 1'b0;
            ce_wait <= 0;
            outputs_since_input <= 16;
            settle_cycles <= 0;
        end
        else begin
            if (y_ref_valid !== y_cand_valid) begin
                $display("VALID mismatch sample=%0d ref=%0b cand=%0b",
                         outputs_checked, y_ref_valid, y_cand_valid);
                mismatch_count <= mismatch_count + 1;
            end
            if (y_ref_valid && y_cand_valid) begin
                if ($signed(y_ref) !== $signed(y_cand)) begin
                    $display("DATA mismatch sample=%0d ref=%0d cand=%0d",
                             outputs_checked, $signed(y_ref), $signed(y_cand));
                    mismatch_count <= mismatch_count + 1;
                end
                outputs_checked <= outputs_checked + 1;
                outputs_since_input <= outputs_since_input + 1;
            end

            x_in_valid <= 1'b0;
            if (settle_cycles != 0)
                settle_cycles <= settle_cycles - 1;
            else if (outputs_since_input >= 16 && inputs_sent < 340) begin
                case (inputs_sent)
                    0: x_in <= 21'sd0;
                    1: x_in <= 21'sd1048575;
                    2: x_in <= -21'sd1048576;
                    3: x_in <= 21'sd1;
                    4: x_in <= -21'sd1;
                    default: x_in <= $random(seed);
                endcase
                x_in_valid <= 1'b1;
                inputs_sent <= inputs_sent + 1;
                outputs_since_input <= 0;
                settle_cycles <= 6;
            end

            if (ce_wait == 0) begin
                ce_out <= 1'b1;
                if (inputs_sent < 120)
                    ce_wait <= 2;
                else
                    ce_wait <= 2 + ($random(seed) & 3);
            end
            else begin
                ce_out <= 1'b0;
                ce_wait <= ce_wait - 1;
            end
        end
    end

    initial begin
        repeat (20) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        wait (outputs_checked >= 2048);
        @(negedge clk);
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        reset_completed = 1'b1;

        wait (inputs_sent >= 340 && outputs_since_input >= 16);
        repeat (20) @(posedge clk);
        if (!reset_completed || mismatch_count != 0)
            $fatal(1,
                "SIMULTANEOUS RANDOM-CE FAIL outputs=%0d mismatch=%0d reset=%0b",
                outputs_checked, mismatch_count, reset_completed);
        $display("SIMULTANEOUS RANDOM-CE PASS: outputs=%0d, random CE/reset, 0 LSB",
                 outputs_checked);
        $finish;
    end

    initial begin
        #6000000;
        $fatal(1, "SIMULTANEOUS RANDOM-CE TIMEOUT outputs=%0d",
               outputs_checked);
    end
endmodule
