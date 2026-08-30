`timescale 1ns / 1ps

//=============================================================
// 文件名       : interp128_all2x_v3_strict_s1_top_ce.v
// 模块名       : interp128_all2x_v3_strict_s1_top_ce
// 功能简述     : 全 2x V3 Phase 3B 独立实验顶层。
//                Stage 1 使用 105-tap Q15 strict-halfband
//                true-polyphase 单 DSP MAC；Stage 2/3 沿用 V2
//                true-polyphase；Stage 4～7 沿用 canonical Q4。
//
//                本模块仅打开 V2 顶层的实验参数，不修改当前板级
//                默认实例，便于进行 0 LSB 与资源 Pareto 对比。
//
// 当前默认配置：
//                  输入采样率：44.1kHz
//                  输出采样率：5.6448MHz
//                  插值倍数  ：128 倍
//                  Stage 1   ：strict-halfband FF 版
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-11
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-11：新增 V3 strict Stage 1 实验顶层。
//=============================================================

module interp128_all2x_v3_strict_s1_top_ce #(
    parameter integer DATA_W = 24
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         ce2_out,
    input  wire                         ce4_out,
    input  wire                         ce8_out,
    input  wire                         ce16_out,
    input  wire                         ce32_out,
    input  wire                         ce64_out,
    input  wire                         ce128_out,

    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,

    output wire signed [23:0]           y_out,
    output wire                         y_out_valid,

    output wire signed [23:0]           dbg_y2,
    output wire                         dbg_y2_valid,
    output wire signed [23:0]           dbg_y4,
    output wire                         dbg_y4_valid,
    output wire signed [23:0]           dbg_y8,
    output wire                         dbg_y8_valid,
    output wire signed [23:0]           dbg_y16,
    output wire                         dbg_y16_valid,
    output wire signed [23:0]           dbg_y32,
    output wire                         dbg_y32_valid,
    output wire signed [23:0]           dbg_y64,
    output wire                         dbg_y64_valid
);

    interp128_all2x_v3_stage1_select_top_ce #(
        .DATA_W                      (DATA_W),
        .FIRST_CANONICAL_STAGE       (4),
        .FIRST_TRUE_POLYPHASE_STAGE  (2),
        .USE_STRICT_STAGE1           (1)
    ) u_interp128_all2x_v3_stage1_select_top_ce (
        .clk            (clk),
        .rst_n          (rst_n),
        .ce2_out        (ce2_out),
        .ce4_out        (ce4_out),
        .ce8_out        (ce8_out),
        .ce16_out       (ce16_out),
        .ce32_out       (ce32_out),
        .ce64_out       (ce64_out),
        .ce128_out      (ce128_out),
        .x_in           (x_in),
        .x_in_valid     (x_in_valid),
        .y_out          (y_out),
        .y_out_valid    (y_out_valid),
        .dbg_y2         (dbg_y2),
        .dbg_y2_valid   (dbg_y2_valid),
        .dbg_y4         (dbg_y4),
        .dbg_y4_valid   (dbg_y4_valid),
        .dbg_y8         (dbg_y8),
        .dbg_y8_valid   (dbg_y8_valid),
        .dbg_y16        (dbg_y16),
        .dbg_y16_valid  (dbg_y16_valid),
        .dbg_y32        (dbg_y32),
        .dbg_y32_valid  (dbg_y32_valid),
        .dbg_y64        (dbg_y64),
        .dbg_y64_valid  (dbg_y64_valid)
    );

endmodule
