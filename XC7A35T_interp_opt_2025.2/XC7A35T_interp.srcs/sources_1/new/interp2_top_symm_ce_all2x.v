`timescale 1ns / 1ps

//=============================================================
// 文件名       : interp2_top_symm_ce_all2x.v
// 模块名       : interp2_top_symm_ce_all2x
// 功能简述     : 全 2x 结构中的单级 2 倍插值封装模块。
//                本模块复用 interp2_ctrl_ce 产生插零后的 FIR 输入，
//                再调用 fir_core_symm_interp2_all2x 完成对应级的
//                对称 FIR 滤波，最后通过 round_sat_q16_to24 输出
//                24bit signed 数据。
//
//                通过 STAGE_ID / COEFF_W / FRAC_W / NTAPS 参数配置
//                当前级所使用的系数表、系数字长和滤波器长度。
//
//                当前默认配置：
//                  数据位宽：24bit signed
//                  默认级号：STAGE_ID = 1
//                  默认 tap：93 tap
//                  默认系数：17bit，Q16
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-10
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-10：新增全 2x 单级 2 倍插值封装模块。
//                2026-07-10：Stage 1 切换为单乘法器时分复用 MAC 核。
//=============================================================
//=============================================================
// 1）模块名称：interp2_top_symm_ce_all2x
// 功能说明：2 倍插值顶层：连接控制器、FIR 核心和输出握手接口。
// 工程版本：Vivado 2025.2。
//=============================================================

module interp2_top_symm_ce_all2x #(
    parameter integer STAGE_ID = 1,
    parameter integer DATA_W   = 24,
    parameter integer COEFF_W  = 17,
    parameter integer ACC_W    = 43,
    parameter integer NTAPS    = 93,
    parameter integer FRAC_W   = 16
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         ce_out,

    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,

    output wire signed [23:0]           y_out,
    output wire                         y_out_valid,

    output wire                         phase_dbg,
    output wire signed [23:0]           fir_in_dbg,
    output wire                         fir_in_valid_dbg
);

    wire signed [DATA_W-1:0] fir_in_w;
    wire                     fir_in_valid_w;

    wire signed [ACC_W-1:0]  y_out_full_w;
    wire                     y_out_full_valid_w;

    wire signed [DATA_W-1:0] sample_buf_w;

    // 例化说明：调用 interp2_ctrl_ce 插值子模块，完成对应级的数据展开、滤波或模式选择。
    interp2_ctrl_ce u_interp2_ctrl_ce (
        .clk          (clk),
        .rst_n        (rst_n),
        .ce_out       (ce_out),

        .x_in         (x_in),
        .x_in_valid   (x_in_valid),

        .fir_in       (fir_in_w),
        .fir_in_valid (fir_in_valid_w),

        .phase        (phase_dbg),
        .sample_buf   (sample_buf_w)
    );

    generate
        if (STAGE_ID == 1) begin : gen_stage1_single_mac
            // 例化说明：调用 fir_core_symm_interp2_stage1_mac FIR 子模块，完成本级对称抽头乘加和定点输出。
            fir_core_symm_interp2_stage1_mac #(
                .DATA_W  (DATA_W),
                .COEFF_W (COEFF_W),
                .ACC_W   (ACC_W),
                .NTAPS   (NTAPS)
            ) u_fir_core_symm_interp2_stage1_mac (
                .clk           (clk),
                .rst_n         (rst_n),
                .fir_in        (fir_in_w),
                .fir_in_valid  (fir_in_valid_w),
                .fir_out_full  (y_out_full_w),
                .fir_out_valid (y_out_full_valid_w)
            );
        end
        else begin : gen_parallel_fir
            // 例化说明：调用 fir_core_symm_interp2_all2x FIR 子模块，完成本级对称抽头乘加和定点输出。
            fir_core_symm_interp2_all2x #(
                .STAGE_ID (STAGE_ID),
                .DATA_W   (DATA_W),
                .COEFF_W  (COEFF_W),
                .ACC_W    (ACC_W),
                .NTAPS    (NTAPS)
            ) u_fir_core_symm_interp2_all2x (
                .clk           (clk),
                .rst_n         (rst_n),
                .fir_in        (fir_in_w),
                .fir_in_valid  (fir_in_valid_w),
                .fir_out_full  (y_out_full_w),
                .fir_out_valid (y_out_full_valid_w)
            );
        end
    endgenerate

    // 例化说明：调用 round_sat_q16_to24 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    round_sat_q16_to24 #(
        .IN_W   (ACC_W),
        .OUT_W  (24),
        .FRAC_W (FRAC_W)
    ) u_round_sat_q16_to24 (
        .din_full (y_out_full_w),
        .dout_24  (y_out)
    );

    assign y_out_valid     = y_out_full_valid_w;
    assign fir_in_dbg      = fir_in_w;
    assign fir_in_valid_dbg = fir_in_valid_w;

endmodule
