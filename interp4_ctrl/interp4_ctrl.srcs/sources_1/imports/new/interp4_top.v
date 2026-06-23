`timescale 1ns / 1ps

module interp4_top #(
    parameter DATA_W  = 24,   // 输入数据位宽
    parameter COEFF_W = 18,   // FIR 系数位宽
    parameter ACC_W   = 56,   // FIR 累加器输出位宽
    parameter NTAPS   = 105   // FIR tap 数，使用 MATLAB 导出的真实系数长度
)(
    input  wire                         clk,            // 系统时钟
    input  wire                         rst_n,          // 低有效复位

    input  wire signed [DATA_W-1:0]     x_in,           // 原始输入样本
    input  wire                         x_in_valid,     // 原始输入样本有效

    //====================================================
    // 新增：真正的 24 位输出
    //====================================================
    output wire signed [23:0]           y_out,          // 24 位有符号输出
    output wire                         y_out_valid,    // 输出有效

    //====================================================
    // 保留：全精度输出，方便你调试观察
    //====================================================
    output wire signed [ACC_W-1:0]      y_out_full,     // FIR 大位宽输出（Q16）
    output wire                         y_out_full_valid,

    //===========================
    // 调试信号
    //===========================
    output wire signed [DATA_W-1:0]     fir_in_dbg,
    output wire                         fir_in_valid_dbg,
    output wire [1:0]                   phase_dbg
);

    //====================================================
    // 中间连线：interp4_ctrl 输出给 fir_core 的数据
    //====================================================
    wire signed [DATA_W-1:0] fir_in_w;
    wire                     fir_in_valid_w;
    wire [1:0]               phase_w;
    wire signed [DATA_W-1:0] sample_buf_w;

    //====================================================
    // 1) 插值控制模块
    //====================================================
    interp4_ctrl u_interp4_ctrl (
        .clk         (clk),
        .rst_n       (rst_n),
        .x_in        (x_in),
        .x_in_valid  (x_in_valid),

        .fir_in      (fir_in_w),
        .fir_in_valid(fir_in_valid_w),

        .phase       (phase_w),
        .sample_buf  (sample_buf_w)
    );

    //====================================================
    // 2) FIR 核心模块
    //====================================================
    fir_core #(
        .DATA_W  (DATA_W),
        .COEFF_W (COEFF_W),
        .ACC_W   (ACC_W),
        .NTAPS   (NTAPS)
    ) u_fir_core (
        .clk          (clk),
        .rst_n        (rst_n),
        .fir_in       (fir_in_w),
        .fir_in_valid (fir_in_valid_w),
        .fir_out_full (y_out_full),
        .fir_out_valid(y_out_full_valid)
    );

    //====================================================
    // 3) 缩放 + 饱和模块
    //
    // 把 FIR 的 Q16 大位宽输出转换成 24 位有符号输出
    //====================================================
    round_sat_q16_to24 #(
        .IN_W   (ACC_W),
        .OUT_W  (24),
        .FRAC_W (16)
    ) u_round_sat_q16_to24 (
        .din_full (y_out_full),
        .dout_24  (y_out)
    );

    //====================================================
    // 4) 输出 valid
    //
    // 因为 round_sat_q16_to24 是纯组合逻辑，
    // 所以 valid 不需要再额外延迟，直接沿用 FIR 输出 valid
    //====================================================
    assign y_out_valid = y_out_full_valid;

    //====================================================
    // 5) 调试信号引出
    //====================================================
    assign fir_in_dbg       = fir_in_w;
    assign fir_in_valid_dbg = fir_in_valid_w;
    assign phase_dbg        = phase_w;

endmodule