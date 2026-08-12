`timescale 1ns / 1ps

// Experiment-only drop-in adapter.  This preserves the production module
// interface while an isolated project copy measures the rounded-state core.
module cic_interp16_n3_hold2_dsp_ce #(
    parameter integer DATA_W = 21,
    parameter integer OUTPUT_W = 20,
    parameter integer FINAL_PRUNE_LSB = 0,
    parameter integer BURST_COUNTER_USE_DSP = 0,
    parameter integer INTEGRATOR_DSP_MODE = 0
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
    cic_interp16_n3_hold2_rounded_state_ce #(
        .DATA_W(DATA_W),
        .OUTPUT_W(OUTPUT_W),
        .FINAL_PRUNE_LSB(FINAL_PRUNE_LSB)
    ) u_rounded_state (
        .clk(clk), .rst_n(rst_n), .ce_out(ce_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(y_out), .y_out_valid(y_out_valid),
        .burst_remaining_dbg(burst_remaining_dbg),
        .pending_dbg(pending_dbg), .comb_busy_dbg(comb_busy_dbg)
    );

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && BURST_COUNTER_USE_DSP != 0)
            $fatal(1, "Rounded-state adapter requires LUT burst counter");
        if (rst_n && INTEGRATOR_DSP_MODE != 0)
            $fatal(1, "Rounded-state adapter requires integrator mode 0");
    end
`endif
endmodule
