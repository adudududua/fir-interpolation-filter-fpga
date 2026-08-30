`timescale 1ns / 1ps

//=============================================================
// 文件名       : cic_compensation_fir_ce.v
// 模块名       : cic_compensation_fir_ce
// 功能简述     : Phase 7 低速 CIC 补偿 FIR。模块在 352.8kHz
//                输入有效节拍更新 15 点历史，并使用一个顺序 MAC
//                在 8 个系统时钟内完成对称 15tap Q12 FIR：
//                  7 组对称预加 + 1 个中心抽头。
//                CIC_ORDER=3/4 时自动选择对应的 Pareto 系数。
//
// 当前默认配置：
//                  输入输出位宽：20bit signed
//                  系数位宽    ：14bit signed，Q12
//                  累加位宽    ：40bit signed
//                  乘法器      ：1 个 DSP48
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-13
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-13：新增 Phase 7 低速补偿 FIR。
//=============================================================

module cic_compensation_fir_ce #(
    parameter integer DATA_W = 20,
    parameter integer COEFF_W = 14,
    parameter integer ACC_W = 40,
    parameter integer FRAC_W = 12,
    parameter integer CIC_ORDER = 3
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,
    output reg  signed [DATA_W-1:0]     y_out,
    output reg                          y_out_valid,
    output wire                         busy_dbg
);

    localparam integer PAIR_W = DATA_W + 1;
    localparam integer PROD_W = PAIR_W + COEFF_W;

    reg signed [DATA_W-1:0] history [0:14];
    reg job_active;
    reg [3:0] mac_index;
    reg signed [ACC_W-1:0] acc_reg;
    reg signed [PAIR_W-1:0] pair_sum_comb;
    reg signed [COEFF_W-1:0] coeff_comb;

    (* use_dsp = "yes" *)
    wire signed [PROD_W-1:0] product_comb;
    wire signed [ACC_W-1:0] product_ext;
    wire signed [ACC_W-1:0] mac_sum_comb;
    wire signed [DATA_W-1:0] rounded_output;

    integer history_idx;

    assign product_comb = pair_sum_comb * coeff_comb;
    assign product_ext = {{(ACC_W-PROD_W){product_comb[PROD_W-1]}},
                          product_comb};
    assign mac_sum_comb = (mac_index == 4'd0) ? product_ext :
                          (acc_reg + product_ext);
    assign busy_dbg = job_active;

    round_sat_shift_compact #(
        .IN_W    (ACC_W),
        .OUT_W   (DATA_W),
        .SHIFT_N (FRAC_W)
    ) u_round_compensation_q12 (
        .din  (mac_sum_comb),
        .dout (rounded_output)
    );

    always @(*) begin
        pair_sum_comb = {PAIR_W{1'b0}};
        coeff_comb = {COEFF_W{1'b0}};

        case (mac_index)
            4'd0: pair_sum_comb =
                $signed({history[0][DATA_W-1], history[0]}) +
                $signed({history[14][DATA_W-1], history[14]});
            4'd1: pair_sum_comb =
                $signed({history[1][DATA_W-1], history[1]}) +
                $signed({history[13][DATA_W-1], history[13]});
            4'd2: pair_sum_comb =
                $signed({history[2][DATA_W-1], history[2]}) +
                $signed({history[12][DATA_W-1], history[12]});
            4'd3: pair_sum_comb =
                $signed({history[3][DATA_W-1], history[3]}) +
                $signed({history[11][DATA_W-1], history[11]});
            4'd4: pair_sum_comb =
                $signed({history[4][DATA_W-1], history[4]}) +
                $signed({history[10][DATA_W-1], history[10]});
            4'd5: pair_sum_comb =
                $signed({history[5][DATA_W-1], history[5]}) +
                $signed({history[9][DATA_W-1], history[9]});
            4'd6: pair_sum_comb =
                $signed({history[6][DATA_W-1], history[6]}) +
                $signed({history[8][DATA_W-1], history[8]});
            4'd7: pair_sum_comb =
                $signed({history[7][DATA_W-1], history[7]});
            default: pair_sum_comb = {PAIR_W{1'b0}};
        endcase

        if (CIC_ORDER == 3) begin
            case (mac_index)
                4'd0: coeff_comb = -14'sd8;
                4'd1: coeff_comb = -14'sd1;
                4'd2: coeff_comb =  14'sd71;
                4'd3: coeff_comb =  14'sd13;
                4'd4: coeff_comb = -14'sd325;
                4'd5: coeff_comb = -14'sd107;
                4'd6: coeff_comb =  14'sd1286;
                4'd7: coeff_comb =  14'sd2238;
                default: coeff_comb = {COEFF_W{1'b0}};
            endcase
        end
        else begin
            case (mac_index)
                4'd0: coeff_comb =  14'sd6;
                4'd1: coeff_comb = -14'sd31;
                4'd2: coeff_comb =  14'sd12;
                4'd3: coeff_comb =  14'sd176;
                4'd4: coeff_comb = -14'sd242;
                4'd5: coeff_comb = -14'sd511;
                4'd6: coeff_comb =  14'sd1248;
                4'd7: coeff_comb =  14'sd2780;
                default: coeff_comb = {COEFF_W{1'b0}};
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (history_idx = 0; history_idx < 15;
                 history_idx = history_idx + 1)
                history[history_idx] <= {DATA_W{1'b0}};
            job_active <= 1'b0;
            mac_index <= 4'd0;
            acc_reg <= {ACC_W{1'b0}};
            y_out <= {DATA_W{1'b0}};
            y_out_valid <= 1'b0;
        end
        else begin
            y_out_valid <= 1'b0;

            if (x_in_valid && !job_active) begin
                for (history_idx = 14; history_idx > 0;
                     history_idx = history_idx - 1)
                    history[history_idx] <= history[history_idx-1];
                history[0] <= x_in;
                job_active <= 1'b1;
                mac_index <= 4'd0;
                acc_reg <= {ACC_W{1'b0}};
            end
            else if (job_active) begin
                if (mac_index == 4'd7) begin
                    y_out <= rounded_output;
                    y_out_valid <= 1'b1;
                    job_active <= 1'b0;
                    mac_index <= 4'd0;
                end
                else begin
                    acc_reg <= mac_sum_comb;
                    mac_index <= mac_index + 1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && x_in_valid && job_active)
            $fatal(1, "CIC compensation FIR input overrun");
        if (rst_n && CIC_ORDER != 3 && CIC_ORDER != 4)
            $fatal(1, "CIC_ORDER must be 3 or 4");
    end
`endif

endmodule
