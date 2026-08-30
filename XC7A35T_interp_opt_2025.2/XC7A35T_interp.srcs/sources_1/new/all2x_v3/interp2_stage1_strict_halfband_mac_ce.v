`timescale 1ns / 1ps

`include "all2x_v3_stage1_coeff_pkg.vh"

//=============================================================
// 文件名       : interp2_stage1_strict_halfband_mac_ce.v
// 模块名       : interp2_stage1_strict_halfband_mac_ce
// 功能简述     : Stage 1 严格半带 true-polyphase 单 DSP MAC。
//                模块直接处理真实 44.1kHz 输入样点，不再显式插零。
//                纯延迟相直接输出 26 个输入样点前的数据；滤波相
//                使用 52 tap 对称 FIR，以 26 个时钟周期完成 MAC。
//
//                两相数学关系：
//                  y[2m]   = x[m-26]
//                  y[2m+1] = sum(c[r] *
//                               (x[m-r] + x[m-(51-r)]))
//
// 当前默认配置：
//                  FIR 长度      ：105 tap
//                  滤波相长度    ：52 tap
//                  对称 MAC 对数 ：26
//                  系数格式      ：17bit signed Q15
//                  累加器位宽    ：42bit signed
//                  历史实现      ：52x24bit FF
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-11
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-11：新增 Stage 1 strict-halfband FF 版本。
//=============================================================
//=============================================================
// 1）模块名称：interp2_stage1_strict_halfband_mac_ce
// 功能说明：第一级 2 倍插值滤波器：处理最长抽头滤波并完成定点量化。
// 工程版本：Vivado 2025.2。
//=============================================================

module interp2_stage1_strict_halfband_mac_ce #(
    parameter integer DATA_W      = 24,
    parameter integer COEFF_W     = `V3_S1_COEFF_W,
    parameter integer ACC_W       = `V3_S1_ACC_W,
    parameter integer FRAC_W      = `V3_S1_FRAC_W,
    parameter integer HISTORY_LEN = `V3_S1_HISTORY_LEN,
    parameter integer PAIR_COUNT  = `V3_S1_PAIR_COUNT,
    parameter integer DELAY_INDEX = `V3_S1_DELAY_INDEX
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ce_out,

    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,

    output reg  signed [DATA_W-1:0]     y_out,
    output reg                          y_out_valid,

    output reg                          phase_dbg,
    output wire signed [DATA_W-1:0]     fir_in_dbg,
    output wire                         fir_in_valid_dbg
);

    localparam integer PAIR_W = DATA_W + 1;
    localparam integer PROD_W = PAIR_W + COEFF_W;

    reg signed [DATA_W-1:0] history [0:HISTORY_LEN-1];
    reg                      phase_cnt;
    reg                      busy;
    reg                      filter_ready;
    reg [4:0]                mac_idx;
    reg signed [ACC_W-1:0]   acc_reg;
    reg signed [ACC_W-1:0]   filter_result;

    wire signed [DATA_W-1:0] x_current;
    reg  signed [PAIR_W-1:0] pair_sum_comb;
    reg  signed [COEFF_W-1:0] coeff_comb;

    (* use_dsp = "yes" *)
    wire signed [PROD_W-1:0] product_comb;
    wire signed [ACC_W-1:0]  product_ext;
    wire signed [DATA_W-1:0] filter_rounded;

    integer history_idx;

    assign x_current = x_in_valid ? x_in : {DATA_W{1'b0}};
    assign product_comb = pair_sum_comb * coeff_comb;
    assign product_ext = {{(ACC_W-PROD_W){product_comb[PROD_W-1]}},
                          product_comb};

    assign fir_in_dbg = x_current;
    assign fir_in_valid_dbg = ce_out && (phase_cnt == 1'b0);

    always @(*) begin
        pair_sum_comb =
            $signed({history[mac_idx][DATA_W-1], history[mac_idx]}) +
            $signed({history[HISTORY_LEN-1-mac_idx][DATA_W-1],
                     history[HISTORY_LEN-1-mac_idx]});

        case (mac_idx)
            5'd0:  coeff_comb = `V3_S1_C00;
            5'd1:  coeff_comb = `V3_S1_C01;
            5'd2:  coeff_comb = `V3_S1_C02;
            5'd3:  coeff_comb = `V3_S1_C03;
            5'd4:  coeff_comb = `V3_S1_C04;
            5'd5:  coeff_comb = `V3_S1_C05;
            5'd6:  coeff_comb = `V3_S1_C06;
            5'd7:  coeff_comb = `V3_S1_C07;
            5'd8:  coeff_comb = `V3_S1_C08;
            5'd9:  coeff_comb = `V3_S1_C09;
            5'd10: coeff_comb = `V3_S1_C10;
            5'd11: coeff_comb = `V3_S1_C11;
            5'd12: coeff_comb = `V3_S1_C12;
            5'd13: coeff_comb = `V3_S1_C13;
            5'd14: coeff_comb = `V3_S1_C14;
            5'd15: coeff_comb = `V3_S1_C15;
            5'd16: coeff_comb = `V3_S1_C16;
            5'd17: coeff_comb = `V3_S1_C17;
            5'd18: coeff_comb = `V3_S1_C18;
            5'd19: coeff_comb = `V3_S1_C19;
            5'd20: coeff_comb = `V3_S1_C20;
            5'd21: coeff_comb = `V3_S1_C21;
            5'd22: coeff_comb = `V3_S1_C22;
            5'd23: coeff_comb = `V3_S1_C23;
            5'd24: coeff_comb = `V3_S1_C24;
            5'd25: coeff_comb = `V3_S1_C25;
            default: coeff_comb = {COEFF_W{1'b0}};
        endcase
    end

    // 例化说明：调用 round_sat_q16_to24 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    round_sat_q16_to24 #(
        .IN_W   (ACC_W),
        .OUT_W  (DATA_W),
        .FRAC_W (FRAC_W)
    ) u_round_sat_q15_to_data (
        .din_full (filter_result),
        .dout_24  (filter_rounded)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            for (history_idx = 0; history_idx < HISTORY_LEN;
                 history_idx = history_idx + 1)
                history[history_idx] <= {DATA_W{1'b0}};

            phase_cnt    <= 1'b1;
            phase_dbg    <= 1'b1;
            busy         <= 1'b0;
            filter_ready <= 1'b0;
            mac_idx      <= 5'd0;
            acc_reg      <= {ACC_W{1'b0}};
            filter_result <= {ACC_W{1'b0}};
            y_out        <= {DATA_W{1'b0}};
            y_out_valid  <= 1'b0;
        end
        else begin
            y_out_valid <= 1'b0;

            if (busy) begin
                if (mac_idx == PAIR_COUNT-1) begin
                    filter_result <= acc_reg + product_ext;
                    filter_ready  <= 1'b1;
                    busy          <= 1'b0;
                end
                else begin
                    acc_reg <= acc_reg + product_ext;
                    mac_idx <= mac_idx + 5'd1;
                end
            end

            if (ce_out) begin
                phase_dbg <= phase_cnt;
                y_out_valid <= 1'b1;

                if (phase_cnt == 1'b0) begin
                    y_out <= history[DELAY_INDEX];

                    history[0] <= x_current;
                    for (history_idx = 1; history_idx < HISTORY_LEN;
                         history_idx = history_idx + 1)
                        history[history_idx] <= history[history_idx-1];

                    acc_reg      <= {ACC_W{1'b0}};
                    mac_idx      <= 5'd0;
                    busy         <= 1'b1;
                    filter_ready <= 1'b0;
                end
                else begin
                    y_out <= filter_ready ? filter_rounded :
                             {DATA_W{1'b0}};
                    filter_ready <= 1'b0;
                end

                phase_cnt <= ~phase_cnt;
            end
        end
    end

`ifndef SYNTHESIS
    reg input_seen;

    always @(posedge clk) begin
        if (!rst_n) begin
            input_seen <= 1'b0;
        end
        else if (ce_out && phase_cnt == 1'b0) begin
            input_seen <= 1'b1;
            if (busy)
                $fatal(1, "Stage 1 strict-halfband MAC deadline miss");
        end
        else if (ce_out && phase_cnt == 1'b1 && input_seen &&
                 !filter_ready) begin
            $fatal(1, "Stage 1 strict-halfband result not ready");
        end
    end
`endif

endmodule
