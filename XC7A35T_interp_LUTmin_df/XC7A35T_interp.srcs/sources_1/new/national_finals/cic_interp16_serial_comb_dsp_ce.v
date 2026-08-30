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
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     : V2025.2 统一文件头并补充串行梳状器结构说明。
//=============================================================

(* use_dsp = "yes" *)
module cic_interp16_serial_comb_dsp_ce #(
    parameter integer DATA_W = 20,
    parameter integer OUTPUT_W = DATA_W,
    parameter integer FINAL_PRUNE_LSB = 0,
    parameter integer BURST_COUNTER_USE_DSP = 0,
    // 三级高速积分器固定映射到 DSP48E1；低速串行梳状器在相邻输入间
    // 具有16个工作时钟，可选择 LUT 进位链，以少量 LUT 换取1个DSP节省。
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

    // 第k阶有限差分最多增长1位，因此低速梳状状态采用20/21/22/23位在
    // 数学上无损，只有高速积分器需要完整32位CIC宽度。三级串行梳状周期
    // 内轮转三组低速历史，使所选延迟始终位于comb_delay0，消除DSP输入端
    // COMB_W位3:1 MUX。统一DATA_W+2历史宽度可覆盖最宽二阶差分，相比
    // 原20/21/22位分级存储仅增加3个状态位。
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

    // 三级有限差分采用逐级位宽且保持精确；显式保留两种DSP映射，让综合
    // 报告而非推断启发式结果决定5-DSP候选是否进入下一阶段。
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
    // 第三级梳状减法完成后comb_operand自身即保存突发样本，复用该寄存器
    // 可避免再增加一个FULL_W位重复寄存器。
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

    // 两个内部中间积分器使用同步复位，以便Vivado吸收到DSP48E1内部寄存器；
    // 外部可见输出和最终CIC状态仍保留异步复位语义。
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
