`timescale 1ns / 1ps

// Complete X3 candidate: one 20 MHz DSP for FIR Stage1/2/3 plus the signed-
// off two-DSP CIC integrator allocation in the audio domain.
module nf_x3_20m_filter_core (
    input  wire                         sys_clk,
    input  wire                         sys_rst_n,
    input  wire                         audio_clk,
    input  wire                         audio_rst_n,
    input  wire                         ce2_out,
    input  wire                         ce4_out,
    input  wire                         ce8_out,
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
    output wire                         input_overflow_dbg,
    output wire                         output_overrun_dbg
);
    wire signed [23:0] y2_w;
    wire y2_valid_w;
    wire signed [21:0] y4_w;
    wire y4_valid_w;
    wire signed [19:0] y8_w;
    wire y8_valid_w;
    wire signed [20:0] compensated_w;
    wire compensated_valid_w;
    wire signed [19:0] y128_w;
    wire y128_valid_w;

    nf_x3_20m_fir_front u_fir_front (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .audio_clk(audio_clk), .audio_rst_n(audio_rst_n),
        .audio_ce2(ce2_out), .audio_ce4(ce4_out),
        .audio_ce8(ce8_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y2_out(y2_w), .y2_out_valid(y2_valid_w),
        .y4_out(y4_w), .y4_out_valid(y4_valid_w),
        .y8_out(y8_w), .y8_out_valid(y8_valid_w),
        .input_overflow_dbg(input_overflow_dbg),
        .output_overrun_dbg(output_overrun_dbg),
        .sys_frame_cycle_dbg(), .sys_frame_active_dbg()
    );

    cic3_compensator_shiftadd_ce #(
        .DATA_W(20), .OUTPUT_W(21), .REGISTER_OUTPUT(0)
    ) u_compensator (
        .clk(audio_clk), .rst_n(audio_rst_n),
        .x_in(y8_w), .x_in_valid(y8_valid_w),
        .y_out(compensated_w), .y_out_valid(compensated_valid_w)
    );

    cic_interp16_n3_hold2_dsp_ce #(
        .DATA_W(21),
        .OUTPUT_W(20),
        .FINAL_PRUNE_LSB(0),
        .BURST_COUNTER_USE_DSP(0),
        .INTEGRATOR_DSP_MODE(2)
    ) u_cic (
        .clk(audio_clk), .rst_n(audio_rst_n),
        .ce_out(ce128_out),
        .x_in(compensated_w), .x_in_valid(compensated_valid_w),
        .y_out(y128_w), .y_out_valid(y128_valid_w),
        .burst_remaining_dbg(), .pending_dbg(), .comb_busy_dbg()
    );

    assign y_out = {y128_w, 4'b0000};
    assign y_out_valid = y128_valid_w;
    assign dbg_y2 = y2_w;
    assign dbg_y2_valid = y2_valid_w;
    assign dbg_y4 = {y4_w, 2'b00};
    assign dbg_y4_valid = y4_valid_w;
    assign dbg_y8 = {y8_w, 4'b0000};
    assign dbg_y8_valid = y8_valid_w;
endmodule
