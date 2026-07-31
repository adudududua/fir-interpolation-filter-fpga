`timescale 1ns / 1ps

//=============================================================
// 文件名       : interp2_halfband7_shiftadd_ce.v
// 模块名       : interp2_halfband7_shiftadd_ce
// 功能简述     : 精确 7 tap 半带核的 2 倍插值 true-polyphase 实现。
//                偶相使用移位加法计算，奇相退化为纯延时路径，
//                不构造显式插零序列，也不实例化通用乘法器。
//
//                半带系数：[-1 0 9 16 9 0 -1] / 16
//                偶相分子：-(x[n]+x[n-3])+9*(x[n-1]+x[n-2])
//                奇相输出：x[n-1]
//
// 当前默认配置：
//                  输入输出位宽：24bit signed
//                  系数格式    ：Q4
//                  实现资源    ：加法器、减法器和移位器
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-11
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-11：新增 canonical halfband7 移位加法实现。
//=============================================================

(* use_dsp = "no" *)
module interp2_halfband7_shiftadd_ce #(
    parameter integer DATA_W = 24,
    parameter integer ASSUME_VALID_PHASE0 = 0,
    parameter integer PROVEN_NO_SATURATION = 0
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ce_out,
    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,
    output reg  signed [DATA_W-1:0]     y_out,
    output reg                          y_out_valid,
    output wire                         phase_dbg
);

    localparam integer PAIR_W = DATA_W + 1;
    localparam integer ACC_W  = DATA_W + 5;

    reg                     phase_cnt;
    reg signed [DATA_W-1:0] x_d1;
    reg signed [DATA_W-1:0] x_d2;
    reg signed [DATA_W-1:0] x_d3;

    wire signed [DATA_W-1:0] x_current;
    wire signed [PAIR_W-1:0] pair_edge;
    wire signed [PAIR_W-1:0] pair_inner;
    wire signed [ACC_W-1:0]  pair_edge_ext;
    wire signed [ACC_W-1:0]  pair_inner_ext;
    wire signed [ACC_W-1:0]  even_acc;
    wire signed [DATA_W-1:0] even_rounded;
    wire signed [ACC_W-1:0] even_biased;
    wire signed [ACC_W-1:0] even_shifted;

    assign x_current = (ASSUME_VALID_PHASE0 != 0) ? x_in :
        (x_in_valid ? x_in : {DATA_W{1'b0}});
    assign pair_edge = $signed({x_current[DATA_W-1], x_current})
                     + $signed({x_d3[DATA_W-1], x_d3});
    assign pair_inner = $signed({x_d1[DATA_W-1], x_d1})
                      + $signed({x_d2[DATA_W-1], x_d2});

    assign pair_edge_ext = {{(ACC_W-PAIR_W){pair_edge[PAIR_W-1]}},
                            pair_edge};
    assign pair_inner_ext = {{(ACC_W-PAIR_W){pair_inner[PAIR_W-1]}},
                             pair_inner};
    assign even_acc = -pair_edge_ext
                    + pair_inner_ext
                    + (pair_inner_ext <<< 3);

    generate
        if (PROVEN_NO_SATURATION != 0) begin : gen_compact_round
            assign even_biased = even_acc+{{(ACC_W-3){1'b0}}, 3'd7}+
                {{(ACC_W-1){1'b0}}, ~even_acc[ACC_W-1]};
            assign even_shifted = even_biased >>> 4;
            assign even_rounded = even_shifted[DATA_W-1:0];
        end
        else begin : gen_saturating_round
            assign even_biased = {ACC_W{1'b0}};
            assign even_shifted = {ACC_W{1'b0}};
            round_sat_shift_compact #(
                .IN_W   (ACC_W),
                .OUT_W  (DATA_W),
                .SHIFT_N(4)
            ) u_round_sat_q4_to_data (
                .din  (even_acc),
                .dout (even_rounded)
            );
        end
    endgenerate

    assign phase_dbg = phase_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_cnt  <= 1'b1;
            x_d1       <= {DATA_W{1'b0}};
            x_d2       <= {DATA_W{1'b0}};
            x_d3       <= {DATA_W{1'b0}};
            y_out      <= {DATA_W{1'b0}};
            y_out_valid <= 1'b0;
        end
        else begin
            y_out_valid <= 1'b0;

            if (ce_out) begin
                y_out_valid <= 1'b1;

                if (phase_cnt == 1'b0) begin
                    y_out <= even_rounded;
                    x_d3  <= x_d2;
                    x_d2  <= x_d1;
                    x_d1  <= x_current;
                end
                else begin
                    y_out <= x_d2;
                end

                phase_cnt <= ~phase_cnt;
            end
        end
    end

`ifndef SYNTHESIS
    reg input_seen;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            input_seen <= 1'b0;
        end
        else if (ce_out && (phase_cnt == 1'b0)) begin
            if (x_in_valid)
                input_seen <= 1'b1;
            else if (input_seen)
                $display("WARNING: canonical halfband7 phase-0 input missing at %0t", $time);
        end
    end
`endif

endmodule
