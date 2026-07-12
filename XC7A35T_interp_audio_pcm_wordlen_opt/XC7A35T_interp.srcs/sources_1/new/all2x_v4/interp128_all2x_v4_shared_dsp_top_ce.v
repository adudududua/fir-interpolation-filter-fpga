`timescale 1ns / 1ps

//=============================================================
// 文件名       : interp128_all2x_v4_shared_dsp_top_ce.v
// 模块名       : interp128_all2x_v4_shared_dsp_top_ce
// 功能简述     : 全 2x V4 Stage 2/3 共享 DSP 独立实验顶层。
//                Stage 1 保持 V3 strict-halfband BRAM 单 DSP，
//                Stage 2/3 共用第 2 个 DSP，Stage 4～7 保持
//                canonical Q4 shift-add，级间使用 valid-only 桥。
//
// 当前默认配置：
//                  输入采样率：44.1kHz
//                  输出采样率：5.6448MHz
//                  插值倍数  ：128 倍
//                  DSP 数目标：2
//                  BRAM 目标  ：1 Block RAM Tile
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-12
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-12：新增 V4 Stage 2/3 共享 DSP 顶层。
//=============================================================

module interp128_all2x_v4_shared_dsp_top_ce #(
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

    wire signed [23:0] y2_w;
    wire               y2_valid_w;
    wire signed [23:0] y2_to_4_data;
    wire               y2_to_4_valid;

    wire signed [23:0] y4_w;
    wire               y4_valid_w;
    wire signed [23:0] y4_to_8_data;
    wire               y4_to_8_valid;

    wire signed [23:0] y8_w;
    wire               y8_valid_w;
    wire signed [23:0] y8_to_16_data;
    wire               y8_to_16_valid;

    wire signed [23:0] y16_w;
    wire               y16_valid_w;
    wire signed [23:0] y16_to_32_data;
    wire               y16_to_32_valid;

    wire signed [23:0] y32_w;
    wire               y32_valid_w;
    wire signed [23:0] y32_to_64_data;
    wire               y32_to_64_valid;

    wire signed [23:0] y64_w;
    wire               y64_valid_w;
    wire signed [23:0] y64_to_128_data;
    wire               y64_to_128_valid;

    wire signed [23:0] y128_w;
    wire               y128_valid_w;

    interp2_stage1_strict_halfband_bram_ce #(
        .DATA_W (DATA_W)
    ) u_interp2_stage1_strict_halfband_bram_ce (
        .clk              (clk),
        .rst_n            (rst_n),
        .ce_out           (ce2_out),
        .x_in             (x_in),
        .x_in_valid       (x_in_valid),
        .y_out            (y2_w),
        .y_out_valid      (y2_valid_w),
        .phase_dbg        (),
        .fir_in_dbg       (),
        .fir_in_valid_dbg ()
    );

    bridge_valid_only_to_interp2_ce #(
        .DATA_W (24)
    ) u_bridge_2_to_4 (
        .clk         (clk),
        .rst_n       (rst_n),
        .in_data     (y2_w),
        .in_valid    (y2_valid_w),
        .ce_out_next (ce4_out),
        .out_data    (y2_to_4_data),
        .out_valid   (y2_to_4_valid)
    );

    bridge_valid_only_to_interp2_ce #(
        .DATA_W (24)
    ) u_bridge_4_to_8 (
        .clk         (clk),
        .rst_n       (rst_n),
        .in_data     (y4_w),
        .in_valid    (y4_valid_w),
        .ce_out_next (ce8_out),
        .out_data    (y4_to_8_data),
        .out_valid   (y4_to_8_valid)
    );

    interp2_stage23_shared_dsp_ce #(
        .DATA_W  (DATA_W),
        .COEFF_W (16),
        .ACC_W   (42)
    ) u_interp2_stage23_shared_dsp_ce (
        .clk                     (clk),
        .rst_n                   (rst_n),
        .stage2_ce_out           (ce4_out),
        .stage2_x_in             (y2_to_4_data),
        .stage2_x_in_valid       (y2_to_4_valid),
        .stage2_y_out            (y4_w),
        .stage2_y_out_valid      (y4_valid_w),
        .stage3_ce_out           (ce8_out),
        .stage3_x_in             (y4_to_8_data),
        .stage3_x_in_valid       (y4_to_8_valid),
        .stage3_y_out            (y8_w),
        .stage3_y_out_valid      (y8_valid_w),
        .stage2_phase_dbg        (),
        .stage3_phase_dbg        (),
        .scheduler_busy_dbg      (),
        .scheduler_stage_dbg     (),
        .scheduler_mac_index_dbg ()
    );

    bridge_valid_only_to_interp2_ce #(
        .DATA_W (24)
    ) u_bridge_8_to_16 (
        .clk         (clk),
        .rst_n       (rst_n),
        .in_data     (y8_w),
        .in_valid    (y8_valid_w),
        .ce_out_next (ce16_out),
        .out_data    (y8_to_16_data),
        .out_valid   (y8_to_16_valid)
    );

    interp2_all2x_v2_stage_select #(
        .USE_CANONICAL (1),
        .STAGE_ID      (4),
        .DATA_W        (DATA_W),
        .COEFF_W       (16),
        .ACC_W         (41),
        .NTAPS         (7),
        .FRAC_W        (15)
    ) u_interp2_all2x_stage4 (
        .clk(clk), .rst_n(rst_n), .ce_out(ce16_out),
        .x_in(y8_to_16_data), .x_in_valid(y8_to_16_valid),
        .y_out(y16_w), .y_out_valid(y16_valid_w),
        .phase_dbg(), .fir_in_dbg(), .fir_in_valid_dbg()
    );

    bridge_valid_only_to_interp2_ce #(
        .DATA_W (24)
    ) u_bridge_16_to_32 (
        .clk(clk), .rst_n(rst_n),
        .in_data(y16_w), .in_valid(y16_valid_w),
        .ce_out_next(ce32_out),
        .out_data(y16_to_32_data), .out_valid(y16_to_32_valid)
    );

    interp2_all2x_v2_stage_select #(
        .USE_CANONICAL (1),
        .STAGE_ID      (5),
        .DATA_W        (DATA_W),
        .COEFF_W       (14),
        .ACC_W         (39),
        .NTAPS         (7),
        .FRAC_W        (13)
    ) u_interp2_all2x_stage5 (
        .clk(clk), .rst_n(rst_n), .ce_out(ce32_out),
        .x_in(y16_to_32_data), .x_in_valid(y16_to_32_valid),
        .y_out(y32_w), .y_out_valid(y32_valid_w),
        .phase_dbg(), .fir_in_dbg(), .fir_in_valid_dbg()
    );

    bridge_valid_only_to_interp2_ce #(
        .DATA_W (24)
    ) u_bridge_32_to_64 (
        .clk(clk), .rst_n(rst_n),
        .in_data(y32_w), .in_valid(y32_valid_w),
        .ce_out_next(ce64_out),
        .out_data(y32_to_64_data), .out_valid(y32_to_64_valid)
    );

    interp2_all2x_v2_stage_select #(
        .USE_CANONICAL (1),
        .STAGE_ID      (6),
        .DATA_W        (DATA_W),
        .COEFF_W       (13),
        .ACC_W         (38),
        .NTAPS         (7),
        .FRAC_W        (12)
    ) u_interp2_all2x_stage6 (
        .clk(clk), .rst_n(rst_n), .ce_out(ce64_out),
        .x_in(y32_to_64_data), .x_in_valid(y32_to_64_valid),
        .y_out(y64_w), .y_out_valid(y64_valid_w),
        .phase_dbg(), .fir_in_dbg(), .fir_in_valid_dbg()
    );

    bridge_valid_only_to_interp2_ce #(
        .DATA_W (24)
    ) u_bridge_64_to_128 (
        .clk(clk), .rst_n(rst_n),
        .in_data(y64_w), .in_valid(y64_valid_w),
        .ce_out_next(ce128_out),
        .out_data(y64_to_128_data), .out_valid(y64_to_128_valid)
    );

    interp2_all2x_v2_stage_select #(
        .USE_CANONICAL (1),
        .STAGE_ID      (7),
        .DATA_W        (DATA_W),
        .COEFF_W       (14),
        .ACC_W         (38),
        .NTAPS         (7),
        .FRAC_W        (12)
    ) u_interp2_all2x_stage7 (
        .clk(clk), .rst_n(rst_n), .ce_out(ce128_out),
        .x_in(y64_to_128_data), .x_in_valid(y64_to_128_valid),
        .y_out(y128_w), .y_out_valid(y128_valid_w),
        .phase_dbg(), .fir_in_dbg(), .fir_in_valid_dbg()
    );

    assign y_out = y128_w;
    assign y_out_valid = y128_valid_w;
    assign dbg_y2 = y2_w;
    assign dbg_y2_valid = y2_valid_w;
    assign dbg_y4 = y4_w;
    assign dbg_y4_valid = y4_valid_w;
    assign dbg_y8 = y8_w;
    assign dbg_y8_valid = y8_valid_w;
    assign dbg_y16 = y16_w;
    assign dbg_y16_valid = y16_valid_w;
    assign dbg_y32 = y32_w;
    assign dbg_y32_valid = y32_valid_w;
    assign dbg_y64 = y64_w;
    assign dbg_y64_valid = y64_valid_w;

endmodule
