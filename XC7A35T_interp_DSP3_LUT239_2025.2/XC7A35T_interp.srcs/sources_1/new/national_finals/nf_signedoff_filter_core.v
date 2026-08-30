`timescale 1ns / 1ps

//=============================================================
// 文件名       : nf_signedoff_filter_core.v
// 模块名       : nf_signedoff_filter_core
// 功能简述     : 全国赛正式参数的验证专用双核包装模块。
//                一个实例采用平坦 Stage3 系数，提供正式 4x/8x
//                调试节点；另一个实例采用 CIC 补偿 Stage3 系数，
//                提供正式 128x 输出和后续节点。
//
//                本模块只用于 RTL 黄金向量回归，不进入板级综合。
//                板级工程使用单个按模式选择系数组的正式滤波器核，
//                因此这里的双实例不会计入 239-LUT/3-DSP 资源结果。
//
// 当前默认配置：
//                  STAGE2_DATA_W=20
//                  4x/8x 使用平坦系数组
//                  128x 使用补偿系数组
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-29
// 版本         : V2025.2
// 开发工具     : Vivado Simulator 2025.2
// 修订记录     :
//                2026-07-29：建立正式多节点验证包装模块。
//                2026-08-16：明确双实例只用于仿真、不计板级资源。
//=============================================================

module nf_signedoff_filter_core #(
    parameter integer STAGE2_DATA_W = 20
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               ce2_out,
    input  wire               ce4_out,
    input  wire               ce8_out,
    input  wire               ce16_out,
    input  wire               ce32_out,
    input  wire               ce64_out,
    input  wire               ce128_out,
    input  wire signed [23:0] x_in,
    input  wire               x_in_valid,
    output wire signed [23:0] y_out,
    output wire               y_out_valid,
    output wire signed [23:0] dbg_y2,
    output wire               dbg_y2_valid,
    output wire signed [23:0] dbg_y4,
    output wire               dbg_y4_valid,
    output wire signed [23:0] dbg_y8,
    output wire               dbg_y8_valid,
    output wire signed [23:0] dbg_y16,
    output wire               dbg_y16_valid,
    output wire signed [23:0] dbg_y32,
    output wire               dbg_y32_valid,
    output wire signed [23:0] dbg_y64,
    output wire               dbg_y64_valid
);

    wire signed [23:0] unused_comp_y2;
    wire unused_comp_y2_valid;
    wire signed [23:0] unused_comp_y4;
    wire unused_comp_y4_valid;
    wire signed [23:0] unused_comp_y8;
    wire unused_comp_y8_valid;

    // 补偿分支：正式128x输出路径，Stage3使用P3 CIC幅频补偿系数；
    // 其4x/8x调试端口不作为本包装器的公开低倍率签核节点。
    interp128_all2x_v7_folded_fir_cic_top_ce #(
        .STAGE1_ACC_W(41),
        .STAGE23_ACC_W(38),
        .STAGE2_DATA_W(STAGE2_DATA_W),
        .CIC_ORDER(3),
        .FINAL_PRUNE_LSB(0),
        .USE_LUTRAM_STAGE23(1),
        .STAGE3_FLAT(1),
        .USE_CIC3_SHIFTADD_COMPENSATOR(0),
        .USE_BRAM_STAGE23_HISTORY(1),
        .USE_UNIFIED_BRAM_STAGE23_HISTORY(1),
        .USE_SINGLE_BRAM_STAGE1(1),
        .USE_BRAM_STAGE23_COEFF(1),
        .USE_PACKED_BRAM_STAGE23(0),
        .CIC_BURST_COUNTER_USE_DSP(0),
        .CIC_COMB_USE_DSP(0),
        .USE_SERIAL_CIC_COMB(1),
        .USE_N3_HOLD_EQUIV(1),
        .USE_STAGE1_DSP48_PREADDER(1),
        .USE_NATIONAL_FINALS_NARROW_STAGE23(1),
        .USE_P3_JOINT_STAGE3(1),
        .ASSUME_ALIGNED_POW2_CE(1),
        .CIC_INTEGRATOR_DSP_MODE(2),
        .USE_UNIFIED_FIR_COEFF_BRAM(1)
    ) u_p3_compensated_core (
        .clk(clk),
        .rst_n(rst_n),
        .ce2_out(ce2_out),
        .ce4_out(ce4_out),
        .ce8_out(ce8_out),
        .ce16_out(ce16_out),
        .ce32_out(ce32_out),
        .ce64_out(ce64_out),
        .ce128_out(ce128_out),
        .x_in(x_in),
        .x_in_valid(x_in_valid),
        .stage3_compensated_mode(1'b1),
        .y_out(y_out),
        .y_out_valid(y_out_valid),
        .dbg_y2(unused_comp_y2),
        .dbg_y2_valid(unused_comp_y2_valid),
        .dbg_y4(unused_comp_y4),
        .dbg_y4_valid(unused_comp_y4_valid),
        .dbg_y8(unused_comp_y8),
        .dbg_y8_valid(unused_comp_y8_valid),
        .dbg_y16(dbg_y16),
        .dbg_y16_valid(dbg_y16_valid),
        .dbg_y32(dbg_y32),
        .dbg_y32_valid(dbg_y32_valid),
        .dbg_y64(dbg_y64),
        .dbg_y64_valid(dbg_y64_valid)
    );

    // 平坦分支：复用同一结构参数但关闭Stage3补偿，用于输出正式4x/8x
    // 调试节点。该双实例包装器仅参与黄金向量仿真，不进入板级综合。
    interp128_all2x_v7_folded_fir_cic_top_ce #(
        .STAGE1_ACC_W(41),
        .STAGE23_ACC_W(38),
        .STAGE2_DATA_W(STAGE2_DATA_W),
        .CIC_ORDER(3),
        .FINAL_PRUNE_LSB(0),
        .USE_LUTRAM_STAGE23(1),
        .STAGE3_FLAT(1),
        .USE_CIC3_SHIFTADD_COMPENSATOR(0),
        .USE_BRAM_STAGE23_HISTORY(1),
        .USE_UNIFIED_BRAM_STAGE23_HISTORY(1),
        .USE_SINGLE_BRAM_STAGE1(1),
        .USE_BRAM_STAGE23_COEFF(1),
        .USE_PACKED_BRAM_STAGE23(0),
        .CIC_BURST_COUNTER_USE_DSP(0),
        .CIC_COMB_USE_DSP(0),
        .USE_SERIAL_CIC_COMB(1),
        .USE_N3_HOLD_EQUIV(1),
        .USE_STAGE1_DSP48_PREADDER(1),
        .USE_NATIONAL_FINALS_NARROW_STAGE23(1),
        .USE_P3_JOINT_STAGE3(1),
        .ASSUME_ALIGNED_POW2_CE(1),
        .CIC_INTEGRATOR_DSP_MODE(2),
        .USE_UNIFIED_FIR_COEFF_BRAM(1)
    ) u_p3_flat_core (
        .clk(clk),
        .rst_n(rst_n),
        .ce2_out(ce2_out),
        .ce4_out(ce4_out),
        .ce8_out(ce8_out),
        .ce16_out(ce16_out),
        .ce32_out(ce32_out),
        .ce64_out(ce64_out),
        .ce128_out(ce128_out),
        .x_in(x_in),
        .x_in_valid(x_in_valid),
        .stage3_compensated_mode(1'b0),
        .y_out(),
        .y_out_valid(),
        .dbg_y2(dbg_y2),
        .dbg_y2_valid(dbg_y2_valid),
        .dbg_y4(dbg_y4),
        .dbg_y4_valid(dbg_y4_valid),
        .dbg_y8(dbg_y8),
        .dbg_y8_valid(dbg_y8_valid),
        .dbg_y16(),
        .dbg_y16_valid(),
        .dbg_y32(),
        .dbg_y32_valid(),
        .dbg_y64(),
        .dbg_y64_valid()
    );

endmodule
