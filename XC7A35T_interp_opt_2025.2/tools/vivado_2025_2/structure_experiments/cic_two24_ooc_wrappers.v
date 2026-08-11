`timescale 1ns / 1ps

module baseline_cic_ooc_wrapper (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               ce_out,
    input  wire signed [20:0] x_in,
    input  wire               x_in_valid,
    output wire signed [19:0] y_out,
    output wire               y_out_valid,
    output wire [4:0]         burst_remaining_dbg,
    output wire               pending_dbg,
    output wire               comb_busy_dbg
);
    cic_interp16_n3_hold2_dsp_ce #(
        .DATA_W(21),
        .OUTPUT_W(20),
        .FINAL_PRUNE_LSB(0),
        .BURST_COUNTER_USE_DSP(0),
        .INTEGRATOR_DSP_MODE(2)
    ) u_dut (
        .clk(clk), .rst_n(rst_n), .ce_out(ce_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(y_out), .y_out_valid(y_out_valid),
        .burst_remaining_dbg(burst_remaining_dbg),
        .pending_dbg(pending_dbg), .comb_busy_dbg(comb_busy_dbg)
    );
endmodule

module candidate_cic_two24_ooc_wrapper (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               ce_out,
    input  wire signed [20:0] x_in,
    input  wire               x_in_valid,
    output wire signed [19:0] y_out,
    output wire               y_out_valid,
    output wire [4:0]         burst_remaining_dbg,
    output wire               pending_dbg,
    output wire               comb_busy_dbg
);
    cic_interp16_n3_hold2_two24_comb_integrator_ce #(
        .DATA_W(21),
        .OUTPUT_W(20),
        .FINAL_PRUNE_LSB(0)
    ) u_dut (
        .clk(clk), .rst_n(rst_n), .ce_out(ce_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(y_out), .y_out_valid(y_out_valid),
        .burst_remaining_dbg(burst_remaining_dbg),
        .pending_dbg(pending_dbg), .comb_busy_dbg(comb_busy_dbg)
    );
endmodule

module candidate_cic_sequential_pair_ooc_wrapper (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               ce_out,
    input  wire signed [20:0] x_in,
    input  wire               x_in_valid,
    output wire signed [19:0] y_out,
    output wire               y_out_valid,
    output wire [4:0]         burst_remaining_dbg,
    output wire               pending_dbg,
    output wire               comb_busy_dbg
);
    cic_interp16_n3_hold2_two24_sequential_pair_ce #(
        .DATA_W(21),
        .OUTPUT_W(20),
        .FINAL_PRUNE_LSB(0)
    ) u_dut (
        .clk(clk), .rst_n(rst_n), .ce_out(ce_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(y_out), .y_out_valid(y_out_valid),
        .burst_remaining_dbg(burst_remaining_dbg),
        .pending_dbg(pending_dbg), .comb_busy_dbg(comb_busy_dbg)
    );
endmodule

module candidate_cic_simultaneous_ooc_wrapper (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               ce_out,
    input  wire signed [20:0] x_in,
    input  wire               x_in_valid,
    output wire signed [19:0] y_out,
    output wire               y_out_valid,
    output wire [4:0]         burst_remaining_dbg,
    output wire               pending_dbg,
    output wire               comb_busy_dbg
);
    cic_interp16_n3_hold2_two24_simultaneous_ce #(
        .DATA_W(21),
        .OUTPUT_W(20),
        .FINAL_PRUNE_LSB(0)
    ) u_dut (
        .clk(clk), .rst_n(rst_n), .ce_out(ce_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(y_out), .y_out_valid(y_out_valid),
        .burst_remaining_dbg(burst_remaining_dbg),
        .pending_dbg(pending_dbg), .comb_busy_dbg(comb_busy_dbg)
    );
endmodule
