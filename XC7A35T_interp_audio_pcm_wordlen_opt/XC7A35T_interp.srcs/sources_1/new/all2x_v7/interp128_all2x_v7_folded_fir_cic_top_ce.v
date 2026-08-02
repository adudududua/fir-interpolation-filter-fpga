`timescale 1ns / 1ps

//=============================================================
// 文件名       : interp128_all2x_v7_folded_fir_cic_top_ce.v
// 模块名       : interp128_all2x_v7_folded_fir_cic_top_ce
// 功能简述     : Phase 7 折叠补偿 FIR-CIC 128 倍实验顶层。
//                前两级保持 Phase 6 的 BRAM/共享 DSP 与
//                24/22bit 数据格式；第三级仍为 11tap 2x FIR，
//                但系数同时承担 CIC 通带补偿。原 Stage4～7
//                四级 2x FIR 由一个 16 倍 CIC 取代。
//
//                调试输出仍提供 2x/4x/8x 节点，最终 20bit CIC
//                输出左移 4bit 恢复为 24bit PCM 标度。
//
// 当前默认配置：
//                  输入采样率：44.1kHz
//                  输出采样率：5.6448MHz
//                  候选 A    ：N=3，CIC 保持全精度
//                  候选 B    ：N=4，CIC 最后一级丢弃 7 LSB
//                  FIR DSP   ：2（Stage1 + Stage2/3 共享）
//                  CIC DSP   ：6（三级差分 + 三级积分）
//                  默认总数  ：8（burst 计数器使用 LUT 进位链）
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-13
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-13：新增 Stage3 折叠补偿 FIR-CIC 顶层。
//                2026-07-18：CIC 宽位加减法改用 DSP48 优先映射候选。
//                2026-07-18：增加 Stage 2/3 单读 LUTRAM 资源候选；
//                            默认关闭，不改变稳定板级版本行为。
//                2026-07-18：增加 Stage 2/3 BRAM 历史缓存候选参数。
//                2026-07-18：增加 CIC burst 计数器 DSP/LUT 选择参数。
//                2026-07-18：增加 Stage2/3 交叉系数 BRAM 打包参数。
//=============================================================

module interp128_all2x_v7_folded_fir_cic_top_ce #(
    parameter integer STAGE1_ACC_W = 42,
    parameter integer STAGE23_ACC_W = 38,
    parameter integer CIC_ORDER = 3,
    parameter integer FINAL_PRUNE_LSB = 3,
    parameter integer USE_LUTRAM_STAGE23 = 0,
    parameter integer STAGE3_FLAT = 0,
    parameter integer USE_CIC3_SHIFTADD_COMPENSATOR = 0,
    parameter integer USE_BRAM_STAGE23_HISTORY = 0,
    parameter integer USE_UNIFIED_BRAM_STAGE23_HISTORY = 0,
    parameter integer USE_SINGLE_BRAM_STAGE1 = 0,
    parameter integer USE_BRAM_STAGE23_COEFF = 0,
    parameter integer USE_PACKED_BRAM_STAGE23 = 0,
    parameter integer CIC_BURST_COUNTER_USE_DSP = 0,
    parameter integer CIC_COMB_USE_DSP = 0,
    parameter integer USE_SERIAL_CIC_COMB = 0,
    parameter integer USE_N3_HOLD_EQUIV = 0,
    parameter integer USE_STAGE1_DSP48_PREADDER = 0,
    parameter integer USE_NATIONAL_FINALS_NARROW_STAGE23 = 0,
    parameter integer USE_P3_JOINT_STAGE3 = 0,
    parameter integer ASSUME_ALIGNED_POW2_CE = 0,
    parameter integer CIC_INTEGRATOR_DSP_MODE = 2,
    parameter integer USE_SHARED_PCM_STAGE1_BRAM = 0,
    parameter integer USE_UNIFIED_FIR_COEFF_BRAM =
        USE_BRAM_STAGE23_COEFF
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
    input  wire                         stage3_compensated_mode,
    input  wire                         pcm_sample_ce,
    input  wire                         pcm_family_48k,
    output wire signed [23:0]           pcm_sample_out,
    output wire                         pcm_sample_update,
    output wire [7:0]                   pcm_sample_addr_dbg,
    output wire                         pcm_deadline_miss_dbg,
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
    localparam integer STAGE3_RESULT_W =
        (USE_P3_JOINT_STAGE3 != 0) ? 21 : 20;
    wire signed [STAGE3_RESULT_W-1:0] y8_w;
    wire y8_valid_w;
    wire signed [20:0] y8_extended_w;
    wire y8_debug_overflow_w;
    wire signed [19:0] y8_debug_20_w;
    wire signed [20:0] cic_x_w;
    wire cic_x_valid_w;
    wire signed [19:0] y128_w;
    wire y128_valid_w;
    wire [4:0] stage1_coeff_addr_w;
    wire signed [15:0] stage1_coeff_data_w;
    wire [6:0] stage23_coeff_addr_w;
    wire signed [17:0] stage23_coeff_data_w;
    wire signed [23:0] stage1_pcm_sample_w;
    wire stage1_pcm_update_w;
    wire [7:0] stage1_pcm_addr_w;
    wire stage1_pcm_deadline_miss_w;

    wire unused_ce;
    assign unused_ce = ce16_out ^ ce32_out ^ ce64_out;

    generate
        if (USE_UNIFIED_FIR_COEFF_BRAM != 0) begin :
                gen_unified_fir_coeff_bram
            nf_unified_fir_coeff_bram u_nf_unified_fir_coeff_bram (
                .clk(clk),
                .stage1_addr(stage1_coeff_addr_w),
                .stage1_coeff(stage1_coeff_data_w),
                .stage23_addr(stage23_coeff_addr_w),
                .stage23_coeff(stage23_coeff_data_w)
            );
        end
        else begin : gen_no_unified_fir_coeff_bram
            assign stage1_coeff_data_w = 16'sd0;
            assign stage23_coeff_data_w = 18'sd0;
        end
    endgenerate

    generate
        if (USE_SINGLE_BRAM_STAGE1 != 0) begin : gen_single_bram_stage1
            interp2_stage1_single_bram_serial_ce #(
                .DATA_W(24),
                .ACC_W(STAGE1_ACC_W),
                .USE_DSP48_PREADDER(USE_STAGE1_DSP48_PREADDER),
                .USE_EXTERNAL_COEFF_BRAM(USE_UNIFIED_FIR_COEFF_BRAM),
                .USE_SHARED_PCM_BRAM(USE_SHARED_PCM_STAGE1_BRAM)
            ) u_interp2_stage1_strict_halfband_bram_ce (
                .clk(clk), .rst_n(rst_n), .ce_out(ce2_out),
                .x_in(x_in), .x_in_valid(x_in_valid),
                .y_out(y2_w), .y_out_valid(y2_valid_w),
                .phase_dbg(), .fir_in_dbg(), .fir_in_valid_dbg(),
                .external_coeff_addr(stage1_coeff_addr_w),
                .external_coeff_data(stage1_coeff_data_w),
                .pcm_sample_ce(pcm_sample_ce),
                .pcm_family_48k(pcm_family_48k),
                .pcm_sample_out(stage1_pcm_sample_w),
                .pcm_sample_update(stage1_pcm_update_w),
                .pcm_sample_addr_dbg(stage1_pcm_addr_w),
                .pcm_deadline_miss_dbg(stage1_pcm_deadline_miss_w)
            );
        end
        else begin : gen_dual_bram_stage1
            assign stage1_pcm_sample_w = 24'sd0;
            assign stage1_pcm_update_w = 1'b0;
            assign stage1_pcm_addr_w = 8'd0;
            assign stage1_pcm_deadline_miss_w = 1'b0;
            interp2_stage1_strict_halfband_bram_ce #(
                .DATA_W(24),
                .ACC_W(STAGE1_ACC_W),
                .USE_DSP48_PREADDER(USE_STAGE1_DSP48_PREADDER),
                .USE_EXTERNAL_COEFF_BRAM(USE_UNIFIED_FIR_COEFF_BRAM)
            ) u_interp2_stage1_strict_halfband_bram_ce (
                .clk(clk), .rst_n(rst_n), .ce_out(ce2_out),
                .x_in(x_in), .x_in_valid(x_in_valid),
                .y_out(y2_w), .y_out_valid(y2_valid_w),
                .phase_dbg(), .fir_in_dbg(), .fir_in_valid_dbg(),
                .external_coeff_addr(stage1_coeff_addr_w),
                .external_coeff_data(stage1_coeff_data_w)
            );
        end
    endgenerate

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

    generate
        if (USE_LUTRAM_STAGE23 != 0) begin : gen_lutram_stage23
            interp2_stage23_lutram_cic_dsp_ce #(
                .DATA_W(24),
                .STAGE2_DATA_W(22),
                .STAGE3_DATA_W(20),
                .STAGE3_OUTPUT_W(STAGE3_RESULT_W),
                .COEFF_W((USE_P3_JOINT_STAGE3 != 0) ? 18 :
                         ((USE_NATIONAL_FINALS_NARROW_STAGE23 != 0) ?
                          16 : 18)),
                .ACC_W(STAGE23_ACC_W),
                .CIC_ORDER(CIC_ORDER),
                .STAGE3_FLAT(STAGE3_FLAT),
                .USE_BRAM_HISTORY(USE_BRAM_STAGE23_HISTORY),
                .USE_UNIFIED_BRAM_HISTORY(
                    USE_UNIFIED_BRAM_STAGE23_HISTORY),
                .USE_BRAM_COEFF(USE_BRAM_STAGE23_COEFF),
                .USE_PACKED_BRAM(USE_PACKED_BRAM_STAGE23),
                .USE_EXTERNAL_COEFF_BRAM(USE_UNIFIED_FIR_COEFF_BRAM),
                .USE_P3_JOINT_STAGE3(USE_P3_JOINT_STAGE3),
                .ASSUME_ALIGNED_POW2_CE(ASSUME_ALIGNED_POW2_CE)
            ) u_interp2_stage23_lutram_cic_dsp_ce (
                .clk(clk), .rst_n(rst_n),
                .stage2_ce_out(ce4_out),
                .stage2_x_in(y2_to_4_data),
                .stage2_x_in_valid(y2_to_4_valid),
                .stage2_y_out(y4_w),
                .stage2_y_out_valid(y4_valid_w),
                .stage3_ce_out(ce8_out),
                .stage3_x_in(y4_to_8_data),
                .stage3_x_in_valid(y4_to_8_valid),
                .stage3_compensated_mode(stage3_compensated_mode),
                .stage3_y_out(y8_w),
                .stage3_y_out_valid(y8_valid_w),
                .stage2_phase_dbg(), .stage3_phase_dbg(),
                .scheduler_busy_dbg(), .scheduler_stage_dbg(),
                .scheduler_mac_index_dbg(),
                .external_coeff_addr(stage23_coeff_addr_w),
                .external_coeff_data(stage23_coeff_data_w)
            );
        end
        else begin : gen_register_stage23
            assign stage23_coeff_addr_w = 6'd0;
            interp2_stage23_folded_cic_dsp_ce #(
                .DATA_W(24),
                .STAGE2_DATA_W(22),
                .STAGE3_DATA_W(20),
                .COEFF_W(16),
                .ACC_W(STAGE23_ACC_W),
                .CIC_ORDER(CIC_ORDER)
            ) u_interp2_stage23_folded_cic_dsp_ce (
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
        end
    endgenerate

    generate
        if (USE_P3_JOINT_STAGE3 != 0) begin :
                gen_p3_joint_stage3_compensator
            assign cic_x_w =
                {{(21-STAGE3_RESULT_W){y8_w[STAGE3_RESULT_W-1]}}, y8_w};
            assign cic_x_valid_w = y8_valid_w;
        end
        else if (USE_CIC3_SHIFTADD_COMPENSATOR != 0) begin :
                gen_cic3_shiftadd_compensator
            cic3_compensator_shiftadd_ce #(
                .DATA_W(20),
                .OUTPUT_W(21),
                .REGISTER_OUTPUT((USE_SERIAL_CIC_COMB != 0 ||
                                  USE_N3_HOLD_EQUIV != 0) ? 0 : 1)
            ) u_cic3_compensator_shiftadd_ce (
                .clk(clk),
                .rst_n(rst_n),
                .x_in(y8_w[19:0]),
                .x_in_valid(y8_valid_w),
                .y_out(cic_x_w),
                .y_out_valid(cic_x_valid_w)
            );
        end
        else begin : gen_no_cic3_shiftadd_compensator
            assign cic_x_w = {y8_w[19], y8_w};
            assign cic_x_valid_w = y8_valid_w;
        end
    endgenerate

    generate
        if (USE_N3_HOLD_EQUIV != 0) begin : gen_serial_cic_comb
            cic_interp16_n3_hold2_dsp_ce #(
                .DATA_W          (21),
                .OUTPUT_W        (20),
                .FINAL_PRUNE_LSB (FINAL_PRUNE_LSB),
                .BURST_COUNTER_USE_DSP(CIC_BURST_COUNTER_USE_DSP),
                .INTEGRATOR_DSP_MODE(CIC_INTEGRATOR_DSP_MODE)
            ) u_cic_interp16_serial_comb_dsp_ce (
                .clk                  (clk),
                .rst_n                (rst_n),
                .ce_out               (ce128_out),
                .x_in                 (cic_x_w),
                .x_in_valid           (cic_x_valid_w),
                .y_out                (y128_w),
                .y_out_valid          (y128_valid_w),
                .burst_remaining_dbg  (),
                .pending_dbg          (),
                .comb_busy_dbg        ()
            );
        end
        else if (USE_SERIAL_CIC_COMB != 0) begin : gen_serial_cic_comb_legacy
            cic_interp16_serial_comb_dsp_ce #(
                .DATA_W          (21),
                .OUTPUT_W        (20),
                .FINAL_PRUNE_LSB (FINAL_PRUNE_LSB),
                .BURST_COUNTER_USE_DSP(CIC_BURST_COUNTER_USE_DSP),
                .COMB_USE_DSP(CIC_COMB_USE_DSP)
            ) u_cic_interp16_serial_comb_dsp_ce (
                .clk                  (clk),
                .rst_n                (rst_n),
                .ce_out               (ce128_out),
                .x_in                 (cic_x_w),
                .x_in_valid           (cic_x_valid_w),
                .y_out                (y128_w),
                .y_out_valid          (y128_valid_w),
                .burst_remaining_dbg  (),
                .pending_dbg          (),
                .comb_busy_dbg        ()
            );
        end
        else begin : gen_parallel_cic_comb
            cic_interp16_core_dsp_ce #(
                .DATA_W          (21),
                .OUTPUT_W        (20),
                .CIC_ORDER       (CIC_ORDER),
                .FINAL_PRUNE_LSB (FINAL_PRUNE_LSB),
                .BURST_COUNTER_USE_DSP(CIC_BURST_COUNTER_USE_DSP)
            ) u_cic_interp16_core_dsp_ce (
                .clk                  (clk),
                .rst_n                (rst_n),
                .ce_out               (ce128_out),
                .x_in                 (cic_x_w),
                .x_in_valid           (cic_x_valid_w),
                .y_out                (y128_w),
                .y_out_valid          (y128_valid_w),
                .burst_remaining_dbg  (),
                .pending_dbg          ()
            );
        end
    endgenerate

    assign y_out = {y128_w, 4'b0};
    assign pcm_sample_out = stage1_pcm_sample_w;
    assign pcm_sample_update = stage1_pcm_update_w;
    assign pcm_sample_addr_dbg = stage1_pcm_addr_w;
    assign pcm_deadline_miss_dbg = stage1_pcm_deadline_miss_w;
    assign y_out_valid = y128_valid_w;
    assign dbg_y2 = y2_w;
    assign dbg_y2_valid = y2_valid_w;
    assign dbg_y4 = {y4_w, 2'b0};
    assign dbg_y4_valid = y4_valid_w;
    // P3-J keeps a signed-21 Stage3 result for the compensated 128x path,
    // but the visible 8x node retains the original saturating signed-20 PCM
    // format.  Saturate the one extra bit here; direct truncation would turn
    // a positive near-full-scale sample into a negative output.
    assign y8_extended_w =
        {{(21-STAGE3_RESULT_W){y8_w[STAGE3_RESULT_W-1]}}, y8_w};
    assign y8_debug_overflow_w =
        (USE_P3_JOINT_STAGE3 != 0) &&
        (y8_extended_w[20] != y8_extended_w[19]);
    assign y8_debug_20_w = !y8_debug_overflow_w ? y8_extended_w[19:0] :
        (y8_extended_w[20] ? 20'sh80000 : 20'sh7ffff);
    assign dbg_y8 = {y8_debug_20_w, 4'b0};
    assign dbg_y8_valid = y8_valid_w;
    assign dbg_y16 = 24'sd0;
    assign dbg_y16_valid = 1'b0;
    assign dbg_y32 = 24'sd0;
    assign dbg_y32_valid = 1'b0;
    assign dbg_y64 = 24'sd0;
    assign dbg_y64_valid = 1'b0;

`ifndef SYNTHESIS
    initial begin
        if (STAGE3_FLAT != 0 && USE_LUTRAM_STAGE23 == 0)
            $fatal(1, "STAGE3_FLAT currently requires LUTRAM/BRAM Stage23");
        if (USE_CIC3_SHIFTADD_COMPENSATOR != 0 && STAGE3_FLAT == 0)
            $fatal(1, "CIC3 shift-add compensator requires flat Stage3");
        if (USE_P3_JOINT_STAGE3 != 0 &&
            (STAGE3_FLAT == 0 || USE_CIC3_SHIFTADD_COMPENSATOR != 0 ||
             USE_UNIFIED_FIR_COEFF_BRAM == 0))
            $fatal(1, "P3 requires flat/compensated external bank and no separate equalizer");
        if (USE_SERIAL_CIC_COMB != 0 && CIC_ORDER != 3)
            $fatal(1, "Serial CIC comb candidate requires CIC_ORDER=3");
        if (USE_N3_HOLD_EQUIV != 0 && CIC_ORDER != 3)
            $fatal(1, "N=3 Hold CIC rewrite requires CIC_ORDER=3");
        if (USE_SINGLE_BRAM_STAGE1 != 0 &&
            USE_SINGLE_BRAM_STAGE1 != 1)
            $fatal(1, "USE_SINGLE_BRAM_STAGE1 must be 0 or 1");
        if (USE_SHARED_PCM_STAGE1_BRAM != 0 &&
            USE_SINGLE_BRAM_STAGE1 == 0)
            $fatal(1, "Shared PCM/Stage1 BRAM requires single-BRAM Stage1");
    end

    always @(posedge clk) begin
        if (rst_n && unused_ce === 1'bx)
            $fatal(1, "Unused intermediate CE input contains X");
    end

    generate
        if (USE_P3_JOINT_STAGE3 != 0) begin : g_p3_debug_saturation_assert
            always @(posedge clk) begin
                if (rst_n && !stage3_compensated_mode && y8_valid_w &&
                    y8_debug_overflow_w &&
                    y8_debug_20_w !=
                        (y8_extended_w[20] ? 20'sh80000 : 20'sh7ffff))
                    $fatal(1, "Flat Stage3 signed-20 saturation failed");
            end
        end
    endgenerate
`endif

endmodule
