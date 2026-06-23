`timescale 1ns / 1ps

module interp4_top_synth #(
    parameter DATA_W  = 24,   // 输入数据位宽：24位有符号
    parameter COEFF_W = 18,   // FIR 系数位宽：18位有符号
    parameter ACC_W   = 56,   // FIR 全精度累加器位宽
    parameter NTAPS   = 105   // FIR 抽头数：当前为 MATLAB 导出的真实系数长度
)(
    input  wire                         clk,         // 系统时钟
    input  wire                         rst_n,       // 低有效复位

    input  wire signed [DATA_W-1:0]     x_in,        // 原始输入样本
    input  wire                         x_in_valid,  // 原始输入样本有效

    output wire signed [23:0]           y_out,       // 最终 24 位输出
    output wire                         y_out_valid  // 输出有效
);

    //====================================================
    // 1) 中间连线
    //
    // interp4_ctrl 输出的是"补零后的 FIR 输入"
    // fir_core 输出的是 Q16 格式的大位宽结果
    //====================================================
    wire signed [DATA_W-1:0] fir_in_w;
    wire                     fir_in_valid_w;

    wire signed [ACC_W-1:0]  y_out_full_w;
    wire                     y_out_full_valid_w;

    //====================================================
    // 2) 插值控制模块
    //
    // 功能：
    //   每输入 1 个真实样本，
    //   输出给 FIR 的序列变成：
    //     x0,0,0,0,x1,0,0,0,...
    //====================================================
    interp4_ctrl u_interp4_ctrl (
        .clk          (clk),
        .rst_n        (rst_n),
        .x_in         (x_in),
        .x_in_valid   (x_in_valid),

        .fir_in       (fir_in_w),
        .fir_in_valid (fir_in_valid_w),

        // 下面两个端口在综合专用顶层里不需要向外引出，
        // 但模块本身仍然需要连接
        .phase        (),
        .sample_buf   ()
    );

    //====================================================
    // 3) FIR 核心模块
    //
    // 功能：
    //   对补零后的序列做 105 tap FIR 滤波
    //
    // 注意：
    //   这里输出的是 Q16 格式的大位宽结果，
    //   还没有缩放回 24 位
    //====================================================
    fir_core #(
        .DATA_W   (DATA_W),
        .COEFF_W  (COEFF_W),
        .ACC_W    (ACC_W),
        .NTAPS    (NTAPS)
    ) u_fir_core (
        .clk           (clk),
        .rst_n         (rst_n),
        .fir_in        (fir_in_w),
        .fir_in_valid  (fir_in_valid_w),
        .fir_out_full  (y_out_full_w),
        .fir_out_valid (y_out_full_valid_w)
    );

    //====================================================
    // 4) 缩放 + 舍入 + 饱和模块
    //
    // 把 FIR 的 Q16 大位宽输出转换为 24 位有符号输出
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
    // 5) 输出 valid
    //
    // 因为 round_sat_q16_to24 是组合逻辑，
    // 所以 valid 直接沿用 FIR 输出 valid
    //====================================================
    assign y_out_valid = y_out_full_valid_w;

endmodule