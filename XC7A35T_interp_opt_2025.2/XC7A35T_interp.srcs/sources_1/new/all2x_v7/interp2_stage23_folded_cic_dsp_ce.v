`timescale 1ns / 1ps

//=============================================================
// 文件名       : interp2_stage23_folded_cic_dsp_ce.v
// 模块名       : interp2_stage23_folded_cic_dsp_ce
// 功能简述     : Stage 2/3 共用一个 DSP 的 true-polyphase FIR。
//                两级分别保存真实输入历史，在各自 CE 到达时生成
//                MAC job；调度器采用 Stage 3 优先策略，共享一个
//                25x16 signed 乘法器和 38bit 累加器。
//
//                Stage 2：phase0=5 MAC，phase1=4 MAC，Q15
//                Stage 3：phase0=3 MAC，phase1=3 MAC，使用 Q15
//                折叠补偿系数，同时完成 2x 插值与 CIC 通带补偿。
//                中心系数拆为 16bit 负系数与 2^16 直通项，直通项
//                预装进现有累加器，因此不增加 MAC 数或额外加法器。
//
// 当前默认配置：
//                  输入输出位宽：24bit signed
//                  共享 DSP 数 ：1
//                  调度优先级  ：Stage 3 > Stage 2
//                  CIC 候选    ：N=3 / N=4
//                  Stage 3 系数：MATLAB Phase 7 folded Q15/17bit
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-12
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-12：新增 Stage 2/3 共享 DSP 实验模块。
//                2026-07-12：Stage 3 系数乘 2 改为 Q15，
//                            Stage 2/3 共用一个舍入饱和单元。
//                2026-07-12：共享舍入器改为余数进位与高位一致性
//                            饱和结构，消除 42bit 舍入偏置加法器。
//                2026-07-13：增加 Stage 2/3 独立数据位宽参数；
//                            等位宽时仍只生成一个共享舍入器。
//                2026-07-13：Stage 3 替换为 FIR-CIC 折叠补偿系数，
//                            保持 11tap 与 3+3 MAC 调度不变。
//                2026-07-13：拆分超过 signed 16bit 的中心系数，
//                            乘法器恢复为 25x16 signed。
//=============================================================

`include "all2x_v2_coeff_pkg.vh"

module interp2_stage23_folded_cic_dsp_ce #(
    parameter integer DATA_W = 24,
    parameter integer STAGE2_DATA_W = DATA_W,
    parameter integer STAGE3_DATA_W = DATA_W,
    parameter integer COEFF_W = 16,
    parameter integer ACC_W = 38,
    parameter integer CIC_ORDER = 3
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         stage2_ce_out,
    input  wire signed [STAGE2_DATA_W-1:0] stage2_x_in,
    input  wire                         stage2_x_in_valid,
    output reg  signed [STAGE2_DATA_W-1:0] stage2_y_out,
    output reg                          stage2_y_out_valid,

    input  wire                         stage3_ce_out,
    input  wire signed [STAGE3_DATA_W-1:0] stage3_x_in,
    input  wire                         stage3_x_in_valid,
    output reg  signed [STAGE3_DATA_W-1:0] stage3_y_out,
    output reg                          stage3_y_out_valid,

    output wire                         stage2_phase_dbg,
    output wire                         stage3_phase_dbg,
    output wire                         scheduler_busy_dbg,
    output wire [1:0]                   scheduler_stage_dbg,
    output wire [3:0]                   scheduler_mac_index_dbg
);

    localparam integer PAIR_W = STAGE2_DATA_W + 1;
    localparam integer PROD_W = PAIR_W + COEFF_W;

    reg signed [STAGE2_DATA_W-1:0] stage2_hist [0:8];
    reg signed [STAGE3_DATA_W-1:0] stage3_hist [0:5];

    reg stage2_phase;
    reg stage3_phase;

    reg stage2_pending;
    reg stage3_pending;
    reg stage2_pending_phase;
    reg stage3_pending_phase;
    reg [31:0] stage2_pending_deadline;
    reg [31:0] stage3_pending_deadline;

    reg job_active;
    reg [1:0] job_stage;
    reg job_phase;
    reg [3:0] job_mac_index;
    reg [3:0] job_mac_count;
    reg [31:0] job_deadline;
    reg [31:0] cycle_count;

    reg signed [ACC_W-1:0] acc_reg;
    reg signed [PAIR_W-1:0] pair_sum_comb;
    reg signed [COEFF_W-1:0] coeff_comb;

    (* use_dsp = "yes" *)
    wire signed [PROD_W-1:0] product_comb;
    wire signed [ACC_W-1:0] product_ext;
    wire signed [ACC_W-1:0] mac_sum_comb;
    wire signed [ACC_W-1:0] stage3_center_extended;
    wire signed [ACC_W-1:0] stage3_center_direct;
    wire use_preloaded_acc;
    wire signed [STAGE2_DATA_W-1:0] stage2_q15_rounded;
    wire signed [STAGE3_DATA_W-1:0] stage3_q15_rounded;

    wire signed [STAGE2_DATA_W-1:0] stage2_x_current;
    wire signed [STAGE3_DATA_W-1:0] stage3_x_current;

    integer i;

    assign stage2_x_current = stage2_x_in_valid ? stage2_x_in :
                              {STAGE2_DATA_W{1'b0}};
    assign stage3_x_current = stage3_x_in_valid ? stage3_x_in :
                              {STAGE3_DATA_W{1'b0}};

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
    assign stage3_center_extended =
        {{(ACC_W-STAGE3_DATA_W){stage3_hist[2][STAGE3_DATA_W-1]}},
         stage3_hist[2]};
    assign stage3_center_direct = stage3_center_extended <<< 16;
    assign use_preloaded_acc = (job_stage == 2'd3) && job_phase;
    assign mac_sum_comb = (job_mac_index == 4'd0 && !use_preloaded_acc) ?
                          product_ext : (acc_reg + product_ext);

    assign stage2_phase_dbg = stage2_phase;
    assign stage3_phase_dbg = stage3_phase;
    assign scheduler_busy_dbg = job_active;
    assign scheduler_stage_dbg = job_stage;
    assign scheduler_mac_index_dbg = job_mac_index;

    generate
        if (STAGE2_DATA_W == STAGE3_DATA_W) begin : gen_shared_rounder
            round_sat_q15_compact_to24 #(
                .IN_W  (ACC_W),
                .OUT_W (STAGE2_DATA_W)
            ) u_round_shared_q15_compact (
                .din_full (mac_sum_comb),
                .dout_24  (stage2_q15_rounded)
            );
            assign stage3_q15_rounded = stage2_q15_rounded;
        end
        else begin : gen_separate_rounders
            round_sat_q15_compact_to24 #(
                .IN_W  (ACC_W),
                .OUT_W (STAGE2_DATA_W)
            ) u_round_stage2_q15_compact (
                .din_full (mac_sum_comb),
                .dout_24  (stage2_q15_rounded)
            );
            round_sat_q15_compact_to24 #(
                .IN_W  (ACC_W),
                .OUT_W (STAGE3_DATA_W)
            ) u_round_stage3_q15_compact (
                .din_full (mac_sum_comb),
                .dout_24  (stage3_q15_rounded)
            );
        end
    endgenerate

    always @(*) begin
        pair_sum_comb = {PAIR_W{1'b0}};
        coeff_comb = {COEFF_W{1'b0}};

        if (job_stage == 2'd2) begin
            if (job_phase == 1'b0) begin
                case (job_mac_index)
                    4'd0: begin
                        pair_sum_comb =
                            $signed({stage2_hist[0][STAGE2_DATA_W-1],
                                     stage2_hist[0]}) +
                            $signed({stage2_hist[8][STAGE2_DATA_W-1],
                                     stage2_hist[8]});
                        coeff_comb = `V2_S2_P0_C0;
                    end
                    4'd1: begin
                        pair_sum_comb =
                            $signed({stage2_hist[1][STAGE2_DATA_W-1],
                                     stage2_hist[1]}) +
                            $signed({stage2_hist[7][STAGE2_DATA_W-1],
                                     stage2_hist[7]});
                        coeff_comb = `V2_S2_P0_C1;
                    end
                    4'd2: begin
                        pair_sum_comb =
                            $signed({stage2_hist[2][STAGE2_DATA_W-1],
                                     stage2_hist[2]}) +
                            $signed({stage2_hist[6][STAGE2_DATA_W-1],
                                     stage2_hist[6]});
                        coeff_comb = `V2_S2_P0_C2;
                    end
                    4'd3: begin
                        pair_sum_comb =
                            $signed({stage2_hist[3][STAGE2_DATA_W-1],
                                     stage2_hist[3]}) +
                            $signed({stage2_hist[5][STAGE2_DATA_W-1],
                                     stage2_hist[5]});
                        coeff_comb = `V2_S2_P0_C3;
                    end
                    4'd4: begin
                        pair_sum_comb =
                            $signed({stage2_hist[4][STAGE2_DATA_W-1],
                                     stage2_hist[4]});
                        coeff_comb = `V2_S2_P0_C4;
                    end
                    default: begin
                        pair_sum_comb = {PAIR_W{1'b0}};
                        coeff_comb = {COEFF_W{1'b0}};
                    end
                endcase
            end
            else begin
                case (job_mac_index)
                    4'd0: begin
                        pair_sum_comb =
                            $signed({stage2_hist[0][STAGE2_DATA_W-1],
                                     stage2_hist[0]}) +
                            $signed({stage2_hist[7][STAGE2_DATA_W-1],
                                     stage2_hist[7]});
                        coeff_comb = `V2_S2_P1_C0;
                    end
                    4'd1: begin
                        pair_sum_comb =
                            $signed({stage2_hist[1][STAGE2_DATA_W-1],
                                     stage2_hist[1]}) +
                            $signed({stage2_hist[6][STAGE2_DATA_W-1],
                                     stage2_hist[6]});
                        coeff_comb = `V2_S2_P1_C1;
                    end
                    4'd2: begin
                        pair_sum_comb =
                            $signed({stage2_hist[2][STAGE2_DATA_W-1],
                                     stage2_hist[2]}) +
                            $signed({stage2_hist[5][STAGE2_DATA_W-1],
                                     stage2_hist[5]});
                        coeff_comb = `V2_S2_P1_C2;
                    end
                    4'd3: begin
                        pair_sum_comb =
                            $signed({stage2_hist[3][STAGE2_DATA_W-1],
                                     stage2_hist[3]}) +
                            $signed({stage2_hist[4][STAGE2_DATA_W-1],
                                     stage2_hist[4]});
                        coeff_comb = `V2_S2_P1_C3;
                    end
                    default: begin
                        pair_sum_comb = {PAIR_W{1'b0}};
                        coeff_comb = {COEFF_W{1'b0}};
                    end
                endcase
            end
        end
        else if (job_stage == 2'd3) begin
            if (job_phase == 1'b0) begin
                case (job_mac_index)
                    4'd0: begin
                        pair_sum_comb =
                            $signed({stage3_hist[0][STAGE3_DATA_W-1],
                                     stage3_hist[0]}) +
                            $signed({stage3_hist[5][STAGE3_DATA_W-1],
                                     stage3_hist[5]});
                        coeff_comb = (CIC_ORDER == 3) ?
                                     16'sd561 : 16'sd624;
                    end
                    4'd1: begin
                        pair_sum_comb =
                            $signed({stage3_hist[1][STAGE3_DATA_W-1],
                                     stage3_hist[1]}) +
                            $signed({stage3_hist[4][STAGE3_DATA_W-1],
                                     stage3_hist[4]});
                        coeff_comb = (CIC_ORDER == 3) ?
                                     -16'sd4234 : -16'sd4587;
                    end
                    4'd2: begin
                        pair_sum_comb =
                            $signed({stage3_hist[2][STAGE3_DATA_W-1],
                                     stage3_hist[2]}) +
                            $signed({stage3_hist[3][STAGE3_DATA_W-1],
                                     stage3_hist[3]});
                        coeff_comb = (CIC_ORDER == 3) ?
                                     16'sd20057 : 16'sd20348;
                    end
                    default: begin
                        pair_sum_comb = {PAIR_W{1'b0}};
                        coeff_comb = {COEFF_W{1'b0}};
                    end
                endcase
            end
            else begin
                case (job_mac_index)
                    4'd0: begin
                        pair_sum_comb =
                            $signed({stage3_hist[0][STAGE3_DATA_W-1],
                                     stage3_hist[0]}) +
                            $signed({stage3_hist[4][STAGE3_DATA_W-1],
                                     stage3_hist[4]});
                        coeff_comb = (CIC_ORDER == 3) ?
                                     16'sd137 : 16'sd153;
                    end
                    4'd1: begin
                        pair_sum_comb =
                            $signed({stage3_hist[1][STAGE3_DATA_W-1],
                                     stage3_hist[1]}) +
                            $signed({stage3_hist[3][STAGE3_DATA_W-1],
                                     stage3_hist[3]});
                        coeff_comb = (CIC_ORDER == 3) ?
                                     -16'sd1555 : -16'sd1971;
                    end
                    4'd2: begin
                        pair_sum_comb =
                            $signed({stage3_hist[2][STAGE3_DATA_W-1],
                                     stage3_hist[2]});
                        coeff_comb = (CIC_ORDER == 3) ?
                                     -16'sd29932 : -16'sd29134;
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
            stage2_phase <= 1'b1;
            stage3_phase <= 1'b1;
            stage2_pending <= 1'b0;
            stage3_pending <= 1'b0;
            stage2_pending_phase <= 1'b0;
            stage3_pending_phase <= 1'b0;
            stage2_pending_deadline <= 32'd0;
            stage3_pending_deadline <= 32'd0;
            job_active <= 1'b0;
            job_stage <= 2'd0;
            job_phase <= 1'b0;
            job_mac_index <= 4'd0;
            job_mac_count <= 4'd0;
            job_deadline <= 32'd0;
            cycle_count <= 32'd0;
            acc_reg <= {ACC_W{1'b0}};
            stage2_y_out <= {STAGE2_DATA_W{1'b0}};
            stage3_y_out <= {STAGE3_DATA_W{1'b0}};
            stage2_y_out_valid <= 1'b0;
            stage3_y_out_valid <= 1'b0;

            for (i = 0; i < 9; i = i + 1)
                stage2_hist[i] <= {STAGE2_DATA_W{1'b0}};
            for (i = 0; i < 6; i = i + 1)
                stage3_hist[i] <= {STAGE3_DATA_W{1'b0}};
        end
        else begin
            cycle_count <= cycle_count + 32'd1;
            stage2_y_out_valid <= 1'b0;
            stage3_y_out_valid <= 1'b0;

            if (stage2_ce_out) begin
                stage2_pending <= 1'b1;
                stage2_pending_phase <= stage2_phase;
                stage2_pending_deadline <= cycle_count + 32'd16;

                if (stage2_phase == 1'b0) begin
                    for (i = 8; i > 0; i = i - 1)
                        stage2_hist[i] <= stage2_hist[i-1];
                    stage2_hist[0] <= stage2_x_current;
                end

                stage2_phase <= ~stage2_phase;
            end

            if (stage3_ce_out) begin
                stage3_pending <= 1'b1;
                stage3_pending_phase <= stage3_phase;
                stage3_pending_deadline <= cycle_count + 32'd8;

                if (stage3_phase == 1'b0) begin
                    for (i = 5; i > 0; i = i - 1)
                        stage3_hist[i] <= stage3_hist[i-1];
                    stage3_hist[0] <= stage3_x_current;
                end

                stage3_phase <= ~stage3_phase;
            end

            if (job_active) begin
                if (job_mac_index == job_mac_count - 4'd1) begin
                    if (job_stage == 2'd2) begin
                        stage2_y_out <= stage2_q15_rounded;
                        stage2_y_out_valid <= 1'b1;
                    end
                    else begin
                        stage3_y_out <= stage3_q15_rounded;
                        stage3_y_out_valid <= 1'b1;
                    end

                    job_active <= 1'b0;
                    job_mac_index <= 4'd0;
                    acc_reg <= {ACC_W{1'b0}};
                end
                else begin
                    acc_reg <= mac_sum_comb;
                    job_mac_index <= job_mac_index + 4'd1;
                end
            end
            else if (stage3_pending) begin
                job_active <= 1'b1;
                job_stage <= 2'd3;
                job_phase <= stage3_pending_phase;
                job_mac_index <= 4'd0;
                job_mac_count <= 4'd3;
                job_deadline <= stage3_pending_deadline;
                if (stage3_pending_phase)
                    acc_reg <= stage3_center_direct;
                else
                    acc_reg <= {ACC_W{1'b0}};
                stage3_pending <= 1'b0;
            end
            else if (stage2_pending) begin
                job_active <= 1'b1;
                job_stage <= 2'd2;
                job_phase <= stage2_pending_phase;
                job_mac_index <= 4'd0;
                job_mac_count <= stage2_pending_phase ? 4'd4 : 4'd5;
                job_deadline <= stage2_pending_deadline;
                acc_reg <= {ACC_W{1'b0}};
                stage2_pending <= 1'b0;
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (STAGE2_DATA_W < STAGE3_DATA_W)
            $fatal(1, "Stage 2 data width must be >= Stage 3 data width");
        if (CIC_ORDER != 3 && CIC_ORDER != 4)
            $fatal(1, "CIC_ORDER must be 3 or 4");
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (ACC_W < PROD_W &&
                product_comb[PROD_W-1:ACC_W] !=
                {(PROD_W-ACC_W){product_comb[ACC_W-1]}})
                $fatal(1, "Stage 2/3 product exceeds ACC_W=%0d", ACC_W);

            if (stage2_ce_out && stage2_pending)
                $fatal(1, "Stage 2 shared DSP pending overwrite");
            if (stage3_ce_out && stage3_pending)
                $fatal(1, "Stage 3 shared DSP pending overwrite");

            if (job_active &&
                (job_mac_index == job_mac_count - 4'd1) &&
                ((cycle_count + 32'd1) > job_deadline)) begin
                $fatal(1,
                    "Stage %0d shared DSP deadline miss: finish=%0d deadline=%0d",
                    job_stage, cycle_count + 32'd1, job_deadline);
            end
        end
    end
`endif

endmodule
