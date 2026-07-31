`timescale 1ns / 1ps

//=============================================================
// 文件名       : cic_interp16_serial_comb_dsp_ce.v
// 模块名       : cic_interp16_serial_comb_dsp_ce
// 功能简述     : 全国赛 CIC16 N=3 的低 DSP 候选。
//
//                原实现将三级低速 comb 差分在一个时钟周期内
//                级联计算，综合为 3 个 DSP48E1。本模块利用 8x
//                输入每 16 个 128x 时钟才到达一次的周期余量，
//                用同一个 DSP 在 3 拍内顺序完成三级差分。
//
//                三个高速 integrator 仍保持每拍并行更新，因而
//                稳态输出仍为每个 ce_out 一点。除初始 valid
//                延迟增加外，输出有效样点序列、32 bit 模运算、
//                归一化舍入和饱和均与原 DSP 核逐点一致。
//
// 当前默认配置：
//                  R=16，M=1，N=3
//                  输入输出：20 bit signed
//                  内部位宽：32 bit signed
//                  DSP 数量：1 comb + 3 integrator = 4
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-29
// 版本         : V2018.3
// 开发工具     : Vivado
//=============================================================

(* use_dsp = "yes" *)
module cic_interp16_serial_comb_dsp_ce #(
    parameter integer DATA_W = 20,
    parameter integer OUTPUT_W = DATA_W,
    parameter integer FINAL_PRUNE_LSB = 0,
    parameter integer BURST_COUNTER_USE_DSP = 0,
    // The three high-rate integrators remain DSP-resident.  The low-rate
    // serial comb has sixteen clocks per input and may use the LUT carry
    // chain to save one DSP48E1 at a small LUT cost.
    parameter integer COMB_USE_DSP = 0
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ce_out,
    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,
    output reg  signed [OUTPUT_W-1:0]   y_out,
    output reg                          y_out_valid,
    output wire [4:0]                   burst_remaining_dbg,
    output wire                         pending_dbg,
    output wire                         comb_busy_dbg
);

    localparam integer CIC_ORDER = 3;
    localparam integer RATE_LOG2 = 4;
    localparam integer FULL_W = DATA_W + CIC_ORDER*RATE_LOG2;
    localparam integer COMB_W = DATA_W + CIC_ORDER;
    localparam integer COMB_DELAY_W = DATA_W + CIC_ORDER - 1;
    localparam integer FINAL_W = FULL_W - FINAL_PRUNE_LSB;
    localparam integer OUTPUT_SHIFT =
        (CIC_ORDER-1)*RATE_LOG2 - FINAL_PRUNE_LSB;

    // The kth finite difference grows by at most one bit. Keeping the
    // low-rate comb state at 20/21/22/23 bits is mathematically lossless;
    // only the high-rate integrators require the full 32-bit CIC width.
    // Rotate the three low-rate histories during the three serial comb
    // cycles.  The selected delay is then always comb_delay0, eliminating a
    // COMB_W-bit 3:1 mux at the DSP input.  A uniform DATA_W+2 history width
    // exactly covers the widest stored second difference and costs only
    // three additional state bits versus the former 20/21/22-bit banks.
    reg signed [COMB_DELAY_W-1:0] comb_delay0;
    reg signed [COMB_DELAY_W-1:0] comb_delay1;
    reg signed [COMB_DELAY_W-1:0] comb_delay2;
    reg signed [COMB_W-1:0] comb_operand;
    reg [1:0] comb_stage_index;
    reg comb_active;

    reg signed [FULL_W-1:0] integrator_state [0:CIC_ORDER-2];
    reg signed [FULL_W-1:0] integrator_next [0:CIC_ORDER-2];
    reg signed [FULL_W-1:0] integrator_work;
    reg signed [FINAL_W-1:0] final_integrator_state;

    reg burst_pending;
    reg [3:0] burst_remaining;

    wire signed [COMB_W-1:0] x_comb_extended;
    wire signed [COMB_W-1:0] comb_delay_selected;
    wire signed [COMB_W-1:0] comb_stage_result;
    wire output_event;
    wire first_output_event;
    wire signed [FULL_W-1:0] high_rate_input;
    wire signed [FINAL_W-1:0] final_input_rounded;
    wire signed [FINAL_W-1:0] final_integrator_next;
    wire signed [OUTPUT_W-1:0] normalized_output;
    (* use_dsp = "no" *) wire [3:0] burst_remaining_decrement;
    (* use_dsp = "no" *) wire [1:0] comb_stage_index_increment;

    integer integrator_idx;
    integer integrator_state_idx;

    assign x_comb_extended =
        {{(COMB_W-DATA_W){x_in[DATA_W-1]}}, x_in};
    assign comb_delay_selected =
        {{(COMB_W-COMB_DELAY_W){comb_delay0[COMB_DELAY_W-1]}},
         comb_delay0};

    // Progressive widths are exact for the three finite differences.
    // Keep both mappings explicit so synthesis reports, rather than an
    // inference heuristic, decide the 5-DSP candidate's Stop/Go result.
    generate
        if (COMB_USE_DSP != 0) begin : gen_comb_dsp
            (* use_dsp = "yes" *)
            wire signed [COMB_W-1:0] comb_stage_result_dsp;
            assign comb_stage_result_dsp =
                comb_operand - comb_delay_selected;
            assign comb_stage_result = comb_stage_result_dsp;
        end
        else begin : gen_comb_lut
            (* use_dsp = "no" *)
            wire signed [COMB_W-1:0] comb_stage_result_lut;
            assign comb_stage_result_lut =
                comb_operand - comb_delay_selected;
            assign comb_stage_result = comb_stage_result_lut;
        end
    endgenerate

    assign output_event = ce_out &&
                          (burst_pending || burst_remaining != 4'd0);
    assign first_output_event = ce_out && burst_pending &&
                                burst_remaining == 4'd0;
    // Once the third comb subtraction completes, comb_operand itself holds
    // the burst sample. Reusing it avoids a duplicate FULL_W-bit register.
    assign high_rate_input = first_output_event ?
        {{(FULL_W-COMB_W){comb_operand[COMB_W-1]}}, comb_operand} :
                             {FULL_W{1'b0}};
    assign final_integrator_next = final_integrator_state +
                                   final_input_rounded;

    assign burst_remaining_dbg = {1'b0, burst_remaining};
    assign pending_dbg = burst_pending;
    assign comb_busy_dbg = comb_active;

    assign burst_remaining_decrement = burst_remaining - 4'd1;
    assign comb_stage_index_increment = comb_stage_index + 2'd1;

    generate
        if (FINAL_PRUNE_LSB == 0) begin : gen_no_final_pruning
            assign final_input_rounded = integrator_work;
        end
        else begin : gen_final_pruning
            round_sat_shift_compact #(
                .IN_W    (FULL_W),
                .OUT_W   (FINAL_W),
                .SHIFT_N (FINAL_PRUNE_LSB)
            ) u_round_final_integrator_input (
                .din  (integrator_work),
                .dout (final_input_rounded)
            );
        end
    endgenerate

    round_sat_shift_compact #(
        .IN_W    (FINAL_W),
        .OUT_W   (OUTPUT_W),
        .SHIFT_N (OUTPUT_SHIFT)
    ) u_round_cic_normalized_output (
        .din  (final_integrator_next),
        .dout (normalized_output)
    );

    // 三个高速积分器必须每个 128x 输出周期同时更新，继续并行映射。
    always @(*) begin
        integrator_work = high_rate_input;
        for (integrator_idx = 0; integrator_idx < CIC_ORDER-1;
             integrator_idx = integrator_idx + 1) begin
            integrator_next[integrator_idx] =
                integrator_state[integrator_idx] + integrator_work;
            integrator_work = integrator_next[integrator_idx];
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            comb_delay0 <= {COMB_DELAY_W{1'b0}};
            comb_delay1 <= {COMB_DELAY_W{1'b0}};
            comb_delay2 <= {COMB_DELAY_W{1'b0}};
            comb_operand <= {COMB_W{1'b0}};
            comb_stage_index <= 2'd0;
            comb_active <= 1'b0;

            final_integrator_state <= {FINAL_W{1'b0}};

            burst_pending <= 1'b0;
            burst_remaining <= 4'd0;
            y_out <= {OUTPUT_W{1'b0}};
            y_out_valid <= 1'b0;
        end
        else begin
            y_out_valid <= 1'b0;

            if (x_in_valid) begin
                comb_operand <= x_comb_extended;
                comb_stage_index <= 2'd0;
                comb_active <= 1'b1;
            end

            if (comb_active) begin
                comb_delay0 <= comb_delay1;
                comb_delay1 <= comb_delay2;
                comb_delay2 <= comb_operand[COMB_DELAY_W-1:0];
                comb_operand <= comb_stage_result;

                if (comb_stage_index == CIC_ORDER-1) begin
                    burst_pending <= 1'b1;
                    comb_active <= 1'b0;
                end
                else begin
                    comb_stage_index <= comb_stage_index_increment;
                end
            end

            if (output_event) begin
                final_integrator_state <= final_integrator_next;
                y_out <= normalized_output;
                y_out_valid <= 1'b1;

                if (first_output_event) begin
                    burst_pending <= 1'b0;
                    burst_remaining <= 4'd15;
                end
                else if (burst_remaining == 4'd1) begin
                    burst_remaining <= 4'd0;
                end
                else begin
                    burst_remaining <= burst_remaining_decrement;
                end
            end
        end
    end

    // The two hidden intermediate integrators use synchronous reset so Vivado
    // can absorb them into DSP48E1 internal registers.  The externally visible
    // output and final CIC state retain asynchronous reset.
    always @(posedge clk) begin
        if (!rst_n) begin
            for (integrator_state_idx = 0;
                 integrator_state_idx < CIC_ORDER-1;
                 integrator_state_idx = integrator_state_idx + 1)
                integrator_state[integrator_state_idx] <=
                    {FULL_W{1'b0}};
        end
        else if (output_event) begin
            for (integrator_state_idx = 0;
                 integrator_state_idx < CIC_ORDER-1;
                 integrator_state_idx = integrator_state_idx + 1)
                integrator_state[integrator_state_idx] <=
                    integrator_next[integrator_state_idx];
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && x_in_valid && comb_active)
            $fatal(1, "Serial CIC comb input overwrite");
        if (rst_n && x_in_valid && burst_pending)
            $fatal(1, "Serial CIC burst pending overwrite");
        if (rst_n && comb_stage_index >= CIC_ORDER)
            $fatal(1, "Serial CIC comb stage index out of range");
        if (rst_n && BURST_COUNTER_USE_DSP != 0)
            $fatal(1, "Serial CIC only supports LUT burst counter");
        if (rst_n && COMB_USE_DSP != 0 && COMB_USE_DSP != 1)
            $fatal(1, "COMB_USE_DSP must be 0 or 1");
        if (rst_n && OUTPUT_SHIFT < 1)
            $fatal(1, "Serial CIC output normalization shift is invalid");
    end
`endif

endmodule
