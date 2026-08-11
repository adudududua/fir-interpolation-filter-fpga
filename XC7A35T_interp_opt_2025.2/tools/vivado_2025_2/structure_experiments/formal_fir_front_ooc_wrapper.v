`timescale 1ns / 1ps

// Isolated measurement wrapper.  Only the three FIR nodes are observable, so
// synthesis removes the downstream CIC and reports the signed-off FIR front
// end on the same RTL/configuration used by the board project.
module formal_fir_front_ooc_wrapper #(
    parameter integer STAGE2_DATA_W = 22
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    ce2_out,
    input  wire                    ce4_out,
    input  wire                    ce8_out,
    input  wire signed [23:0]      x_in,
    input  wire                    x_in_valid,
    input  wire                    stage3_compensated_mode,
    output wire signed [23:0]      y2,
    output wire                    y2_valid,
    output wire signed [23:0]      y4,
    output wire                    y4_valid,
    output wire signed [23:0]      y8,
    output wire                    y8_valid
);

    interp128_all2x_v7_folded_fir_cic_top_ce #(
        .STAGE1_ACC_W(41),
        .STAGE23_ACC_W(38),
        .STAGE2_DATA_W(STAGE2_DATA_W),
        .CIC_ORDER(3),
        .FINAL_PRUNE_LSB(0),
        .USE_LUTRAM_STAGE23(1),
        .STAGE3_FLAT(1),
        .USE_CIC3_SHIFTADD_COMPENSATOR(0),
        .USE_BRAM_STAGE23_HISTORY(1),
        .USE_UNIFIED_BRAM_STAGE23_HISTORY(1),
        .USE_SINGLE_BRAM_STAGE1(1),
        .USE_BRAM_STAGE23_COEFF(1),
        .USE_PACKED_BRAM_STAGE23(0),
        .CIC_BURST_COUNTER_USE_DSP(0),
        .CIC_COMB_USE_DSP(0),
        .USE_SERIAL_CIC_COMB(1),
        .USE_N3_HOLD_EQUIV(1),
        .USE_STAGE1_DSP48_PREADDER(1),
        .USE_NATIONAL_FINALS_NARROW_STAGE23(1),
        .USE_P3_JOINT_STAGE3(1),
        .ASSUME_ALIGNED_POW2_CE(1),
        .CIC_INTEGRATOR_DSP_MODE(2),
        .USE_UNIFIED_FIR_COEFF_BRAM(1)
    ) u_formal_core (
        .clk(clk),
        .rst_n(rst_n),
        .ce2_out(ce2_out),
        .ce4_out(ce4_out),
        .ce8_out(ce8_out),
        .ce16_out(1'b0),
        .ce32_out(1'b0),
        .ce64_out(1'b0),
        .ce128_out(1'b0),
        .x_in(x_in),
        .x_in_valid(x_in_valid),
        .stage3_compensated_mode(stage3_compensated_mode),
        .y_out(),
        .y_out_valid(),
        .dbg_y2(y2),
        .dbg_y2_valid(y2_valid),
        .dbg_y4(y4),
        .dbg_y4_valid(y4_valid),
        .dbg_y8(y8),
        .dbg_y8_valid(y8_valid),
        .dbg_y16(),
        .dbg_y16_valid(),
        .dbg_y32(),
        .dbg_y32_valid(),
        .dbg_y64(),
        .dbg_y64_valid()
    );

endmodule
