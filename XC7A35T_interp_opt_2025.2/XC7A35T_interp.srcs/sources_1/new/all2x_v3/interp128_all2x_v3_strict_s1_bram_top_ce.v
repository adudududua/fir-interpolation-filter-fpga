`timescale 1ns / 1ps

//=============================================================
// 文件名       : interp128_all2x_v3_strict_s1_bram_top_ce.v
// 模块名       : interp128_all2x_v3_strict_s1_bram_top_ce
// 功能简述     : 全 2x V3 Phase 3C BRAM 实验顶层。
//                Stage 1 使用 64x24bit BRAM 循环缓冲的严格半带
//                true-polyphase 单 DSP MAC，其余级保持 V2 结构。
//
//                本模块已作为板级工程的 V3 资源优化链路入口。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-11
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-11：新增 V3 strict Stage 1 BRAM 顶层。
//                2026-07-12：接入板级 DAC 演示工程进行综合实现验证。
//=============================================================
//=============================================================
// 1）模块名称：interp128_all2x_v3_strict_s1_bram_top_ce
// 功能说明：128 倍插值顶层：级联多级 2 倍插值、CIC 与补偿级并管理模式旁路。
// 工程版本：Vivado 2025.2。
//=============================================================

module interp128_all2x_v3_strict_s1_bram_top_ce #(
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

    // 例化说明：调用 interp128_all2x_v3_stage1_select_top_ce 插值链顶层，完成所选倍率的数据率提升与有效信号传递。
    interp128_all2x_v3_stage1_select_top_ce #(
        .DATA_W                      (DATA_W),
        .FIRST_CANONICAL_STAGE       (4),
        .FIRST_TRUE_POLYPHASE_STAGE  (2),
        .USE_STRICT_STAGE1           (2)
    ) u_interp128_all2x_v3_stage1_select_top_ce (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .ce16_out(ce16_out), .ce32_out(ce32_out),
        .ce64_out(ce64_out), .ce128_out(ce128_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(y_out), .y_out_valid(y_out_valid),
        .dbg_y2(dbg_y2), .dbg_y2_valid(dbg_y2_valid),
        .dbg_y4(dbg_y4), .dbg_y4_valid(dbg_y4_valid),
        .dbg_y8(dbg_y8), .dbg_y8_valid(dbg_y8_valid),
        .dbg_y16(dbg_y16), .dbg_y16_valid(dbg_y16_valid),
        .dbg_y32(dbg_y32), .dbg_y32_valid(dbg_y32_valid),
        .dbg_y64(dbg_y64), .dbg_y64_valid(dbg_y64_valid)
    );

endmodule
