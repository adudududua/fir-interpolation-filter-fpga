`timescale 1ns / 1ps

//=============================================================
// 文件名       : interp2_stage23_v2_select.v
// 模块名       : interp2_stage23_v2_select
// 功能简述     : Phase 2 的 Stage 2/3 结构选择封装。根据
//                USE_POLYPHASE 选择稳定版显式插零 FIR，或只保存
//                真实输入历史的 true-polyphase FIR。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-11
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-11：新增 Stage 2/3 Phase 2 选择封装。
//=============================================================
//=============================================================
// 1）模块名称：interp2_stage23_v2_select
// 功能说明：第二、三级 2 倍插值滤波器：复用或折叠运算资源完成连续插值。
// 工程版本：Vivado 2025.2。
//=============================================================

module interp2_stage23_v2_select #(
    parameter integer USE_POLYPHASE = 0,
    parameter integer STAGE_ID      = 3,
    parameter integer DATA_W        = 24,
    parameter integer COEFF_W       = 15,
    parameter integer ACC_W         = 40,
    parameter integer NTAPS         = 11,
    parameter integer FRAC_W        = 14
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ce_out,
    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,
    output wire signed [DATA_W-1:0]     y_out,
    output wire                         y_out_valid,
    output wire                         phase_dbg,
    output wire signed [DATA_W-1:0]     fir_in_dbg,
    output wire                         fir_in_valid_dbg
);

    generate
        if (USE_POLYPHASE != 0) begin : gen_polyphase
            // 例化说明：调用 interp2_stage23_polyphase_ce 插值子模块，完成对应级的数据展开、滤波或模式选择。
            interp2_stage23_polyphase_ce #(
                .STAGE_ID (STAGE_ID),
                .DATA_W   (DATA_W),
                .COEFF_W  (COEFF_W),
                .ACC_W    (ACC_W),
                .FRAC_W   (FRAC_W)
            ) u_interp2_stage23_polyphase_ce (
                .clk         (clk),
                .rst_n       (rst_n),
                .ce_out      (ce_out),
                .x_in        (x_in),
                .x_in_valid  (x_in_valid),
                .y_out       (y_out),
                .y_out_valid (y_out_valid),
                .phase_dbg   (phase_dbg)
            );

            assign fir_in_dbg       = {DATA_W{1'b0}};
            assign fir_in_valid_dbg = ce_out;
        end
        else begin : gen_stable
            // 例化说明：调用 interp2_top_symm_ce_all2x 插值子模块，完成对应级的数据展开、滤波或模式选择。
            interp2_top_symm_ce_all2x #(
                .STAGE_ID (STAGE_ID),
                .DATA_W   (DATA_W),
                .COEFF_W  (COEFF_W),
                .ACC_W    (ACC_W),
                .NTAPS    (NTAPS),
                .FRAC_W   (FRAC_W)
            ) u_interp2_top_symm_ce_all2x (
                .clk              (clk),
                .rst_n            (rst_n),
                .ce_out           (ce_out),
                .x_in             (x_in),
                .x_in_valid       (x_in_valid),
                .y_out            (y_out),
                .y_out_valid      (y_out_valid),
                .phase_dbg        (phase_dbg),
                .fir_in_dbg       (fir_in_dbg),
                .fir_in_valid_dbg (fir_in_valid_dbg)
            );
        end
    endgenerate

endmodule
