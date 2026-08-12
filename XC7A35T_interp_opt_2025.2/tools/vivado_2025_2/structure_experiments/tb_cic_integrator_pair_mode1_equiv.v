`timescale 1ns / 1ps

module tb_cic_integrator_pair_mode1_equiv;
    localparam integer DATA_W = 21;
    localparam integer OUTPUT_W = 20;
    localparam integer QUEUE_DEPTH = 64;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg ce_out = 1'b0;
    reg signed [DATA_W-1:0] x_in = 21'sd0;
    reg x_in_valid = 1'b0;
    wire signed [OUTPUT_W-1:0] y_ref;
    wire ref_valid;
    wire signed [OUTPUT_W-1:0] y_candidate;
    wire candidate_valid;

    reg signed [OUTPUT_W-1:0] expected_queue [0:QUEUE_DEPTH-1];
    integer queue_write = 0;
    integer queue_read = 0;
    integer queue_count = 0;
    integer input_count;
    integer reference_count = 0;
    integer candidate_count = 0;
    integer enabled_phase;
    integer random_seed;
    integer seed_index;
    integer test_expected_outputs = 0;
    integer test_start_reference = 0;
    integer test_start_candidate = 0;

    always #5 clk = ~clk;

    cic_interp16_n3_hold2_dsp_ce #(
        .DATA_W(DATA_W), .OUTPUT_W(OUTPUT_W),
        .FINAL_PRUNE_LSB(0), .BURST_COUNTER_USE_DSP(0),
        .INTEGRATOR_DSP_MODE(1)
    ) reference_cic (
        .clk(clk), .rst_n(rst_n), .ce_out(ce_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(y_ref), .y_out_valid(ref_valid),
        .burst_remaining_dbg(), .pending_dbg(), .comb_busy_dbg()
    );

    cic_interp16_n3_hold2_integrator_pair_mode1_candidate #(
        .DATA_W(DATA_W), .OUTPUT_W(OUTPUT_W),
        .FINAL_PRUNE_LSB(0), .BURST_COUNTER_USE_DSP(0)
    ) candidate_cic (
        .clk(clk), .rst_n(rst_n), .ce_out(ce_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(y_candidate), .y_out_valid(candidate_valid),
        .burst_remaining_dbg(), .pending_dbg(), .comb_busy_dbg()
    );

    always @(negedge clk) begin
        if (!rst_n) begin
            queue_write = 0;
            queue_read = 0;
            queue_count = 0;
        end
        else begin
            if (ref_valid) begin
                if (queue_count >= QUEUE_DEPTH)
                    $fatal(1, "Compare queue overflow");
                expected_queue[queue_write] = y_ref;
                queue_write = (queue_write+1) % QUEUE_DEPTH;
                queue_count = queue_count+1;
                reference_count = reference_count+1;
            end
            if (candidate_valid) begin
                if (queue_count == 0)
                    $fatal(1, "Candidate output arrived without reference");
                if (y_candidate !== expected_queue[queue_read])
                    $fatal(1, "CIC mismatch output=%0d expected=%0d actual=%0d",
                        candidate_count, expected_queue[queue_read], y_candidate);
                queue_read = (queue_read+1) % QUEUE_DEPTH;
                queue_count = queue_count-1;
                candidate_count = candidate_count+1;
            end
        end
    end

    task choose_sample;
        input integer sample_index;
        begin
            case (sample_index & 15)
                0: x_in = 21'sh0fffff;
                1: x_in = -21'sd1048576;
                2: x_in = 21'sd0;
                3: x_in = 21'sd1;
                4: x_in = -21'sd1;
                5: x_in = 21'sh055555;
                6: x_in = -21'sd349525;
                default: x_in = $random(random_seed);
            endcase
        end
    endtask

    task stream_inputs;
        input integer number_of_inputs;
        input integer insert_ce_stalls;
        begin
            test_start_reference = reference_count;
            test_start_candidate = candidate_count;
            input_count = 0;
            enabled_phase = 15;
            while (input_count < number_of_inputs) begin
                @(negedge clk);
                x_in_valid = 1'b0;
                if (insert_ce_stalls)
                    ce_out = (($random(random_seed) & 32'h7) != 0);
                else
                    ce_out = 1'b1;
                if (ce_out) begin
                    if (enabled_phase == 15) begin
                        choose_sample(input_count);
                        x_in_valid = 1'b1;
                        input_count = input_count+1;
                        enabled_phase = 0;
                    end
                    else begin
                        enabled_phase = enabled_phase+1;
                    end
                end
            end
            test_expected_outputs = number_of_inputs*16;
        end
    endtask

    task drain_and_check;
        integer drain_index;
        begin
            for (drain_index = 0; drain_index < 64;
                 drain_index = drain_index+1) begin
                @(negedge clk);
                x_in_valid = 1'b0;
                ce_out = 1'b1;
            end
            @(negedge clk);
            if (queue_count != 0)
                $fatal(1, "Compare queue did not drain: %0d", queue_count);
            if (reference_count-test_start_reference != test_expected_outputs ||
                candidate_count-test_start_candidate != test_expected_outputs)
                $fatal(1, "Count mismatch ref=%0d candidate=%0d expected=%0d",
                    reference_count-test_start_reference,
                    candidate_count-test_start_candidate,
                    test_expected_outputs);
        end
    endtask

    task pulse_reset;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            x_in_valid = 1'b0;
            ce_out = 1'b0;
            repeat (3) @(negedge clk);
            rst_n = 1'b1;
        end
    endtask

    initial begin
        random_seed = 32'h4A91C35D;
        repeat (12) @(negedge clk);
        rst_n = 1'b1;

        stream_inputs(25, 0);
        @(negedge clk);
        x_in_valid = 1'b0;
        ce_out = 1'b1;
        repeat (7) @(negedge clk);
        rst_n = 1'b0;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        stream_inputs(320, 0);
        drain_and_check();
        pulse_reset();
        stream_inputs(480, 1);
        drain_and_check();

        for (seed_index = 0; seed_index < 20; seed_index = seed_index+1) begin
            pulse_reset();
            random_seed = 32'h13579BDF ^ (seed_index*32'h10204081);
            stream_inputs(256, 1);
            drain_and_check();
        end

        $display("TWO24 INTEGRATOR-PAIR EQUIVALENCE PASS: continuous=320 stalled=480 seeds=20x256 reset-mid-burst=PASS outputs=%0d 0 LSB",
            candidate_count);
        $finish;
    end
endmodule
