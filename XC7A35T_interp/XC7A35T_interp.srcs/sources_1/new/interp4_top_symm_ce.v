`default_nettype none
`timescale 1ns / 1ps

module interp4_top_symm_ce #(
    parameter DATA_W  = 24,   // 输入数据位宽
    parameter COEFF_W = 18,   // FIR 系数位宽
    parameter ACC_W   = 56,   // 累加器位宽
    parameter NTAPS   = 155   // FIR tap 数
)(
    input  wire                         clk,         // 系统时钟
    input  wire                         rst_n,       // 低有效复位

    input  wire                         ce_out,      // 输出采样使能（例如 200kHz）

    input  wire signed [DATA_W-1:0]     x_in,        // 原始输入样本
    input  wire                         x_in_valid,  // 原始输入样本有效

    output wire signed [23:0]           y_out,       // 最终 24 位输出
    output wire                         y_out_valid, // 输出有效

    // 调试输出，方便上板时接 ILA
    output wire [1:0]                   phase_dbg,
    output wire signed [23:0]           fir_in_dbg,
    output wire                         fir_in_valid_dbg
);

    //====================================================
    // 中间连线
    //====================================================
    wire signed [DATA_W-1:0] fir_in_w;
    wire                     fir_in_valid_w;

    wire signed [ACC_W-1:0]  y_out_full_w;
    wire                     y_out_full_valid_w;

    wire signed [DATA_W-1:0] sample_buf_w;

    //====================================================
    // 1) 带 ce 的插值控制模块
    //====================================================
    interp4_ctrl_ce u_interp4_ctrl_ce (
        .clk          (clk),
        .rst_n        (rst_n),
        .ce_out       (ce_out),

        .x_in         (x_in),
        .x_in_valid   (x_in_valid),

        .fir_in       (fir_in_w),
        .fir_in_valid (fir_in_valid_w),

        .phase        (phase_dbg),
        .sample_buf   (sample_buf_w)
    );

    //====================================================
    // 2) 对称优化版 FIR
    //
    // 注意：
    // fir_core_symm 本身不需要 ce_out 输入，
    // 因为它是否推进延时线取决于 fir_in_valid_w。
    // 只有 ce_out=1 时，fir_in_valid_w 才会拉高。
    //====================================================
    fir_core_symm #(
        .DATA_W   (DATA_W),
        .COEFF_W  (COEFF_W),
        .ACC_W    (ACC_W),
        .NTAPS    (NTAPS)
    ) u_fir_core_symm (
        .clk           (clk),
        .rst_n         (rst_n),
        .fir_in        (fir_in_w),
        .fir_in_valid  (fir_in_valid_w),
        .fir_out_full  (y_out_full_w),
        .fir_out_valid (y_out_full_valid_w)
    );

    //====================================================
    // 3) Q16 大位宽输出 -> 24 位输出
    //====================================================
    round_sat_q16_to24 #(
        .IN_W    (ACC_W),
        .OUT_W   (24),
        .FRAC_W  (16)
    ) u_round_sat_q16_to24 (
        .din_full (y_out_full_w),
        .dout_24  (y_out)
    );

    //====================================================
    // 4) 输出 valid
    //====================================================
    assign y_out_valid = y_out_full_valid_w;

    //====================================================
    // 5) 调试引出
    //====================================================
    assign fir_in_dbg       = fir_in_w;
    assign fir_in_valid_dbg = fir_in_valid_w;

endmodule
`default_nettype wire