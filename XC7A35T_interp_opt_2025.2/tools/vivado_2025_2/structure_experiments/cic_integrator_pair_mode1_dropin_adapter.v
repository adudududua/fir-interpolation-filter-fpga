`timescale 1ns / 1ps

// Drop-in name adapter used only by the isolated full-board experiment.
module cic_interp16_n3_hold2_dsp_ce #(
    parameter integer DATA_W = 21,
    parameter integer OUTPUT_W = 20,
    parameter integer FINAL_PRUNE_LSB = 0,
    parameter integer BURST_COUNTER_USE_DSP = 0,
    parameter integer INTEGRATOR_DSP_MODE = 1
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ce_out,
    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,
    output wire signed [OUTPUT_W-1:0]   y_out,
    output wire                         y_out_valid,
    output wire [4:0]                   burst_remaining_dbg,
    output wire                         pending_dbg,
    output wire                         comb_busy_dbg
);
    localparam integer FINAL_W = DATA_W+8-FINAL_PRUNE_LSB;
    wire signed [FINAL_W-1:0] candidate_final_integrator_state;

    cic_interp16_n3_hold2_integrator_pair_mode1_candidate #(
        .DATA_W(DATA_W),
        .OUTPUT_W(OUTPUT_W),
        .FINAL_PRUNE_LSB(FINAL_PRUNE_LSB),
        .BURST_COUNTER_USE_DSP(BURST_COUNTER_USE_DSP)
    ) u_candidate (
        .clk(clk),
        .rst_n(rst_n),
        .ce_out(ce_out),
        .x_in(x_in),
        .x_in_valid(x_in_valid),
        .y_out(y_out),
        .y_out_valid(y_out_valid),
        .burst_remaining_dbg(burst_remaining_dbg),
        .pending_dbg(pending_dbg),
        .comb_busy_dbg(comb_busy_dbg)
    );

    assign candidate_final_integrator_state =
        u_candidate.final_integrator_state;
    // Preserve the debug hierarchy name used by reset-recovery tests.
    wire signed [FINAL_W-1:0] final_integrator_state =
        candidate_final_integrator_state;

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && INTEGRATOR_DSP_MODE != 1)
            $fatal(1, "This experiment adapter requires mode 1");
    end
`endif
endmodule
