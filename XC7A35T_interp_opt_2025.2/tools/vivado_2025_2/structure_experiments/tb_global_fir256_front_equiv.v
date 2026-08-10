`timescale 1ns / 1ps

module tb_global_fir256_front_equiv;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [7:0] ce_counter = 8'd0;
    reg signed [23:0] x_in = 24'sd0;
    reg [31:0] lfsr = 32'h6a09e667;
    reg stage3_compensated_mode = 1'b0;
    integer cycle_count = 0;
    integer i;
    integer ref_y2_count = 0, dut_y2_count = 0;
    integer ref_y4_count = 0, dut_y4_count = 0;
    integer ref_y8_count = 0, dut_y8_count = 0;
    reg signed [23:0] ref_y2_stream [0:1023];
    reg signed [23:0] dut_y2_stream [0:1023];
    reg signed [23:0] ref_y4_stream [0:2047];
    reg signed [23:0] dut_y4_stream [0:2047];
    reg signed [23:0] ref_y8_stream [0:4095];
    reg signed [23:0] dut_y8_stream [0:4095];

    wire ce2_out = ce_counter[6:0] == 7'd0;
    wire ce4_out = ce_counter[5:0] == 6'd0;
    wire ce8_out = ce_counter[4:0] == 5'd0;
    wire signed [23:0] ref_y2, ref_y4, ref_y8;
    wire ref_y2_valid, ref_y4_valid, ref_y8_valid;
    wire signed [23:0] dut_y2, dut_y4, dut_y8;
    wire dut_y2_valid, dut_y4_valid, dut_y8_valid;

    always #5 clk = ~clk;

    baseline_fir_front_direct_wrapper u_ref (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .x_in(x_in), .x_in_valid(1'b1),
        .stage3_compensated_mode(stage3_compensated_mode),
        .y2(ref_y2), .y2_valid(ref_y2_valid),
        .y4(ref_y4), .y4_valid(ref_y4_valid),
        .y8(ref_y8), .y8_valid(ref_y8_valid)
    );

    global_fir256_front_ooc_wrapper u_dut (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .x_in(x_in), .x_in_valid(1'b1),
        .stage3_compensated_mode(stage3_compensated_mode),
        .y2(dut_y2), .y2_valid(dut_y2_valid),
        .y4(dut_y4), .y4_valid(dut_y4_valid),
        .y8(dut_y8), .y8_valid(dut_y8_valid)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            ce_counter <= 8'd0;
            x_in <= 24'sd0;
            lfsr <= 32'h6a09e667;
            stage3_compensated_mode <= 1'b0;
        end
        else begin
            ce_counter <= ce_counter + 8'd1;
            if (ce_counter == 8'd0) begin
                lfsr <= {lfsr[30:0],
                         lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
                x_in <= lfsr[23:0];
                if (cycle_count > 30000)
                    stage3_compensated_mode <= 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        #1;
        if (rst_n) begin
            if (ref_y2_valid) begin
                ref_y2_stream[ref_y2_count] = ref_y2;
                ref_y2_count = ref_y2_count + 1;
            end
            if (dut_y2_valid) begin
                dut_y2_stream[dut_y2_count] = dut_y2;
                dut_y2_count = dut_y2_count + 1;
            end
            if (ref_y4_valid) begin
                ref_y4_stream[ref_y4_count] = ref_y4;
                ref_y4_count = ref_y4_count + 1;
            end
            if (dut_y4_valid) begin
                dut_y4_stream[dut_y4_count] = dut_y4;
                dut_y4_count = dut_y4_count + 1;
            end
            if (ref_y8_valid) begin
                ref_y8_stream[ref_y8_count] = ref_y8;
                ref_y8_count = ref_y8_count + 1;
            end
            if (dut_y8_valid) begin
                dut_y8_stream[dut_y8_count] = dut_y8;
                dut_y8_count = dut_y8_count + 1;
            end
            cycle_count = cycle_count + 1;
        end
    end

    initial begin
        repeat (10) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (64000) @(posedge clk);
        if (ref_y2_count != dut_y2_count ||
            ref_y4_count != dut_y4_count ||
            ref_y8_count != dut_y8_count)
            $fatal(1, "stream count mismatch ref=%0d/%0d/%0d dut=%0d/%0d/%0d",
                   ref_y2_count, ref_y4_count, ref_y8_count,
                   dut_y2_count, dut_y4_count, dut_y8_count);
        for (i = 0; i < ref_y2_count; i = i + 1)
            if (ref_y2_stream[i] !== dut_y2_stream[i])
                $fatal(1, "y2 stream mismatch index=%0d ref=%0d dut=%0d",
                       i, ref_y2_stream[i], dut_y2_stream[i]);
        for (i = 0; i < ref_y4_count; i = i + 1)
            if (ref_y4_stream[i] !== dut_y4_stream[i])
                $fatal(1, "y4 stream mismatch index=%0d ref=%0d dut=%0d",
                       i, ref_y4_stream[i], dut_y4_stream[i]);
        for (i = 0; i < ref_y8_count; i = i + 1)
            if (ref_y8_stream[i] !== dut_y8_stream[i])
                $fatal(1, "y8 stream mismatch index=%0d ref=%0d dut=%0d",
                       i, ref_y8_stream[i], dut_y8_stream[i]);
        if (ref_y2_count < 400 || ref_y4_count < 900 || ref_y8_count < 1800)
            $fatal(1, "insufficient stream coverage");
        $display("GLOBAL FIR256 STREAM EQUIVALENCE PASS: y2=%0d y4=%0d y8=%0d",
                 ref_y2_count, ref_y4_count, ref_y8_count);
        $finish;
    end
endmodule
