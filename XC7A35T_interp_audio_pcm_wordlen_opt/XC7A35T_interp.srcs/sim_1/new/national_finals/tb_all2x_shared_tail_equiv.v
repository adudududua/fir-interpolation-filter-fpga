`timescale 1ns / 1ps

module tb_all2x_shared_tail_equiv;

    reg clk;
    reg rst_n;
    reg [6:0] ce_cnt;
    reg signed [23:0] x_in;
    reg [23:0] lfsr;
    integer cycle_count;
    integer compared_count;

    wire ce2_out = (ce_cnt[5:0] == 6'b000000);
    wire ce4_out = (ce_cnt[4:0] == 5'b00000);
    wire ce8_out = (ce_cnt[3:0] == 4'b0000);
    wire ce16_out = (ce_cnt[2:0] == 3'b000);
    wire ce32_out = (ce_cnt[1:0] == 2'b00);
    wire ce64_out = (ce_cnt[0] == 1'b0);
    wire ce128_out = 1'b1;
    wire input_update = (ce_cnt == 7'd127);

    wire signed [23:0] y_shared;
    wire y_shared_valid;
    wire signed [23:0] y_ref;
    wire y_ref_valid;
    wire signed [23:0] y16_shared;
    wire signed [23:0] y32_shared;
    wire signed [23:0] y64_shared;
    wire signed [23:0] y16_ref;
    wire signed [23:0] y32_ref;
    wire signed [23:0] y64_ref;
    wire y16_shared_valid;
    wire y32_shared_valid;
    wire y64_shared_valid;
    wire y16_ref_valid;
    wire y32_ref_valid;
    wire y64_ref_valid;

    interp128_all2x_nf_optimized_top_ce #(
        .USE_SHARED_TAIL(1),
        .USE_SHARED_TAIL_DSP48(1)
    ) u_shared (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(x_in), .x_in_valid(1'b1),
        .y_out(y_shared), .y_out_valid(y_shared_valid),
        .dbg_y2(), .dbg_y2_valid(), .dbg_y4(), .dbg_y4_valid(),
        .dbg_y8(), .dbg_y8_valid(),
        .dbg_y16(y16_shared), .dbg_y16_valid(y16_shared_valid),
        .dbg_y32(y32_shared), .dbg_y32_valid(y32_shared_valid),
        .dbg_y64(y64_shared), .dbg_y64_valid(y64_shared_valid)
    );

    interp128_all2x_nf_optimized_top_ce #(
        .USE_SHARED_TAIL(0)
    ) u_independent (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(x_in), .x_in_valid(1'b1),
        .y_out(y_ref), .y_out_valid(y_ref_valid),
        .dbg_y2(), .dbg_y2_valid(), .dbg_y4(), .dbg_y4_valid(),
        .dbg_y8(), .dbg_y8_valid(),
        .dbg_y16(y16_ref), .dbg_y16_valid(y16_ref_valid),
        .dbg_y32(y32_ref), .dbg_y32_valid(y32_ref_valid),
        .dbg_y64(y64_ref), .dbg_y64_valid(y64_ref_valid)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ce_cnt <= 7'd0;
            x_in <= 24'sd0;
            lfsr <= 24'h5a17c3;
        end
        else begin
            ce_cnt <= ce_cnt + 7'd1;
            if (input_update) begin
                lfsr <= {lfsr[22:0],
                    lfsr[23] ^ lfsr[22] ^ lfsr[21] ^ lfsr[16]};
                case (cycle_count[3:0])
                    4'd0: x_in <= 24'sh7fffff;
                    4'd1: x_in <= -24'sh800000;
                    4'd2: x_in <= 24'sd1;
                    4'd3: x_in <= -24'sd1;
                    default: x_in <= $signed(lfsr);
                endcase
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count <= cycle_count + 1;
            if (cycle_count > 1024) begin
                if (y_shared_valid !== y_ref_valid)
                    $fatal(1, "y128 valid mismatch cycle=%0d", cycle_count);
                if (y_shared_valid && y_shared !== y_ref)
                    $fatal(1,
                        "y128 mismatch cycle=%0d shared=%0d ref=%0d",
                        cycle_count, y_shared, y_ref);
                if (y16_shared_valid !== y16_ref_valid ||
                    (y16_shared_valid && y16_shared !== y16_ref))
                    $fatal(1, "y16 mismatch cycle=%0d", cycle_count);
                if (y32_shared_valid !== y32_ref_valid ||
                    (y32_shared_valid && y32_shared !== y32_ref))
                    $fatal(1, "y32 mismatch cycle=%0d", cycle_count);
                if (y64_shared_valid !== y64_ref_valid ||
                    (y64_shared_valid && y64_shared !== y64_ref))
                    $fatal(1, "y64 mismatch cycle=%0d", cycle_count);
                compared_count <= compared_count + 1;
            end
        end
    end

    initial begin
        rst_n = 1'b0;
        cycle_count = 0;
        compared_count = 0;
        repeat (20) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (18000) @(posedge clk);

        @(negedge clk);
        rst_n = 1'b0;
        repeat (7) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        cycle_count = 0;
        repeat (18000) @(posedge clk);

        $display(
            "ALL2X SHARED TAIL EQUIVALENCE PASS compared=%0d reset=PASS",
            compared_count);
        $finish;
    end

endmodule
