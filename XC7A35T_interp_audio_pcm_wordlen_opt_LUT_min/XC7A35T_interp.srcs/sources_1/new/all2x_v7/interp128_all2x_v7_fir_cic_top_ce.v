`timescale 1ns / 1ps

//=============================================================
// 文件名       : interp128_all2x_v7_fir_cic_top_ce.v
// 模块名       : interp128_all2x_v7_fir_cic_top_ce
// 功能简述     : Phase 7 FIR-CIC 混合 128 倍插值实验顶层。
//                前三级保持 Phase 6 的 BRAM/共享 DSP 与
//                24/22/20bit 数据格式，Stage4～7 的四级 2x
//                canonical FIR 改为低速 15tap 补偿 FIR 和
//                16 倍 CIC 插值器。
//
//                调试输出仍提供 2x/4x/8x 节点，最终 20bit CIC
//                输出左移 4bit 恢复为 24bit PCM 标度。
//
// 当前默认配置：
//                  输入采样率：44.1kHz
//                  输出采样率：5.6448MHz
//                  候选 A    ：N=3，最后一级丢弃 3 LSB
//                  候选 B    ：N=4，最后一级丢弃 6 LSB
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-13
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-13：新增 Phase 7 FIR-CIC 混合顶层。
//=============================================================

module interp128_all2x_v7_fir_cic_top_ce #(
    parameter integer STAGE23_ACC_W = 38,
    parameter integer CIC_ORDER = 3,
    parameter integer FINAL_PRUNE_LSB = 3
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
    input  wire signed [23:0]           x_in,
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
    wire signed [21:0] y2_to_4_data;
    wire y2_to_4_valid;
    wire signed [21:0] y4_w;
    wire y4_valid_w;
    wire signed [19:0] y4_to_8_data;
    wire y4_to_8_valid;
    wire signed [19:0] y8_w;
    wire y8_valid_w;
    wire signed [19:0] y128_w;
    wire y128_valid_w;

    wire unused_ce;
    assign unused_ce = ce16_out ^ ce32_out ^ ce64_out;

    interp2_stage1_strict_halfband_bram_ce #(
        .DATA_W (24)
    ) u_interp2_stage1_strict_halfband_bram_ce (
        .clk(clk), .rst_n(rst_n), .ce_out(ce2_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(y2_w), .y_out_valid(y2_valid_w),
        .phase_dbg(), .fir_in_dbg(), .fir_in_valid_dbg()
    );

    bridge_valid_quantized_to_interp2_ce #(
        .IN_W(24), .OUT_W(22), .SHIFT_N(2)
    ) u_bridge_2_to_4_quantized (
        .clk(clk), .rst_n(rst_n),
        .in_data(y2_w), .in_valid(y2_valid_w),
        .ce_out_next(ce4_out),
        .out_data(y2_to_4_data), .out_valid(y2_to_4_valid)
    );

    bridge_valid_quantized_to_interp2_ce #(
        .IN_W(22), .OUT_W(20), .SHIFT_N(2)
    ) u_bridge_4_to_8_quantized (
        .clk(clk), .rst_n(rst_n),
        .in_data(y4_w), .in_valid(y4_valid_w),
        .ce_out_next(ce8_out),
        .out_data(y4_to_8_data), .out_valid(y4_to_8_valid)
    );

    interp2_stage23_shared_dsp_ce #(
        .DATA_W(24),
        .STAGE2_DATA_W(22),
        .STAGE3_DATA_W(20),
        .COEFF_W(16),
        .ACC_W(STAGE23_ACC_W)
    ) u_interp2_stage23_shared_dsp_ce (
        .clk(clk), .rst_n(rst_n),
        .stage2_ce_out(ce4_out),
        .stage2_x_in(y2_to_4_data),
        .stage2_x_in_valid(y2_to_4_valid),
        .stage2_y_out(y4_w),
        .stage2_y_out_valid(y4_valid_w),
        .stage3_ce_out(ce8_out),
        .stage3_x_in(y4_to_8_data),
        .stage3_x_in_valid(y4_to_8_valid),
        .stage3_y_out(y8_w),
        .stage3_y_out_valid(y8_valid_w),
        .stage2_phase_dbg(), .stage3_phase_dbg(),
        .scheduler_busy_dbg(), .scheduler_stage_dbg(),
        .scheduler_mac_index_dbg()
    );

    cic_interp16_top #(
        .DATA_W          (20),
        .CIC_ORDER       (CIC_ORDER),
        .FINAL_PRUNE_LSB (FINAL_PRUNE_LSB)
    ) u_cic_interp16_top (
        .clk                  (clk),
        .rst_n                (rst_n),
        .ce_out               (ce128_out),
        .x_in                 (y8_w),
        .x_in_valid           (y8_valid_w),
        .y_out                (y128_w),
        .y_out_valid          (y128_valid_w),
        .compensation_busy_dbg(),
        .burst_remaining_dbg  ()
    );

    assign y_out = {y128_w, 4'b0};
    assign y_out_valid = y128_valid_w;
    assign dbg_y2 = y2_w;
    assign dbg_y2_valid = y2_valid_w;
    assign dbg_y4 = {y4_w, 2'b0};
    assign dbg_y4_valid = y4_valid_w;
    assign dbg_y8 = {y8_w, 4'b0};
    assign dbg_y8_valid = y8_valid_w;
    assign dbg_y16 = 24'sd0;
    assign dbg_y16_valid = 1'b0;
    assign dbg_y32 = 24'sd0;
    assign dbg_y32_valid = 1'b0;
    assign dbg_y64 = 24'sd0;
    assign dbg_y64_valid = 1'b0;

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && unused_ce === 1'bx)
            $fatal(1, "Unused intermediate CE input contains X");
    end
`endif

endmodule
