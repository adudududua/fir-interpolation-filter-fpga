`timescale 1ns / 1ps

// Test-only name adapter for reusing the existing random-CE FIFO scoreboard.
module cic_interp16_n3_hold2_two24_comb_integrator_ce #(
    parameter integer DATA_W = 21,
    parameter integer OUTPUT_W = 20,
    parameter integer FINAL_PRUNE_LSB = 0
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
    cic_interp16_n3_hold2_two24_simultaneous_ce #(
        .DATA_W(DATA_W), .OUTPUT_W(OUTPUT_W),
        .FINAL_PRUNE_LSB(FINAL_PRUNE_LSB)
    ) u_simultaneous (
        .clk(clk), .rst_n(rst_n), .ce_out(ce_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(y_out), .y_out_valid(y_out_valid),
        .burst_remaining_dbg(burst_remaining_dbg),
        .pending_dbg(pending_dbg), .comb_busy_dbg(comb_busy_dbg)
    );
endmodule
