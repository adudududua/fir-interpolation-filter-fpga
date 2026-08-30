`timescale 1ns / 1ps

`include "all2x_v2_coeff_pkg.vh"

//=============================================================
// 文件名       : interp2_stage23_polyphase_ce.v
// 模块名       : interp2_stage23_polyphase_ce
// 功能简述     : Stage 2/3 共用的 2 倍 true-polyphase FIR 核。
//                本模块不生成显式插零序列，只保存真实输入历史，
//                并分别利用偶相、奇相子滤波器的对称性完成乘加。
//
//                STAGE_ID=2：phase0 9 tap，phase1 8 tap，Q15
//                STAGE_ID=3：phase0 6 tap，phase1 5 tap，Q14
//
// 当前默认配置：
//                  输入输出位宽：24bit signed
//                  系数来源    ：all2x_v2_coeff_pkg.vh
//                  运行方式    ：固定 CE，两相交替输出
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-11
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-11：新增 Stage 2/3 true-polyphase FIR 核。
//=============================================================

(* use_dsp = "no" *)
//=============================================================
// 1）模块名称：interp2_stage23_polyphase_ce
// 功能说明：第二、三级 2 倍插值滤波器：复用或折叠运算资源完成连续插值。
// 工程版本：Vivado 2025.2。
//=============================================================
module interp2_stage23_polyphase_ce #(
    parameter integer STAGE_ID = 3,
    parameter integer DATA_W   = 24,
    parameter integer COEFF_W  = 15,
    parameter integer ACC_W    = 40,
    parameter integer FRAC_W   = 14
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

    localparam integer PHASE0_LEN = (STAGE_ID == 2) ? 9 : 6;
    localparam integer PHASE1_LEN = (STAGE_ID == 2) ? 8 : 5;
    localparam integer HIST_LEN   = (STAGE_ID == 2) ? 8 : 5;
    localparam integer P0_PAIRS   = PHASE0_LEN / 2;
    localparam integer P1_PAIRS   = PHASE1_LEN / 2;

    reg                     phase_cnt;
    reg signed [DATA_W-1:0] x_hist [0:HIST_LEN-1];
    reg signed [ACC_W-1:0]  acc_shared_comb;

    wire signed [DATA_W-1:0] x_current;
    wire signed [DATA_W-1:0] y_shared_rounded;

    integer i;
    integer k;

    assign x_current = x_in_valid ? x_in : {DATA_W{1'b0}};
    assign phase_dbg = phase_cnt;

    function signed [COEFF_W-1:0] phase0_coeff;
        input integer index;
        begin
            phase0_coeff = {COEFF_W{1'b0}};
            if (STAGE_ID == 2) begin
                case (index)
                    0: phase0_coeff = `V2_S2_P0_C0;
                    1: phase0_coeff = `V2_S2_P0_C1;
                    2: phase0_coeff = `V2_S2_P0_C2;
                    3: phase0_coeff = `V2_S2_P0_C3;
                    4: phase0_coeff = `V2_S2_P0_C4;
                    default: phase0_coeff = {COEFF_W{1'b0}};
                endcase
            end
            else begin
                case (index)
                    0: phase0_coeff = `V2_S3_P0_C0;
                    1: phase0_coeff = `V2_S3_P0_C1;
                    2: phase0_coeff = `V2_S3_P0_C2;
                    default: phase0_coeff = {COEFF_W{1'b0}};
                endcase
            end
        end
    endfunction

    function signed [COEFF_W-1:0] phase1_coeff;
        input integer index;
        begin
            phase1_coeff = {COEFF_W{1'b0}};
            if (STAGE_ID == 2) begin
                case (index)
                    0: phase1_coeff = `V2_S2_P1_C0;
                    1: phase1_coeff = `V2_S2_P1_C1;
                    2: phase1_coeff = `V2_S2_P1_C2;
                    3: phase1_coeff = `V2_S2_P1_C3;
                    default: phase1_coeff = {COEFF_W{1'b0}};
                endcase
            end
            else begin
                case (index)
                    0: phase1_coeff = `V2_S3_P1_C0;
                    1: phase1_coeff = `V2_S3_P1_C1;
                    2: phase1_coeff = `V2_S3_P1_C2;
                    default: phase1_coeff = {COEFF_W{1'b0}};
                endcase
            end
        end
    endfunction

    always @(*) begin
        acc_shared_comb = {ACC_W{1'b0}};

        if (phase_cnt == 1'b0) begin
            for (k = 0; k < P0_PAIRS; k = k + 1) begin
                if (k == 0) begin
                    acc_shared_comb = acc_shared_comb
                        + ($signed({x_current[DATA_W-1], x_current})
                        +  $signed({x_hist[PHASE0_LEN-2][DATA_W-1],
                                    x_hist[PHASE0_LEN-2]}))
                        * $signed(phase0_coeff(k));
                end
                else begin
                    acc_shared_comb = acc_shared_comb
                        + ($signed({x_hist[k-1][DATA_W-1], x_hist[k-1]})
                        +  $signed({x_hist[PHASE0_LEN-2-k][DATA_W-1],
                                    x_hist[PHASE0_LEN-2-k]}))
                        * $signed(phase0_coeff(k));
                end
            end

            if ((PHASE0_LEN % 2) != 0) begin
                acc_shared_comb = acc_shared_comb
                    + $signed(x_hist[P0_PAIRS-1])
                    * $signed(phase0_coeff(P0_PAIRS));
            end
        end
        else begin
            for (k = 0; k < P1_PAIRS; k = k + 1) begin
                acc_shared_comb = acc_shared_comb
                    + ($signed({x_hist[k][DATA_W-1], x_hist[k]})
                    +  $signed({x_hist[PHASE1_LEN-1-k][DATA_W-1],
                                x_hist[PHASE1_LEN-1-k]}))
                    * $signed(phase1_coeff(k));
            end

            if ((PHASE1_LEN % 2) != 0) begin
                acc_shared_comb = acc_shared_comb
                    + $signed(x_hist[P1_PAIRS])
                    * $signed(phase1_coeff(P1_PAIRS));
            end
        end
    end

    // 例化说明：调用 round_sat_q16_to24 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    round_sat_q16_to24 #(
        .IN_W   (ACC_W),
        .OUT_W  (DATA_W),
        .FRAC_W (FRAC_W)
    ) u_round_shared (
        .din_full (acc_shared_comb),
        .dout_24  (y_shared_rounded)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_cnt   <= 1'b1;
            y_out       <= {DATA_W{1'b0}};
            y_out_valid <= 1'b0;
            for (i = 0; i < HIST_LEN; i = i + 1)
                x_hist[i] <= {DATA_W{1'b0}};
        end
        else begin
            y_out_valid <= 1'b0;

            if (ce_out) begin
                y_out_valid <= 1'b1;
                y_out       <= y_shared_rounded;

                if (phase_cnt == 1'b0) begin
                    for (i = HIST_LEN-1; i > 0; i = i - 1)
                        x_hist[i] <= x_hist[i-1];
                    x_hist[0] <= x_current;
                end

                phase_cnt <= ~phase_cnt;
            end
        end
    end

`ifndef SYNTHESIS
    reg input_seen;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            input_seen <= 1'b0;
        else if (ce_out && (phase_cnt == 1'b0)) begin
            if (x_in_valid)
                input_seen <= 1'b1;
            else if (input_seen)
                $display("WARNING: Stage %0d polyphase input missing at %0t",
                         STAGE_ID, $time);
        end
    end
`endif

endmodule
