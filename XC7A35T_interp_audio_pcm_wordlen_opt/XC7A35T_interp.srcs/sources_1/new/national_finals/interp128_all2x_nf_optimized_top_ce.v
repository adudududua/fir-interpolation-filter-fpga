`timescale 1ns / 1ps

// National-finals all-2x candidate:
//   - Stage 1: strict halfband, BRAM history, one DSP
//   - Stages 2/3: one shared DSP with BRAM history/coefficients
//   - Stages 4..7: exact [-1 0 9 16 9 0 -1]/16 halfbands
//                  with one shared even-phase shift/add datapath
// The 4x and 8x nodes are bit-identical to the FIR-CIC front end.  The final
// 16x interpolation is FIR-only and therefore needs no CIC compensation.
module interp128_all2x_nf_optimized_top_ce #(
    parameter integer STAGE23_ACC_W = 38,
    parameter integer USE_SHARED_TAIL = 1,
    parameter integer USE_SHARED_TAIL_DSP48 = 0,
    parameter integer USE_BRAM_STAGE23_HISTORY = 1,
    parameter integer USE_BRAM_STAGE23_COEFF = 1,
    parameter integer USE_PACKED_BRAM_STAGE23 = 0
)(
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
    wire signed [17:0] y8_to_tail_data;
    wire y8_to_tail_valid;
    wire signed [17:0] y16_w;
    wire y16_valid_w;
    wire signed [17:0] y32_w;
    wire y32_valid_w;
    wire signed [17:0] y64_w;
    wire y64_valid_w;
    wire signed [17:0] y128_w;
    wire y128_valid_w;

    interp2_stage1_strict_halfband_bram_ce #(
        .DATA_W(24),
        .USE_DSP48_PREADDER(0)
    ) u_interp2_stage1_strict_halfband_bram_ce (
        .clk(clk), .rst_n(rst_n), .ce_out(ce2_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(y2_w), .y_out_valid(y2_valid_w),
        .phase_dbg(), .fir_in_dbg(), .fir_in_valid_dbg()
    );

    bridge_valid_quantized_to_interp2_ce #(
        .IN_W(24), .OUT_W(22), .SHIFT_N(2)
    ) u_bridge_2_to_4_quantized (
        .clk(clk), .rst_n(rst_n),
        .in_data(y2_w), .in_valid(y2_valid_w),
        .ce_out_next(ce4_out),
        .out_data(y2_to_4_data), .out_valid(y2_to_4_valid)
    );

    bridge_valid_quantized_to_interp2_ce #(
        .IN_W(22), .OUT_W(20), .SHIFT_N(2)
    ) u_bridge_4_to_8_quantized (
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
        .ACC_W(STAGE23_ACC_W),
        .CIC_ORDER(3),
        .STAGE3_FLAT(2),
        .USE_BRAM_HISTORY(USE_BRAM_STAGE23_HISTORY),
        .USE_BRAM_COEFF(USE_BRAM_STAGE23_COEFF),
        .USE_PACKED_BRAM(USE_PACKED_BRAM_STAGE23)
    ) u_interp2_stage23_lutram_cic_dsp_ce (
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

    bridge_valid_quantized_buffered_ce #(
        .IN_W(20), .OUT_W(18), .SHIFT_N(2)
    ) u_bridge_8_to_tail (
        .clk(clk), .rst_n(rst_n),
        .in_data(y8_w), .in_valid(y8_valid_w),
        .ce_out_next(ce16_out),
        .out_data(y8_to_tail_data), .out_valid(y8_to_tail_valid)
    );

    generate
        if (USE_SHARED_TAIL != 0) begin : gen_shared_tail
            interp2_halfband7_shared4_ce #(
                .DATA_W(18),
                .USE_DSP48_PREADDER(USE_SHARED_TAIL_DSP48)
            ) u_interp2_halfband7_shared4_ce (
                .clk(clk), .rst_n(rst_n),
                .ce16_out(ce16_out), .ce32_out(ce32_out),
                .ce64_out(ce64_out), .ce128_out(ce128_out),
                .x8_quantized(y8_to_tail_valid ?
                              y8_to_tail_data : 18'sd0),
                .y16(y16_w), .y16_valid(y16_valid_w),
                .y32(y32_w), .y32_valid(y32_valid_w),
                .y64(y64_w), .y64_valid(y64_valid_w),
                .y128(y128_w), .y128_valid(y128_valid_w)
            );
        end
        else begin : gen_independent_tail
            wire signed [17:0] y8_to_16_data;
            wire y8_to_16_valid;
            wire signed [17:0] y16_to_32_data;
            wire y16_to_32_valid;
            wire signed [17:0] y32_to_64_data;
            wire y32_to_64_valid;
            wire signed [17:0] y64_to_128_data;
            wire y64_to_128_valid;

            assign y8_to_16_data = y8_to_tail_data;
            assign y8_to_16_valid = y8_to_tail_valid;
            interp2_all2x_v2_stage_select #(
                .USE_CANONICAL(1), .DATA_W(18)
            ) u_stage4 (
                .clk(clk), .rst_n(rst_n), .ce_out(ce16_out),
                .x_in(y8_to_16_data), .x_in_valid(y8_to_16_valid),
                .y_out(y16_w), .y_out_valid(y16_valid_w),
                .phase_dbg(), .fir_in_dbg(), .fir_in_valid_dbg()
            );
            bridge_valid_only_to_interp2_ce #(.DATA_W(18)) u_bridge_16_to_32 (
                .clk(clk), .rst_n(rst_n),
                .in_data(y16_w), .in_valid(y16_valid_w),
                .ce_out_next(ce32_out),
                .out_data(y16_to_32_data), .out_valid(y16_to_32_valid)
            );
            interp2_all2x_v2_stage_select #(
                .USE_CANONICAL(1), .DATA_W(18)
            ) u_stage5 (
                .clk(clk), .rst_n(rst_n), .ce_out(ce32_out),
                .x_in(y16_to_32_data), .x_in_valid(y16_to_32_valid),
                .y_out(y32_w), .y_out_valid(y32_valid_w),
                .phase_dbg(), .fir_in_dbg(), .fir_in_valid_dbg()
            );
            bridge_valid_only_to_interp2_ce #(.DATA_W(18)) u_bridge_32_to_64 (
                .clk(clk), .rst_n(rst_n),
                .in_data(y32_w), .in_valid(y32_valid_w),
                .ce_out_next(ce64_out),
                .out_data(y32_to_64_data), .out_valid(y32_to_64_valid)
            );
            interp2_all2x_v2_stage_select #(
                .USE_CANONICAL(1), .DATA_W(18)
            ) u_stage6 (
                .clk(clk), .rst_n(rst_n), .ce_out(ce64_out),
                .x_in(y32_to_64_data), .x_in_valid(y32_to_64_valid),
                .y_out(y64_w), .y_out_valid(y64_valid_w),
                .phase_dbg(), .fir_in_dbg(), .fir_in_valid_dbg()
            );
            bridge_valid_only_to_interp2_ce #(.DATA_W(18)) u_bridge_64_to_128 (
                .clk(clk), .rst_n(rst_n),
                .in_data(y64_w), .in_valid(y64_valid_w),
                .ce_out_next(ce128_out),
                .out_data(y64_to_128_data), .out_valid(y64_to_128_valid)
            );
            interp2_all2x_v2_stage_select #(
                .USE_CANONICAL(1), .DATA_W(18)
            ) u_stage7 (
                .clk(clk), .rst_n(rst_n), .ce_out(ce128_out),
                .x_in(y64_to_128_data), .x_in_valid(y64_to_128_valid),
                .y_out(y128_w), .y_out_valid(y128_valid_w),
                .phase_dbg(), .fir_in_dbg(), .fir_in_valid_dbg()
            );
        end
    endgenerate

    assign y_out = {y128_w, 6'b0};
    assign y_out_valid = y128_valid_w;
    assign dbg_y2 = y2_w;
    assign dbg_y2_valid = y2_valid_w;
    assign dbg_y4 = {y4_w, 2'b0};
    assign dbg_y4_valid = y4_valid_w;
    assign dbg_y8 = {y8_w, 4'b0};
    assign dbg_y8_valid = y8_valid_w;
    assign dbg_y16 = {y16_w, 6'b0};
    assign dbg_y16_valid = y16_valid_w;
    assign dbg_y32 = {y32_w, 6'b0};
    assign dbg_y32_valid = y32_valid_w;
    assign dbg_y64 = {y64_w, 6'b0};
    assign dbg_y64_valid = y64_valid_w;

endmodule
