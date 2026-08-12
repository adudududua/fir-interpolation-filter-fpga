`timescale 1ns / 1ps

module tb_cic_shared_fabric_equiv;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg ce_out = 1'b0;
    reg signed [20:0] x_in = 21'sd0;
    reg x_in_valid = 1'b0;

    wire signed [19:0] y_ref;
    wire y_ref_valid;
    wire signed [19:0] y_cand;
    wire y_cand_valid;

    reg signed [19:0] expected_fifo [0:63];
    integer fifo_wr = 0;
    integer fifo_rd = 0;
    integer fifo_count = 0;
    integer seed = 32'h29c57a41;
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
        .BURST_COUNTER_USE_DSP(0), .INTEGRATOR_DSP_MODE(0)
    ) u_ref (
        .clk(clk), .rst_n(rst_n), .ce_out(ce_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(y_ref), .y_out_valid(y_ref_valid),
        .burst_remaining_dbg(), .pending_dbg(), .comb_busy_dbg()
    );

    cic_interp16_n3_hold2_shared_fabric_ce u_cand (
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
                if (fifo_count >= 63)
                    $fatal(1, "Reference FIFO overflow");
                expected_fifo[fifo_wr] <= y_ref;
                fifo_wr <= (fifo_wr + 1) & 63;
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
                    fifo_rd <= (fifo_rd + 1) & 63;
                    fifo_count <= fifo_count - 1;
                    outputs_checked <= outputs_checked + 1;
                end
            end

            x_in_valid <= 1'b0;
            if (settle_cycles != 0)
                settle_cycles <= settle_cycles - 1;
            else if (outputs_since_input >= 16 && inputs_sent < 600) begin
                case (inputs_sent)
                    0: x_in <= 21'sd0;
                    1: x_in <= 21'sd1048575;
                    2: x_in <= -21'sd1048576;
                    3: x_in <= 21'sd1;
                    4: x_in <= -21'sd1;
                    5: x_in <= 21'sd524287;
                    6: x_in <= -21'sd524288;
                    default: x_in <= $random(seed);
                endcase
                x_in_valid <= 1'b1;
                inputs_sent <= inputs_sent + 1;
                outputs_since_input <= 0;
                settle_cycles <= 6;
            end

            if (ce_wait == 0) begin
                ce_out <= 1'b1;
                // First 260 inputs exercise the maximum legal rate: one
                // inactive system clock between consecutive ce_out pulses.
                if (inputs_sent < 260)
                    ce_wait <= 1;
                else
                    ce_wait <= 1 + ($random(seed) & 7);
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

        wait (outputs_checked >= 3072);
        // Reset while a 16-sample burst is active.  Both implementations must
        // discard all pending state and resume with an empty output FIFO.
        @(negedge clk);
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        reset_completed = 1'b1;

        wait (inputs_sent >= 600 && outputs_since_input >= 16);
        repeat (40) @(posedge clk);
        if (!reset_completed || mismatch_count != 0 || fifo_count != 0)
            $fatal(1,
                "SHARED FABRIC EQUIV FAIL outputs=%0d mismatch=%0d fifo=%0d reset=%0b",
                outputs_checked, mismatch_count, fifo_count, reset_completed);
        $display("SHARED FABRIC EQUIV PASS: outputs=%0d, directed/random data, max-rate/random CE and mid-burst reset, 0 LSB",
                 outputs_checked);
        $finish;
    end

    initial begin
        #12000000;
        $fatal(1, "SHARED FABRIC EQUIV TIMEOUT outputs=%0d fifo=%0d",
               outputs_checked, fifo_count);
    end
endmodule
