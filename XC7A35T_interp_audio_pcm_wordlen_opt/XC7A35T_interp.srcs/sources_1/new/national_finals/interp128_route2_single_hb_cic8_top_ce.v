`timescale 1ns / 1ps

`include "all2x_v3_stage1_coeff_pkg.vh"

// Route 2C: FIR2 x3 -> canonical HB2 -> CIC8/N3.
module interp128_route2_single_hb_cic8_top_ce (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ce2_out,
    input  wire                         ce4_out,
    input  wire                         ce8_out,
    input  wire                         ce16_out,
    input  wire                         ce32_out,
    input  wire                         ce64_out,
    input  wire                         ce128_out,
    input  wire signed [23:0]           x_in,
    input  wire                         x_in_valid,
    output wire signed [23:0]           y_out,
    output wire                         y_out_valid,
    output wire signed [23:0]           dbg_y2,
    output wire                         dbg_y2_valid,
    output wire signed [23:0]           dbg_y4,
    output wire                         dbg_y4_valid,
    output wire signed [23:0]           dbg_y8,
    output wire                         dbg_y8_valid,
    output wire signed [23:0]           dbg_y16,
    output wire                         dbg_y16_valid,
    output wire signed [23:0]           dbg_y32,
    output wire                         dbg_y32_valid,
    output wire signed [23:0]           dbg_y64,
    output wire                         dbg_y64_valid
);

    wire signed [23:0] y2_w;
    wire y2_valid_w;
    wire signed [21:0] y2_to_4_data;
    wire y2_to_4_valid;
    wire signed [21:0] y4_w;
    wire y4_valid_w;
    wire signed [19:0] y4_to_8_data;
    wire y4_to_8_valid;
    wire signed [19:0] y8_w;
    wire y8_valid_w;
    wire signed [19:0] y16_w;
    wire y16_valid_w;
    wire signed [19:0] y128_w;
    wire y128_valid_w;

    interp2_stage1_strict_halfband_bram_ce #(
        .DATA_W(24),
        .COEFF_W(`R2_S1_COEFF_W),
        .ACC_W(`R2_S1_ACC_W),
        .FRAC_W(`R2_S1_FRAC_W),
        .HISTORY_LEN(`R2_S1_HISTORY_LEN),
        .PAIR_COUNT(`R2_S1_PAIR_COUNT),
        .DELAY_INDEX(`R2_S1_DELAY_INDEX),
        .USE_DSP48_PREADDER(0),
        .USE_ROUTE2_COEFF(1)
    ) u_route2c_stage1 (
        .clk(clk), .rst_n(rst_n), .ce_out(ce2_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(y2_w), .y_out_valid(y2_valid_w),
        .phase_dbg(), .fir_in_dbg(), .fir_in_valid_dbg()
    );

    bridge_valid_quantized_to_interp2_ce #(
        .IN_W(24), .OUT_W(22), .SHIFT_N(2)
    ) u_bridge_2_to_4 (
        .clk(clk), .rst_n(rst_n),
        .in_data(y2_w), .in_valid(y2_valid_w),
        .ce_out_next(ce4_out),
        .out_data(y2_to_4_data), .out_valid(y2_to_4_valid)
    );

    bridge_valid_quantized_to_interp2_ce #(
        .IN_W(22), .OUT_W(20), .SHIFT_N(2)
    ) u_bridge_4_to_8 (
        .clk(clk), .rst_n(rst_n),
        .in_data(y4_w), .in_valid(y4_valid_w),
        .ce_out_next(ce8_out),
        .out_data(y4_to_8_data), .out_valid(y4_to_8_valid)
    );

    interp2_stage23_lutram_cic_dsp_ce #(
        .DATA_W(24),
        .STAGE2_DATA_W(22),
        .STAGE3_DATA_W(20),
        .COEFF_W(16),
        .ACC_W(38),
        .CIC_ORDER(3),
        .STAGE3_FLAT(1),
        .USE_ROUTE2_STAGE3(2),
        .USE_BRAM_HISTORY(1),
        .USE_BRAM_COEFF(1),
        .USE_PACKED_BRAM(0)
    ) u_route2c_stage23 (
        .clk(clk), .rst_n(rst_n),
        .stage2_ce_out(ce4_out),
        .stage2_x_in(y2_to_4_data),
        .stage2_x_in_valid(y2_to_4_valid),
        .stage2_y_out(y4_w),
        .stage2_y_out_valid(y4_valid_w),
        .stage3_ce_out(ce8_out),
        .stage3_x_in(y4_to_8_data),
        .stage3_x_in_valid(y4_to_8_valid),
        .stage3_y_out(y8_w),
        .stage3_y_out_valid(y8_valid_w),
        .stage2_phase_dbg(), .stage3_phase_dbg(),
        .scheduler_busy_dbg(), .scheduler_stage_dbg(),
        .scheduler_mac_index_dbg()
    );

    interp2_halfband7_shiftadd_ce #(
        .DATA_W(20),
        .ASSUME_VALID_PHASE0(1),
        .PROVEN_NO_SATURATION(0)
    ) u_route2c_hb (
        .clk(clk), .rst_n(rst_n), .ce_out(ce16_out),
        .x_in(y8_w), .x_in_valid(y8_valid_w),
        .y_out(y16_w), .y_out_valid(y16_valid_w),
        .phase_dbg()
    );

    cic_interp8_n3_serial_comb_dsp_ce #(
        .DATA_W(20), .OUTPUT_W(20)
    ) u_route2c_cic8 (
        .clk(clk), .rst_n(rst_n), .ce_out(ce128_out),
        .x_in(y16_w), .x_in_valid(y16_valid_w),
        .y_out(y128_w), .y_out_valid(y128_valid_w),
        .burst_remaining_dbg(), .pending_dbg(), .comb_busy_dbg()
    );

    assign y_out = {y128_w, 4'b0};
    assign y_out_valid = y128_valid_w;
    assign dbg_y2 = y2_w;
    assign dbg_y2_valid = y2_valid_w;
    assign dbg_y4 = {y4_w, 2'b0};
    assign dbg_y4_valid = y4_valid_w;
    assign dbg_y8 = {y8_w, 4'b0};
    assign dbg_y8_valid = y8_valid_w;
    assign dbg_y16 = {y16_w, 4'b0};
    assign dbg_y16_valid = y16_valid_w;
    assign dbg_y32 = 24'sd0;
    assign dbg_y32_valid = 1'b0;
    assign dbg_y64 = 24'sd0;
    assign dbg_y64_valid = 1'b0;

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && (ce32_out === 1'bx ||
                      ce64_out === 1'bx))
            $fatal(1, "Route2C unused CE contains X");
    end
`endif

endmodule
