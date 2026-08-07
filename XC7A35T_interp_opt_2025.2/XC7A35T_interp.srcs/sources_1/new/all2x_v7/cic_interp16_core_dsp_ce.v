`timescale 1ns / 1ps

//=============================================================
// 文件名       : cic_interp16_core_dsp_ce.v
// 模块名       : cic_interp16_core_dsp_ce
// 功能简述     : CIC16 核心的 DSP48 优先映射候选。
//                算法、位宽、模运算、舍入和 valid 时序与正式
//                cic_interp16_core_ce 保持一致，仅在模块内部请求
//                Vivado 将宽位加减法优先映射到 DSP48E1。
//
// 当前默认配置：
//                  R=16，M=1，N=3
//                  输入输出：20bit signed
//                  内部位宽：32bit signed
//                  末级剪枝：由顶层参数覆盖
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-18
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-18：新增 DSP48 优先映射候选。
//                2026-07-18：禁止 5bit burst 计数器占用 DSP48E1，
//                            仅保留 CIC 宽位加减法的 DSP 优先映射。
//=============================================================

(* use_dsp = "yes" *)
module cic_interp16_core_dsp_ce #(
    parameter integer DATA_W = 20,
    parameter integer OUTPUT_W = DATA_W,
    parameter integer CIC_ORDER = 3,
    parameter integer FINAL_PRUNE_LSB = 3,
    parameter integer BURST_COUNTER_USE_DSP = 0
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ce_out,
    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,
    output reg  signed [OUTPUT_W-1:0]   y_out,
    output reg                          y_out_valid,
    output wire [4:0]                   burst_remaining_dbg,
    output wire                         pending_dbg
);

    localparam integer RATE_LOG2 = 4;
    localparam integer FULL_W = DATA_W + CIC_ORDER*RATE_LOG2;
    localparam integer FINAL_W = FULL_W - FINAL_PRUNE_LSB;
    localparam integer OUTPUT_SHIFT =
        (CIC_ORDER-1)*RATE_LOG2 - FINAL_PRUNE_LSB;

    reg signed [FULL_W-1:0] comb_delay [0:CIC_ORDER-1];
    reg signed [FULL_W-1:0] comb_stage_input [0:CIC_ORDER-1];
    reg signed [FULL_W-1:0] comb_stage_output [0:CIC_ORDER-1];
    reg signed [FULL_W-1:0] comb_work;

    reg signed [FULL_W-1:0] integrator_state [0:CIC_ORDER-2];
    reg signed [FULL_W-1:0] integrator_next [0:CIC_ORDER-2];
    reg signed [FULL_W-1:0] integrator_work;
    reg signed [FINAL_W-1:0] final_integrator_state;

    reg signed [FULL_W-1:0] burst_sample;
    reg burst_pending;
    reg [4:0] burst_remaining;
    wire [4:0] burst_remaining_decrement;

    wire signed [FULL_W-1:0] x_extended;
    wire output_event;
    wire first_output_event;
    wire signed [FULL_W-1:0] high_rate_input;
    wire signed [FINAL_W-1:0] final_input_rounded;
    wire signed [FINAL_W-1:0] final_integrator_next;
    wire signed [OUTPUT_W-1:0] normalized_output;

    integer comb_idx;
    integer integrator_idx;

    assign x_extended = {{(FULL_W-DATA_W){x_in[DATA_W-1]}}, x_in};
    assign output_event = ce_out &&
                          (burst_pending || burst_remaining != 5'd0);
    assign first_output_event = ce_out && burst_pending &&
                                burst_remaining == 5'd0;
    assign high_rate_input = first_output_event ? burst_sample :
                             {FULL_W{1'b0}};
    assign final_integrator_next = final_integrator_state +
                                   final_input_rounded;
    assign burst_remaining_dbg = burst_remaining;
    assign pending_dbg = burst_pending;

    generate
        if (BURST_COUNTER_USE_DSP != 0) begin : gen_dsp_burst_counter
            (* use_dsp = "yes" *) wire [4:0] decrement_impl;
            assign decrement_impl = burst_remaining - 5'd1;
            assign burst_remaining_decrement = decrement_impl;
        end
        else begin : gen_lut_burst_counter
            (* use_dsp = "no" *) wire [4:0] decrement_impl;
            assign decrement_impl = burst_remaining - 5'd1;
            assign burst_remaining_decrement = decrement_impl;
        end

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

    always @(*) begin
        comb_work = x_extended;
        for (comb_idx = 0; comb_idx < CIC_ORDER;
             comb_idx = comb_idx + 1) begin
            comb_stage_input[comb_idx] = comb_work;
            comb_stage_output[comb_idx] =
                comb_work - comb_delay[comb_idx];
            comb_work = comb_stage_output[comb_idx];
        end
    end

    always @(*) begin
        integrator_work = high_rate_input;
        for (integrator_idx = 0; integrator_idx < CIC_ORDER-1;
             integrator_idx = integrator_idx + 1) begin
            integrator_next[integrator_idx] =
                integrator_state[integrator_idx] + integrator_work;
            integrator_work = integrator_next[integrator_idx];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (comb_idx = 0; comb_idx < CIC_ORDER;
                 comb_idx = comb_idx + 1)
                comb_delay[comb_idx] <= {FULL_W{1'b0}};
            for (integrator_idx = 0; integrator_idx < CIC_ORDER-1;
                 integrator_idx = integrator_idx + 1)
                integrator_state[integrator_idx] <= {FULL_W{1'b0}};
            final_integrator_state <= {FINAL_W{1'b0}};
            burst_sample <= {FULL_W{1'b0}};
            burst_pending <= 1'b0;
            burst_remaining <= 5'd0;
            y_out <= {OUTPUT_W{1'b0}};
            y_out_valid <= 1'b0;
        end
        else begin
            y_out_valid <= 1'b0;

            if (x_in_valid) begin
                for (comb_idx = 0; comb_idx < CIC_ORDER;
                     comb_idx = comb_idx + 1)
                    comb_delay[comb_idx] <= comb_stage_input[comb_idx];
                burst_sample <= comb_stage_output[CIC_ORDER-1];
                burst_pending <= 1'b1;
            end

            if (output_event) begin
                for (integrator_idx = 0; integrator_idx < CIC_ORDER-1;
                     integrator_idx = integrator_idx + 1)
                    integrator_state[integrator_idx] <=
                        integrator_next[integrator_idx];
                final_integrator_state <= final_integrator_next;
                y_out <= normalized_output;
                y_out_valid <= 1'b1;

                if (first_output_event) begin
                    burst_pending <= 1'b0;
                    burst_remaining <= 5'd15;
                end
                else if (burst_remaining == 5'd1)
                    burst_remaining <= 5'd0;
                else
                    burst_remaining <= burst_remaining_decrement;
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && x_in_valid && burst_pending)
            $fatal(1, "CIC comb result pending overwrite");
        if (rst_n && CIC_ORDER != 3 && CIC_ORDER != 4)
            $fatal(1, "CIC_ORDER must be 3 or 4");
        if (rst_n && OUTPUT_SHIFT < 1)
            $fatal(1, "CIC output normalization shift is invalid");
        if (rst_n && BURST_COUNTER_USE_DSP != 0 &&
            BURST_COUNTER_USE_DSP != 1)
            $fatal(1, "BURST_COUNTER_USE_DSP must be 0 or 1");
    end
`endif

endmodule
