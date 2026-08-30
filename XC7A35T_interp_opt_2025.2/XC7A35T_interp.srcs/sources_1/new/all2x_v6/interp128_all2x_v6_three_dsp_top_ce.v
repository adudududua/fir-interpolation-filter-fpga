`timescale 1ns / 1ps

//=============================================================
// 文件名       : interp128_all2x_v6_three_dsp_top_ce.v
// 模块名       : interp128_all2x_v6_three_dsp_top_ce
// 功能简述     : Phase 6 三 DSP Pareto 七级 2x 插值实验顶层。
//                Stage 1 保持 strict-halfband BRAM 单 DSP，
//                Stage 2 和 Stage 3 分别独占一个串行 DSP MAC，
//                Stage 4～7 保持 canonical Q4 shift-add。
//
//                本顶层只用于和 Phase 5 的 Stage2/3 共享 DSP
//                结构比较，不直接替换比赛板级顶层。
//
// 当前默认配置：
//                  输入采样率：44.1kHz
//                  输出采样率：5.6448MHz
//                  插值倍数  ：128 倍
//                  DSP 数目标：3
//                  BRAM 目标  ：1 Block RAM Tile
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-13
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-13：新增 Phase 6 三 DSP Pareto 顶层。
//=============================================================
//=============================================================
// 1）模块名称：interp128_all2x_v6_three_dsp_top_ce
// 功能说明：128 倍插值顶层：级联多级 2 倍插值、CIC 与补偿级并管理模式旁路。
// 工程版本：Vivado 2025.2。
//=============================================================

module interp128_all2x_v6_three_dsp_top_ce #(
    parameter integer DATA_W = 24,
    parameter integer STAGE23_ACC_W = 40
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
    wire y2_valid_w;
    wire signed [23:0] y2_to_4_data;
    wire y2_to_4_valid;
    wire signed [23:0] y4_w;
    wire y4_valid_w;
    wire signed [23:0] y4_to_8_data;
    wire y4_to_8_valid;
    wire signed [23:0] y8_w;
    wire y8_valid_w;
    wire signed [23:0] y8_to_16_data;
    wire y8_to_16_valid;
    wire signed [23:0] y16_w;
    wire y16_valid_w;
    wire signed [23:0] y16_to_32_data;
    wire y16_to_32_valid;
    wire signed [23:0] y32_w;
    wire y32_valid_w;
    wire signed [23:0] y32_to_64_data;
    wire y32_to_64_valid;
    wire signed [23:0] y64_w;
    wire y64_valid_w;
    wire signed [23:0] y64_to_128_data;
    wire y64_to_128_valid;
    wire signed [23:0] y128_w;
    wire y128_valid_w;

    // 例化说明：调用 interp2_stage1_strict_halfband_bram_ce 插值子模块，完成对应级的数据展开、滤波或模式选择。
    interp2_stage1_strict_halfband_bram_ce #(
        .DATA_W (DATA_W)
    ) u_interp2_stage1_strict_halfband_bram_ce (
        .clk(clk), .rst_n(rst_n), .ce_out(ce2_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(y2_w), .y_out_valid(y2_valid_w),
        .phase_dbg(), .fir_in_dbg(), .fir_in_valid_dbg()
    );

    // 例化说明：调用 bridge_valid_only_to_interp2_ce 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    bridge_valid_only_to_interp2_ce #(.DATA_W(24)) u_bridge_2_to_4 (
        .clk(clk), .rst_n(rst_n),
        .in_data(y2_w), .in_valid(y2_valid_w),
        .ce_out_next(ce4_out),
        .out_data(y2_to_4_data), .out_valid(y2_to_4_valid)
    );

    // 例化说明：调用 interp2_stage23_independent_dsp_ce 插值子模块，完成对应级的数据展开、滤波或模式选择。
    interp2_stage23_independent_dsp_ce #(
        .STAGE_ID (2), .DATA_W(DATA_W),
        .COEFF_W(16), .ACC_W(STAGE23_ACC_W)
    ) u_interp2_stage2_independent_dsp_ce (
        .clk(clk), .rst_n(rst_n), .ce_out(ce4_out),
        .x_in(y2_to_4_data), .x_in_valid(y2_to_4_valid),
        .y_out(y4_w), .y_out_valid(y4_valid_w),
        .phase_dbg(), .mac_busy_dbg(), .mac_index_dbg()
    );

    // 例化说明：调用 bridge_valid_only_to_interp2_ce 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    bridge_valid_only_to_interp2_ce #(.DATA_W(24)) u_bridge_4_to_8 (
        .clk(clk), .rst_n(rst_n),
        .in_data(y4_w), .in_valid(y4_valid_w),
        .ce_out_next(ce8_out),
        .out_data(y4_to_8_data), .out_valid(y4_to_8_valid)
    );

    // 例化说明：调用 interp2_stage23_independent_dsp_ce 插值子模块，完成对应级的数据展开、滤波或模式选择。
    interp2_stage23_independent_dsp_ce #(
        .STAGE_ID (3), .DATA_W(DATA_W),
        .COEFF_W(16), .ACC_W(STAGE23_ACC_W)
    ) u_interp2_stage3_independent_dsp_ce (
        .clk(clk), .rst_n(rst_n), .ce_out(ce8_out),
        .x_in(y4_to_8_data), .x_in_valid(y4_to_8_valid),
        .y_out(y8_w), .y_out_valid(y8_valid_w),
        .phase_dbg(), .mac_busy_dbg(), .mac_index_dbg()
    );

    // 例化说明：调用 bridge_valid_only_to_interp2_ce 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    bridge_valid_only_to_interp2_ce #(.DATA_W(24)) u_bridge_8_to_16 (
        .clk(clk), .rst_n(rst_n),
        .in_data(y8_w), .in_valid(y8_valid_w),
        .ce_out_next(ce16_out),
        .out_data(y8_to_16_data), .out_valid(y8_to_16_valid)
    );

    // 例化说明：调用 interp2_all2x_v2_stage_select 插值子模块，完成对应级的数据展开、滤波或模式选择。
    interp2_all2x_v2_stage_select #(
        .USE_CANONICAL(1), .STAGE_ID(4), .DATA_W(DATA_W),
        .COEFF_W(16), .ACC_W(41), .NTAPS(7), .FRAC_W(15)
    ) u_interp2_all2x_stage4 (
        .clk(clk), .rst_n(rst_n), .ce_out(ce16_out),
        .x_in(y8_to_16_data), .x_in_valid(y8_to_16_valid),
        .y_out(y16_w), .y_out_valid(y16_valid_w),
        .phase_dbg(), .fir_in_dbg(), .fir_in_valid_dbg()
    );

    // 例化说明：调用 bridge_valid_only_to_interp2_ce 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    bridge_valid_only_to_interp2_ce #(.DATA_W(24)) u_bridge_16_to_32 (
        .clk(clk), .rst_n(rst_n),
        .in_data(y16_w), .in_valid(y16_valid_w),
        .ce_out_next(ce32_out),
        .out_data(y16_to_32_data), .out_valid(y16_to_32_valid)
    );

    // 例化说明：调用 interp2_all2x_v2_stage_select 插值子模块，完成对应级的数据展开、滤波或模式选择。
    interp2_all2x_v2_stage_select #(
        .USE_CANONICAL(1), .STAGE_ID(5), .DATA_W(DATA_W),
        .COEFF_W(14), .ACC_W(39), .NTAPS(7), .FRAC_W(13)
    ) u_interp2_all2x_stage5 (
        .clk(clk), .rst_n(rst_n), .ce_out(ce32_out),
        .x_in(y16_to_32_data), .x_in_valid(y16_to_32_valid),
        .y_out(y32_w), .y_out_valid(y32_valid_w),
        .phase_dbg(), .fir_in_dbg(), .fir_in_valid_dbg()
    );

    // 例化说明：调用 bridge_valid_only_to_interp2_ce 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    bridge_valid_only_to_interp2_ce #(.DATA_W(24)) u_bridge_32_to_64 (
        .clk(clk), .rst_n(rst_n),
        .in_data(y32_w), .in_valid(y32_valid_w),
        .ce_out_next(ce64_out),
        .out_data(y32_to_64_data), .out_valid(y32_to_64_valid)
    );

    // 例化说明：调用 interp2_all2x_v2_stage_select 插值子模块，完成对应级的数据展开、滤波或模式选择。
    interp2_all2x_v2_stage_select #(
        .USE_CANONICAL(1), .STAGE_ID(6), .DATA_W(DATA_W),
        .COEFF_W(13), .ACC_W(38), .NTAPS(7), .FRAC_W(12)
    ) u_interp2_all2x_stage6 (
        .clk(clk), .rst_n(rst_n), .ce_out(ce64_out),
        .x_in(y32_to_64_data), .x_in_valid(y32_to_64_valid),
        .y_out(y64_w), .y_out_valid(y64_valid_w),
        .phase_dbg(), .fir_in_dbg(), .fir_in_valid_dbg()
    );

    // 例化说明：调用 bridge_valid_only_to_interp2_ce 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    bridge_valid_only_to_interp2_ce #(.DATA_W(24)) u_bridge_64_to_128 (
        .clk(clk), .rst_n(rst_n),
        .in_data(y64_w), .in_valid(y64_valid_w),
        .ce_out_next(ce128_out),
        .out_data(y64_to_128_data), .out_valid(y64_to_128_valid)
    );

    // 例化说明：调用 interp2_all2x_v2_stage_select 插值子模块，完成对应级的数据展开、滤波或模式选择。
    interp2_all2x_v2_stage_select #(
        .USE_CANONICAL(1), .STAGE_ID(7), .DATA_W(DATA_W),
        .COEFF_W(14), .ACC_W(38), .NTAPS(7), .FRAC_W(12)
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

