`timescale 1ns / 1ps

//=============================================================
// 文件名       : cic_interp16_top.v
// 模块名       : cic_interp16_top
// 功能简述     : Phase 7 的 16 倍 FIR-CIC 尾链顶层。模块先在
//                352.8kHz 低速端执行 15tap Q12 补偿 FIR，再按
//                标准顺序执行低速 comb、16 倍插零和高速
//                integrator，输出 5.6448MHz 的 20bit 数据流。
//
// 当前默认配置：
//                  候选 A：CIC_ORDER=3，FINAL_PRUNE_LSB=3
//                  候选 B：CIC_ORDER=4，FINAL_PRUNE_LSB=6
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-13
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-13：新增 Phase 7 FIR-CIC 尾链顶层。
//=============================================================

module cic_interp16_top #(
    parameter integer DATA_W = 20,
    parameter integer CIC_ORDER = 3,
    parameter integer FINAL_PRUNE_LSB = 3
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ce_out,
    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,
    output wire signed [DATA_W-1:0]     y_out,
    output wire                         y_out_valid,
    output wire                         compensation_busy_dbg,
    output wire [4:0]                   burst_remaining_dbg
);

    wire signed [DATA_W-1:0] compensated_data;
    wire compensated_valid;

    cic_compensation_fir_ce #(
        .DATA_W   (DATA_W),
        .COEFF_W  (14),
        .ACC_W    (40),
        .FRAC_W   (12),
        .CIC_ORDER(CIC_ORDER)
    ) u_cic_compensation_fir_ce (
        .clk        (clk),
        .rst_n      (rst_n),
        .x_in       (x_in),
        .x_in_valid (x_in_valid),
        .y_out      (compensated_data),
        .y_out_valid(compensated_valid),
        .busy_dbg   (compensation_busy_dbg)
    );

    cic_interp16_core_ce #(
        .DATA_W          (DATA_W),
        .CIC_ORDER       (CIC_ORDER),
        .FINAL_PRUNE_LSB (FINAL_PRUNE_LSB)
    ) u_cic_interp16_core_ce (
        .clk                (clk),
        .rst_n              (rst_n),
        .ce_out             (ce_out),
        .x_in               (compensated_data),
        .x_in_valid         (compensated_valid),
        .y_out              (y_out),
        .y_out_valid        (y_out_valid),
        .burst_remaining_dbg(burst_remaining_dbg),
        .pending_dbg        ()
    );

endmodule
