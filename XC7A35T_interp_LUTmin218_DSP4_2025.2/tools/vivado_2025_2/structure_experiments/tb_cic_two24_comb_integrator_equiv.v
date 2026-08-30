`timescale 1ns / 1ps

// Stream-equivalence test.  The candidate deliberately delays valid by one
// clock while the final integrator consumes the registered TWO24 result, so a
// FIFO compares every valid sample rather than requiring identical cycles.
module tb_cic_two24_comb_integrator_equiv;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg ce_out = 1'b0;
    reg signed [20:0] x_in = 21'sd0;
    reg x_in_valid = 1'b0;

    wire signed [19:0] y_ref;
    wire y_ref_valid;
    wire signed [19:0] y_cand;
    wire y_cand_valid;

    reg signed [19:0] expected_fifo [0:31];
    integer fifo_wr = 0;
    integer fifo_rd = 0;
    integer fifo_count = 0;
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

    cic_interp16_n3_hold2_two24_comb_integrator_ce u_cand (
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
            fifo_wr <= 0;
            fifo_rd <= 0;
            fifo_count <= 0;
        end
        else begin
            if (y_ref_valid) begin
                if (fifo_count >= 31)
                    $fatal(1, "Reference FIFO overflow");
                expected_fifo[fifo_wr] <= y_ref;
                fifo_wr <= (fifo_wr + 1) & 31;
                fifo_count <= fifo_count + 1;
                outputs_since_input <= outputs_since_input + 1;
            end

            if (y_cand_valid) begin
                if (fifo_count == 0) begin
                    $display("Candidate output without reference sample=%0d",
                             outputs_checked);
                    mismatch_count <= mismatch_count + 1;
                end
                else begin
                    if ($signed(y_cand) !== $signed(expected_fifo[fifo_rd])) begin
                        $display("DATA mismatch sample=%0d ref=%0d cand=%0d",
                                 outputs_checked,
                                 $signed(expected_fifo[fifo_rd]),
                                 $signed(y_cand));
                        mismatch_count <= mismatch_count + 1;
                    end
                    fifo_rd <= (fifo_rd + 1) & 31;
                    fifo_count <= fifo_count - 1;
                    outputs_checked <= outputs_checked + 1;
                end
            end

            x_in_valid <= 1'b0;
            if (settle_cycles != 0)
                settle_cycles <= settle_cycles - 1;
            else if (outputs_since_input >= 16 && inputs_sent < 340) begin
                x_in <= $random(seed);
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
        // The UNISIM global set/reset remains active for the first 100 ns.
        // Keep the explicit reset asserted beyond that interval so the
        // primitive-based reference and Fabric candidate start identically.
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
        if (!reset_completed || mismatch_count != 0 || fifo_count != 0)
            $fatal(1,
                "CIC TWO24 EQUIV FAIL outputs=%0d mismatch=%0d fifo=%0d reset=%0b",
                outputs_checked, mismatch_count, fifo_count,
                reset_completed);
        $display("CIC TWO24 EQUIV PASS: outputs=%0d, fixed/random CE and mid-burst reset, 0 LSB",
                 outputs_checked);
        $finish;
    end

    initial begin
        #6000000;
        $fatal(1, "CIC TWO24 EQUIV TIMEOUT outputs=%0d fifo=%0d",
               outputs_checked, fifo_count);
    end
endmodule
