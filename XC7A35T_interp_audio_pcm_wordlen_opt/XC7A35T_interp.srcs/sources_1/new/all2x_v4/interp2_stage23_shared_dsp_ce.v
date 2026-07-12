`timescale 1ns / 1ps

`include "all2x_v2_coeff_pkg.vh"

//=============================================================
// 文件名       : interp2_stage23_shared_dsp_ce.v
// 模块名       : interp2_stage23_shared_dsp_ce
// 功能简述     : Stage 2/3 共用一个 DSP 的 true-polyphase FIR。
//                两级分别保存真实输入历史，在各自 CE 到达时生成
//                MAC job；调度器采用 Stage 3 优先策略，共享一个
//                25x16 signed 乘法器和 42bit 累加器。
//
//                Stage 2：phase0=5 MAC，phase1=4 MAC，Q15
//                Stage 3：phase0=3 MAC，phase1=3 MAC，等价改写为 Q15
//
// 当前默认配置：
//                  输入输出位宽：24bit signed
//                  共享 DSP 数 ：1
//                  调度优先级  ：Stage 3 > Stage 2
//                  系数来源    ：all2x_v2_coeff_pkg.vh
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
//=============================================================

module interp2_stage23_shared_dsp_ce #(
    parameter integer DATA_W = 24,
    parameter integer COEFF_W = 16,
    parameter integer ACC_W = 42
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         stage2_ce_out,
    input  wire signed [DATA_W-1:0]     stage2_x_in,
    input  wire                         stage2_x_in_valid,
    output reg  signed [DATA_W-1:0]     stage2_y_out,
    output reg                          stage2_y_out_valid,

    input  wire                         stage3_ce_out,
    input  wire signed [DATA_W-1:0]     stage3_x_in,
    input  wire                         stage3_x_in_valid,
    output reg  signed [DATA_W-1:0]     stage3_y_out,
    output reg                          stage3_y_out_valid,

    output wire                         stage2_phase_dbg,
    output wire                         stage3_phase_dbg,
    output wire                         scheduler_busy_dbg,
    output wire [1:0]                   scheduler_stage_dbg,
    output wire [3:0]                   scheduler_mac_index_dbg
);

    localparam integer PAIR_W = DATA_W + 1;
    localparam integer PROD_W = PAIR_W + COEFF_W;

    reg signed [DATA_W-1:0] stage2_hist [0:8];
    reg signed [DATA_W-1:0] stage3_hist [0:5];

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
    wire signed [DATA_W-1:0] shared_q15_rounded;

    wire signed [DATA_W-1:0] stage2_x_current;
    wire signed [DATA_W-1:0] stage3_x_current;

    integer i;

    assign stage2_x_current = stage2_x_in_valid ? stage2_x_in :
                              {DATA_W{1'b0}};
    assign stage3_x_current = stage3_x_in_valid ? stage3_x_in :
                              {DATA_W{1'b0}};

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
    assign mac_sum_comb = (job_mac_index == 4'd0) ? product_ext :
                          (acc_reg + product_ext);

    assign stage2_phase_dbg = stage2_phase;
    assign stage3_phase_dbg = stage3_phase;
    assign scheduler_busy_dbg = job_active;
    assign scheduler_stage_dbg = job_stage;
    assign scheduler_mac_index_dbg = job_mac_index;

    round_sat_q15_compact_to24 #(
        .IN_W   (ACC_W),
        .OUT_W  (DATA_W)
    ) u_round_shared_q15_compact (
        .din_full (mac_sum_comb),
        .dout_24  (shared_q15_rounded)
    );

    always @(*) begin
        pair_sum_comb = {PAIR_W{1'b0}};
        coeff_comb = {COEFF_W{1'b0}};

        if (job_stage == 2'd2) begin
            if (job_phase == 1'b0) begin
                case (job_mac_index)
                    4'd0: begin
                        pair_sum_comb =
                            $signed({stage2_hist[0][DATA_W-1],
                                     stage2_hist[0]}) +
                            $signed({stage2_hist[8][DATA_W-1],
                                     stage2_hist[8]});
                        coeff_comb = `V2_S2_P0_C0;
                    end
                    4'd1: begin
                        pair_sum_comb =
                            $signed({stage2_hist[1][DATA_W-1],
                                     stage2_hist[1]}) +
                            $signed({stage2_hist[7][DATA_W-1],
                                     stage2_hist[7]});
                        coeff_comb = `V2_S2_P0_C1;
                    end
                    4'd2: begin
                        pair_sum_comb =
                            $signed({stage2_hist[2][DATA_W-1],
                                     stage2_hist[2]}) +
                            $signed({stage2_hist[6][DATA_W-1],
                                     stage2_hist[6]});
                        coeff_comb = `V2_S2_P0_C2;
                    end
                    4'd3: begin
                        pair_sum_comb =
                            $signed({stage2_hist[3][DATA_W-1],
                                     stage2_hist[3]}) +
                            $signed({stage2_hist[5][DATA_W-1],
                                     stage2_hist[5]});
                        coeff_comb = `V2_S2_P0_C3;
                    end
                    4'd4: begin
                        pair_sum_comb =
                            $signed({stage2_hist[4][DATA_W-1],
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
                            $signed({stage2_hist[0][DATA_W-1],
                                     stage2_hist[0]}) +
                            $signed({stage2_hist[7][DATA_W-1],
                                     stage2_hist[7]});
                        coeff_comb = `V2_S2_P1_C0;
                    end
                    4'd1: begin
                        pair_sum_comb =
                            $signed({stage2_hist[1][DATA_W-1],
                                     stage2_hist[1]}) +
                            $signed({stage2_hist[6][DATA_W-1],
                                     stage2_hist[6]});
                        coeff_comb = `V2_S2_P1_C1;
                    end
                    4'd2: begin
                        pair_sum_comb =
                            $signed({stage2_hist[2][DATA_W-1],
                                     stage2_hist[2]}) +
                            $signed({stage2_hist[5][DATA_W-1],
                                     stage2_hist[5]});
                        coeff_comb = `V2_S2_P1_C2;
                    end
                    4'd3: begin
                        pair_sum_comb =
                            $signed({stage2_hist[3][DATA_W-1],
                                     stage2_hist[3]}) +
                            $signed({stage2_hist[4][DATA_W-1],
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
                            $signed({stage3_hist[0][DATA_W-1],
                                     stage3_hist[0]}) +
                            $signed({stage3_hist[5][DATA_W-1],
                                     stage3_hist[5]});
                        coeff_comb = 16'sd404;
                    end
                    4'd1: begin
                        pair_sum_comb =
                            $signed({stage3_hist[1][DATA_W-1],
                                     stage3_hist[1]}) +
                            $signed({stage3_hist[4][DATA_W-1],
                                     stage3_hist[4]});
                        coeff_comb = -16'sd3272;
                    end
                    4'd2: begin
                        pair_sum_comb =
                            $signed({stage3_hist[2][DATA_W-1],
                                     stage3_hist[2]}) +
                            $signed({stage3_hist[3][DATA_W-1],
                                     stage3_hist[3]});
                        coeff_comb = 16'sd19250;
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
                            $signed({stage3_hist[0][DATA_W-1],
                                     stage3_hist[0]}) +
                            $signed({stage3_hist[4][DATA_W-1],
                                     stage3_hist[4]});
                        coeff_comb = -16'sd148;
                    end
                    4'd1: begin
                        pair_sum_comb =
                            $signed({stage3_hist[1][DATA_W-1],
                                     stage3_hist[1]}) +
                            $signed({stage3_hist[3][DATA_W-1],
                                     stage3_hist[3]});
                        coeff_comb = 16'sd522;
                    end
                    4'd2: begin
                        pair_sum_comb =
                            $signed({stage3_hist[2][DATA_W-1],
                                     stage3_hist[2]});
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
            stage2_y_out <= {DATA_W{1'b0}};
            stage3_y_out <= {DATA_W{1'b0}};
            stage2_y_out_valid <= 1'b0;
            stage3_y_out_valid <= 1'b0;

            for (i = 0; i < 9; i = i + 1)
                stage2_hist[i] <= {DATA_W{1'b0}};
            for (i = 0; i < 6; i = i + 1)
                stage3_hist[i] <= {DATA_W{1'b0}};
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
                        stage2_y_out <= shared_q15_rounded;
                        stage2_y_out_valid <= 1'b1;
                    end
                    else begin
                        stage3_y_out <= shared_q15_rounded;
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
