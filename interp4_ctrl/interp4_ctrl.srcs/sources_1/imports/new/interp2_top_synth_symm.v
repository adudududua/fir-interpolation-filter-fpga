`timescale 1ns / 1ps

module interp2_top_synth_symm #(
    parameter DATA_W  = 24,
    parameter COEFF_W = 18,
    parameter ACC_W   = 56,
    parameter NTAPS   = 11
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,

    output wire signed [23:0]           y_out,
    output wire                         y_out_valid
);

    //====================================================
    // 中间连线
    //====================================================
    wire signed [DATA_W-1:0] fir_in_w;
    wire                     fir_in_valid_w;

    wire signed [ACC_W-1:0]  y_out_full_w;
    wire                     y_out_full_valid_w;

    //====================================================
    // 1) 2倍补零控制
    //====================================================
    interp2_ctrl u_interp2_ctrl (
        .clk          (clk),
        .rst_n        (rst_n),
        .x_in         (x_in),
        .x_in_valid   (x_in_valid),

        .fir_in       (fir_in_w),
        .fir_in_valid (fir_in_valid_w),

        .phase        (),
        .sample_buf   ()
    );

    //====================================================
    // 2) 对称优化版 2x FIR
    //====================================================
    fir_core_symm_interp2_v2 #(
        .DATA_W   (DATA_W),
        .COEFF_W  (COEFF_W),
        .ACC_W    (ACC_W),
        .NTAPS    (NTAPS)
    ) u_fir_core_symm_interp2 (
        .clk           (clk),
        .rst_n         (rst_n),
        .fir_in        (fir_in_w),
        .fir_in_valid  (fir_in_valid_w),
        .fir_out_full  (y_out_full_w),
        .fir_out_valid (y_out_full_valid_w)
    );

    //====================================================
    // 3) Q16 -> 24位输出
    //====================================================
    round_sat_q16_to24 #(
        .IN_W    (ACC_W),
        .OUT_W   (24),
        .FRAC_W  (16)
    ) u_round_sat_q16_to24 (
        .din_full (y_out_full_w),
        .dout_24  (y_out)
    );

    assign y_out_valid = y_out_full_valid_w;

endmodule