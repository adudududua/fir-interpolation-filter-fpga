`timescale 1ns / 1ps

//=============================================================
// 文件名       : cic_interp16_core_ce.v
// 模块名       : cic_interp16_core_ce
// 功能简述     : 标准 16 倍 CIC 插值核心。低速补偿数据先通过
//                N 级 comb，再在 ce_out 节拍输出一个 comb 样点
//                和 15 个零，最后进入 N 级高速 integrator。
//                所有级采用二进制补码模运算；最后一级按 MATLAB
//                Pareto profile 丢弃 LSB，并完成 CIC 增益归一化。
//
// 当前默认配置：
//                  R=16，M=1，N=3/4
//                  N=3：内部 32bit，最后一级丢弃 3 LSB
//                  N=4：内部 36bit，最后一级丢弃 6 LSB
//                  输出：20bit signed
//                  折叠顶层会按最终搜索结果覆盖剪枝参数：
//                  N=3 丢弃 0 LSB，N=4 丢弃 7 LSB
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-13
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-13：新增标准 CIC 插值 RTL 核心。
//=============================================================

module cic_interp16_core_ce #(
    parameter integer DATA_W = 20,
    parameter integer CIC_ORDER = 3,
    parameter integer FINAL_PRUNE_LSB = 3
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ce_out,
    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,
    output reg  signed [DATA_W-1:0]     y_out,
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

    wire signed [FULL_W-1:0] x_extended;
    wire output_event;
    wire first_output_event;
    wire signed [FULL_W-1:0] high_rate_input;
    wire signed [FINAL_W-1:0] final_input_rounded;
    wire signed [FINAL_W-1:0] final_integrator_next;
    wire signed [DATA_W-1:0] normalized_output;

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
        .OUT_W   (DATA_W),
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
            y_out <= {DATA_W{1'b0}};
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
                    burst_remaining <= burst_remaining - 1'b1;
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
    end
`endif

endmodule
