`timescale 1ns / 1ps

module interp8_top_synth #(
    parameter DATA_W   = 24,
    parameter COEFF_W  = 18,
    parameter ACC_W    = 56,
    parameter NTAPS4X  = 155,
    parameter NTAPS2X  = 11
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,

    output wire signed [23:0]           y_out,
    output wire                         y_out_valid
);

    //====================================================
    // 4x级输出 -> 2x级输入
    //====================================================
    wire signed [23:0] y4_w;
    wire               y4_valid_w;

    //====================================================
    // 1) 前级：4x 插值器（最终版）
    //====================================================
    interp4_top_synth_symm #(
        .DATA_W  (DATA_W),
        .COEFF_W (COEFF_W),
        .ACC_W   (ACC_W),
        .NTAPS   (NTAPS4X)
    ) u_interp4_top_synth_symm (
        .clk         (clk),
        .rst_n       (rst_n),
        .x_in        (x_in),
        .x_in_valid  (x_in_valid),
        .y_out       (y4_w),
        .y_out_valid (y4_valid_w)
    );

    //====================================================
    // 2) 后级：2x 插值器
    //====================================================
    interp2_top_synth_symm #(
        .DATA_W  (DATA_W),
        .COEFF_W (COEFF_W),
        .ACC_W   (ACC_W),
        .NTAPS   (NTAPS2X)
    ) u_interp2_top_synth_symm (
        .clk         (clk),
        .rst_n       (rst_n),
        .x_in        (y4_w),
        .x_in_valid  (y4_valid_w),
        .y_out       (y_out),
        .y_out_valid (y_out_valid)
    );

endmodule