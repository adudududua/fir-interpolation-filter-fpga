`timescale 1ns / 1ps

//=============================================================
// 文件名       : interp2_all2x_v2_stage_select.v
// 模块名       : interp2_all2x_v2_stage_select
// 功能简述     : V2 全 2x 实验的单级选择封装。根据 USE_CANONICAL
//                选择稳定版对称 FIR，或精确 7 tap 半带移位加法核。
//                本模块仅用于独立 V2 实验目录，不改变稳定版模块。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-11
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-11：新增 V2 单级结构选择封装。
//=============================================================
//=============================================================
// 1）模块名称：interp2_all2x_v2_stage_select
// 功能说明：插值级选择器：根据倍率模式选择旁路或滤波后的数据与有效信号。
// 工程版本：Vivado 2025.2。
//=============================================================

module interp2_all2x_v2_stage_select #(
    parameter integer USE_CANONICAL = 0,
    parameter integer STAGE_ID      = 4,
    parameter integer DATA_W        = 24,
    parameter integer COEFF_W       = 16,
    parameter integer ACC_W         = 41,
    parameter integer NTAPS         = 7,
    parameter integer FRAC_W        = 15
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
        if (USE_CANONICAL != 0) begin : gen_canonical
            // 例化说明：调用 interp2_halfband7_shiftadd_ce 插值子模块，完成对应级的数据展开、滤波或模式选择。
            interp2_halfband7_shiftadd_ce #(
                .DATA_W (DATA_W)
            ) u_interp2_halfband7_shiftadd_ce (
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
