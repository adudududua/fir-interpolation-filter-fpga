`timescale 1ns / 1ps

module tb_fused_quant_fir_front_equiv;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [6:0] ce_counter = 7'd0;
    reg signed [23:0] x_in = 24'sd0;
    reg [31:0] lfsr = 32'h4d3c2b1a;
    reg stage3_compensated_mode = 1'b0;
    integer cycle_count = 0;
    integer compare_y2 = 0;
    integer compare_y4 = 0;
    integer compare_y8 = 0;

    wire ce2_out = ce_counter[5:0] == 6'd0;
    wire ce4_out = ce_counter[4:0] == 5'd0;
    wire ce8_out = ce_counter[3:0] == 4'd0;

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

    fused_quant_fir_front_ooc_wrapper u_dut (
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
            ce_counter <= 7'd0;
            x_in <= 24'sd0;
            lfsr <= 32'h4d3c2b1a;
            stage3_compensated_mode <= 1'b0;
        end
        else begin
            ce_counter <= ce_counter + 7'd1;
            if (ce_counter == 7'd0) begin
                lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
                x_in <= lfsr[23:0];
                if (cycle_count > 12000)
                    stage3_compensated_mode <= 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        #1;
        if (rst_n) begin
            if (ref_y2_valid !== dut_y2_valid)
                $fatal(1, "y2 valid mismatch at cycle %0d", cycle_count);
            if (ref_y4_valid !== dut_y4_valid)
                $fatal(1, "y4 valid mismatch at cycle %0d", cycle_count);
            if (ref_y8_valid !== dut_y8_valid)
                $fatal(1, "y8 valid mismatch at cycle %0d", cycle_count);
            if (ref_y2_valid) begin
                if (ref_y2 !== dut_y2)
                    $fatal(1, "y2 mismatch cycle=%0d ref=%0d dut=%0d", cycle_count, ref_y2, dut_y2);
                compare_y2 = compare_y2 + 1;
            end
            if (ref_y4_valid) begin
                if (ref_y4 !== dut_y4)
                    $fatal(1, "y4 mismatch cycle=%0d ref=%0d dut=%0d", cycle_count, ref_y4, dut_y4);
                compare_y4 = compare_y4 + 1;
            end
            if (ref_y8_valid) begin
                if (ref_y8 !== dut_y8)
                    $fatal(1, "y8 mismatch cycle=%0d ref=%0d dut=%0d", cycle_count, ref_y8, dut_y8);
                compare_y8 = compare_y8 + 1;
            end
            cycle_count = cycle_count + 1;
        end
    end

    initial begin
        repeat (10) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (26000) @(posedge clk);
        if (compare_y2 < 300 || compare_y4 < 600 || compare_y8 < 1200)
            $fatal(1, "insufficient comparisons y2=%0d y4=%0d y8=%0d", compare_y2, compare_y4, compare_y8);
        $display("FUSED QUANT FIR FRONT EQUIVALENCE PASS: y2=%0d y4=%0d y8=%0d", compare_y2, compare_y4, compare_y8);
        $finish;
    end
endmodule
