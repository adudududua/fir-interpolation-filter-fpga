`timescale 1ns / 1ps

//=============================================================
// 文件名       : interp2_top_symm_ce.v
// 模块名       : interp2_top_symm_ce
// 功能简述     : 2 倍插值顶层：连接控制器、FIR 核心和输出握手接口。
// 设计说明     : 本文件采用同步时序设计；复位、时钟使能、
//                有效信号和定点位宽关系均在对应代码段说明。
//                注释仅用于阐明实现，不参与综合结果。
// 设计作者     : kafeizizi
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     : 2026-08-30：统一中文文件头、模块编号与结构说明。
//=============================================================
//=============================================================
// 1）模块名称：interp2_top_symm_ce
// 功能说明：2 倍插值顶层：连接控制器、FIR 核心和输出握手接口。
// 工程版本：Vivado 2025.2。
//=============================================================

module interp2_top_symm_ce #(
    // parameter DATA_W  = 24,
    // parameter COEFF_W = 18,
    // parameter ACC_W   = 56,
    // parameter NTAPS   = 11

    //字长优化后：
    parameter DATA_W  = 24,
    parameter COEFF_W = 14,
    parameter ACC_W   = 45,
    parameter NTAPS   = 29,
    parameter FRAC_W  = 12
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         ce_out,      // 2x 级输出采样使能

    input  wire signed [DATA_W-1:0]     x_in,        // 输入样本
    input  wire                         x_in_valid,  // 输入样本有效

    output wire signed [23:0]           y_out,       // 最终 24 位输出
    output wire                         y_out_valid, // 输出有效

    // 调试输出
    output wire                         phase_dbg,
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
    // 1) 2x 插值控制模块
    //====================================================
    // 例化说明：调用 interp2_ctrl_ce 插值子模块，完成对应级的数据展开、滤波或模式选择。
    interp2_ctrl_ce u_interp2_ctrl_ce (
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
    // 2) 2x 对称优化 FIR
    //====================================================
    // 例化说明：调用 fir_core_symm_interp2_v2 FIR 子模块，完成本级对称抽头乘加和定点输出。
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
    // 3) Q16 -> 24 位输出
    //====================================================
    // 例化说明：调用 round_sat_q16_to24 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    round_sat_q16_to24 #(
        .IN_W   (ACC_W),
        .OUT_W  (24),
        .FRAC_W (FRAC_W)
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
