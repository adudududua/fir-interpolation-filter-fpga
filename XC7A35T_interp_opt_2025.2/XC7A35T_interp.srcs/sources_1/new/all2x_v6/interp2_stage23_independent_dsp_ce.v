`timescale 1ns / 1ps

`include "all2x_v2_coeff_pkg.vh"

//=============================================================
// 文件名       : interp2_stage23_independent_dsp_ce.v
// 模块名       : interp2_stage23_independent_dsp_ce
// 功能简述     : Stage 2 或 Stage 3 独占一个 DSP 的串行
//                true-polyphase FIR 核。每个实例独立保存输入历史、
//                相位和 MAC 状态，不再使用跨级 pending、优先级
//                调度、stage mux 和 deadline 计数器。
//
//                STAGE_ID=2：phase0=5 MAC，phase1=4 MAC，Q15
//                STAGE_ID=3：phase0=3 MAC，phase1=3 MAC，Q15
//
// 当前默认配置：
//                  输入输出位宽：24bit signed
//                  系数位宽    ：16bit signed Q15
//                  累加位宽    ：40bit signed
//                  每实例 DSP  ：1
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-13
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-13：新增 Phase 6 三 DSP Pareto 独立 MAC 核。
//=============================================================
//=============================================================
// 1）模块名称：interp2_stage23_independent_dsp_ce
// 功能说明：第二、三级 2 倍插值滤波器：复用或折叠运算资源完成连续插值。
// 工程版本：Vivado 2025.2。
//=============================================================

module interp2_stage23_independent_dsp_ce #(
    parameter integer STAGE_ID = 2,
    parameter integer DATA_W = 24,
    parameter integer COEFF_W = 16,
    parameter integer ACC_W = 40
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ce_out,
    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,
    output reg  signed [DATA_W-1:0]     y_out,
    output reg                          y_out_valid,
    output wire                         phase_dbg,
    output wire                         mac_busy_dbg,
    output wire [2:0]                   mac_index_dbg
);

    localparam integer PAIR_W = DATA_W + 1;
    localparam integer PROD_W = PAIR_W + COEFF_W;
    localparam integer HIST_LEN = (STAGE_ID == 2) ? 9 : 6;

    reg signed [DATA_W-1:0] history [0:HIST_LEN-1];
    reg phase;
    reg mac_active;
    reg job_phase;
    reg [2:0] mac_index;
    reg [2:0] mac_count;
    reg signed [ACC_W-1:0] acc_reg;
    reg signed [PAIR_W-1:0] pair_sum_comb;
    reg signed [COEFF_W-1:0] coeff_comb;

    (* use_dsp = "yes" *)
    wire signed [PROD_W-1:0] product_comb;
    wire signed [ACC_W-1:0] product_ext;
    wire signed [ACC_W-1:0] mac_sum_comb;
    wire signed [DATA_W-1:0] rounded_q15;
    wire signed [DATA_W-1:0] x_current;

    integer i;

    assign x_current = x_in_valid ? x_in : {DATA_W{1'b0}};
    assign product_comb = pair_sum_comb * coeff_comb;

    generate
        if (ACC_W >= PROD_W) begin : gen_product_sign_extend
            assign product_ext =
                {{(ACC_W-PROD_W){product_comb[PROD_W-1]}}, product_comb};
        end
        else begin : gen_product_narrow
            assign product_ext = product_comb[ACC_W-1:0];
        end
    endgenerate

    assign mac_sum_comb = (mac_index == 3'd0) ? product_ext :
                          (acc_reg + product_ext);
    assign phase_dbg = phase;
    assign mac_busy_dbg = mac_active;
    assign mac_index_dbg = mac_index;

    // 例化说明：调用 round_sat_q15_compact_to24 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    round_sat_q15_compact_to24 #(
        .IN_W  (ACC_W),
        .OUT_W (DATA_W)
    ) u_round_q15_compact (
        .din_full (mac_sum_comb),
        .dout_24  (rounded_q15)
    );

    always @(*) begin
        pair_sum_comb = {PAIR_W{1'b0}};
        coeff_comb = {COEFF_W{1'b0}};

        if (STAGE_ID == 2) begin
            if (job_phase == 1'b0) begin
                case (mac_index)
                    3'd0: begin
                        pair_sum_comb =
                            $signed({history[0][DATA_W-1], history[0]}) +
                            $signed({history[8][DATA_W-1], history[8]});
                        coeff_comb = `V2_S2_P0_C0;
                    end
                    3'd1: begin
                        pair_sum_comb =
                            $signed({history[1][DATA_W-1], history[1]}) +
                            $signed({history[7][DATA_W-1], history[7]});
                        coeff_comb = `V2_S2_P0_C1;
                    end
                    3'd2: begin
                        pair_sum_comb =
                            $signed({history[2][DATA_W-1], history[2]}) +
                            $signed({history[6][DATA_W-1], history[6]});
                        coeff_comb = `V2_S2_P0_C2;
                    end
                    3'd3: begin
                        pair_sum_comb =
                            $signed({history[3][DATA_W-1], history[3]}) +
                            $signed({history[5][DATA_W-1], history[5]});
                        coeff_comb = `V2_S2_P0_C3;
                    end
                    3'd4: begin
                        pair_sum_comb =
                            $signed({history[4][DATA_W-1], history[4]});
                        coeff_comb = `V2_S2_P0_C4;
                    end
                    default: begin
                        pair_sum_comb = {PAIR_W{1'b0}};
                        coeff_comb = {COEFF_W{1'b0}};
                    end
                endcase
            end
            else begin
                case (mac_index)
                    3'd0: begin
                        pair_sum_comb =
                            $signed({history[0][DATA_W-1], history[0]}) +
                            $signed({history[7][DATA_W-1], history[7]});
                        coeff_comb = `V2_S2_P1_C0;
                    end
                    3'd1: begin
                        pair_sum_comb =
                            $signed({history[1][DATA_W-1], history[1]}) +
                            $signed({history[6][DATA_W-1], history[6]});
                        coeff_comb = `V2_S2_P1_C1;
                    end
                    3'd2: begin
                        pair_sum_comb =
                            $signed({history[2][DATA_W-1], history[2]}) +
                            $signed({history[5][DATA_W-1], history[5]});
                        coeff_comb = `V2_S2_P1_C2;
                    end
                    3'd3: begin
                        pair_sum_comb =
                            $signed({history[3][DATA_W-1], history[3]}) +
                            $signed({history[4][DATA_W-1], history[4]});
                        coeff_comb = `V2_S2_P1_C3;
                    end
                    default: begin
                        pair_sum_comb = {PAIR_W{1'b0}};
                        coeff_comb = {COEFF_W{1'b0}};
                    end
                endcase
            end
        end
        else begin
            if (job_phase == 1'b0) begin
                case (mac_index)
                    3'd0: begin
                        pair_sum_comb =
                            $signed({history[0][DATA_W-1], history[0]}) +
                            $signed({history[5][DATA_W-1], history[5]});
                        coeff_comb = 16'sd404;
                    end
                    3'd1: begin
                        pair_sum_comb =
                            $signed({history[1][DATA_W-1], history[1]}) +
                            $signed({history[4][DATA_W-1], history[4]});
                        coeff_comb = -16'sd3272;
                    end
                    3'd2: begin
                        pair_sum_comb =
                            $signed({history[2][DATA_W-1], history[2]}) +
                            $signed({history[3][DATA_W-1], history[3]});
                        coeff_comb = 16'sd19250;
                    end
                    default: begin
                        pair_sum_comb = {PAIR_W{1'b0}};
                        coeff_comb = {COEFF_W{1'b0}};
                    end
                endcase
            end
            else begin
                case (mac_index)
                    3'd0: begin
                        pair_sum_comb =
                            $signed({history[0][DATA_W-1], history[0]}) +
                            $signed({history[4][DATA_W-1], history[4]});
                        coeff_comb = -16'sd148;
                    end
                    3'd1: begin
                        pair_sum_comb =
                            $signed({history[1][DATA_W-1], history[1]}) +
                            $signed({history[3][DATA_W-1], history[3]});
                        coeff_comb = 16'sd522;
                    end
                    3'd2: begin
                        pair_sum_comb =
                            $signed({history[2][DATA_W-1], history[2]});
                        coeff_comb = 16'sd32016;
                    end
                    default: begin
                        pair_sum_comb = {PAIR_W{1'b0}};
                        coeff_comb = {COEFF_W{1'b0}};
                    end
                endcase
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= 1'b1;
            mac_active <= 1'b0;
            job_phase <= 1'b0;
            mac_index <= 3'd0;
            mac_count <= 3'd0;
            acc_reg <= {ACC_W{1'b0}};
            y_out <= {DATA_W{1'b0}};
            y_out_valid <= 1'b0;
            for (i = 0; i < HIST_LEN; i = i + 1)
                history[i] <= {DATA_W{1'b0}};
        end
        else begin
            y_out_valid <= 1'b0;

            if (ce_out) begin
                if (phase == 1'b0) begin
                    for (i = HIST_LEN-1; i > 0; i = i - 1)
                        history[i] <= history[i-1];
                    history[0] <= x_current;
                end

                phase <= ~phase;
                mac_active <= 1'b1;
                job_phase <= phase;
                mac_index <= 3'd0;
                if (STAGE_ID == 2)
                    mac_count <= phase ? 3'd4 : 3'd5;
                else
                    mac_count <= 3'd3;
                acc_reg <= {ACC_W{1'b0}};
            end
            else if (mac_active) begin
                if (mac_index == mac_count - 3'd1) begin
                    y_out <= rounded_q15;
                    y_out_valid <= 1'b1;
                    mac_active <= 1'b0;
                    mac_index <= 3'd0;
                    acc_reg <= {ACC_W{1'b0}};
                end
                else begin
                    acc_reg <= mac_sum_comb;
                    mac_index <= mac_index + 3'd1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (STAGE_ID != 2 && STAGE_ID != 3)
            $fatal(1, "Independent DSP STAGE_ID must be 2 or 3");
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (ce_out && mac_active)
                $fatal(1, "Stage %0d independent DSP deadline miss", STAGE_ID);

            if (ACC_W < PROD_W &&
                product_comb[PROD_W-1:ACC_W] !=
                {(PROD_W-ACC_W){product_comb[ACC_W-1]}})
                $fatal(1, "Stage %0d product exceeds ACC_W=%0d",
                       STAGE_ID, ACC_W);
        end
    end
`endif

endmodule

