`timescale 1ns / 1ps

//=============================================================
// 文件名       : interp128_all2x_v2_top_ce.v
// 模块名       : interp128_all2x_v2_top_ce
// 功能简述     : V2 全 2x 尾级 canonical halfband7 对比顶层模块。
//                Stage 1～3 保持稳定版实现，Stage 4～7 可按
//                FIRST_CANONICAL_STAGE 从指定级开始替换为精确
//                7 tap true-polyphase 移位加法结构。
//
//                级联结构：
//                  44.1kHz   -> 2x -> 88.2kHz
//                  88.2kHz   -> 2x -> 176.4kHz
//                  176.4kHz  -> 2x -> 352.8kHz
//                  352.8kHz  -> 2x -> 705.6kHz
//                  705.6kHz  -> 2x -> 1.4112MHz
//                  1.4112MHz -> 2x -> 2.8224MHz
//                  2.8224MHz -> 2x -> 5.6448MHz
//
//                调用者需要在 5.6448MHz 的最终 128x 时钟域中产生
//                ce2_out、ce4_out、ce8_out、ce16_out、ce32_out、
//                ce64_out、ce128_out 等多级时钟使能信号。
//
//                当前默认配置：
//                  输入采样率：44.1kHz
//                  输出采样率：5.6448MHz
//                  插值倍数  ：128 倍
//                  级联结构  ：7 级 2x
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-10
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-10：新增全 2x 结构 128 倍插值顶层模块。
//                2026-07-10：同步含 2 倍插值增益的新系数参数，并按
//                            bit-true 结果收紧系数与累加器位宽。
//                2026-07-11：新增 V2 尾级 canonical 逐级替换参数。
//=============================================================
//=============================================================
// 1）模块名称：interp128_all2x_v2_top_ce
// 功能说明：128 倍插值顶层：级联多级 2 倍插值、CIC 与补偿级并管理模式旁路。
// 工程版本：Vivado 2025.2。
//=============================================================

module interp128_all2x_v2_top_ce #(
    parameter integer DATA_W = 24,
    parameter integer FIRST_CANONICAL_STAGE = 8
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         ce2_out,
    input  wire                         ce4_out,
    input  wire                         ce8_out,
    input  wire                         ce16_out,
    input  wire                         ce32_out,
    input  wire                         ce64_out,
    input  wire                         ce128_out,

    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,

    output wire signed [23:0]           y_out,
    output wire                         y_out_valid,

    output wire signed [23:0]           dbg_y2,
    output wire                         dbg_y2_valid,
    output wire signed [23:0]           dbg_y4,
    output wire                         dbg_y4_valid,
    output wire signed [23:0]           dbg_y8,
    output wire                         dbg_y8_valid,
    output wire signed [23:0]           dbg_y16,
    output wire                         dbg_y16_valid,
    output wire signed [23:0]           dbg_y32,
    output wire                         dbg_y32_valid,
    output wire signed [23:0]           dbg_y64,
    output wire                         dbg_y64_valid
);

    wire signed [23:0] y2_w;
    wire               y2_valid_w;
    wire signed [23:0] y2_to_4_data;
    wire               y2_to_4_valid;

    wire signed [23:0] y4_w;
    wire               y4_valid_w;
    wire signed [23:0] y4_to_8_data;
    wire               y4_to_8_valid;

    wire signed [23:0] y8_w;
    wire               y8_valid_w;
    wire signed [23:0] y8_to_16_data;
    wire               y8_to_16_valid;

    wire signed [23:0] y16_w;
    wire               y16_valid_w;
    wire signed [23:0] y16_to_32_data;
    wire               y16_to_32_valid;

    wire signed [23:0] y32_w;
    wire               y32_valid_w;
    wire signed [23:0] y32_to_64_data;
    wire               y32_to_64_valid;

    wire signed [23:0] y64_w;
    wire               y64_valid_w;
    wire signed [23:0] y64_to_128_data;
    wire               y64_to_128_valid;

    wire signed [23:0] y128_w;
    wire               y128_valid_w;

    //=========================================================
    // Stage 1: 44.1 kHz -> 88.2 kHz
    //=========================================================
    // 例化说明：调用 interp2_top_symm_ce_all2x 插值子模块，完成对应级的数据展开、滤波或模式选择。
    interp2_top_symm_ce_all2x #(
        .STAGE_ID (1),
        .DATA_W   (DATA_W),
        .COEFF_W  (17),
        .ACC_W    (43),
        .NTAPS    (93),
        .FRAC_W   (16)
    ) u_interp2_all2x_stage1 (
        .clk              (clk),
        .rst_n            (rst_n),
        .ce_out           (ce2_out),
        .x_in             (x_in),
        .x_in_valid       (x_in_valid),
        .y_out            (y2_w),
        .y_out_valid      (y2_valid_w),
        .phase_dbg        (),
        .fir_in_dbg       (),
        .fir_in_valid_dbg ()
    );

    // 例化说明：调用 bridge_to_interp2_ce 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    bridge_to_interp2_ce #(
        .DATA_W (24)
    ) u_bridge_2_to_4 (
        .clk         (clk),
        .rst_n       (rst_n),
        .in_data     (y2_w),
        .in_valid    (y2_valid_w),
        .ce_out_next (ce4_out),
        .out_data    (y2_to_4_data),
        .out_valid   (y2_to_4_valid)
    );

    //=========================================================
    // Stage 2: 88.2 kHz -> 176.4 kHz
    //=========================================================
    // 例化说明：调用 interp2_top_symm_ce_all2x 插值子模块，完成对应级的数据展开、滤波或模式选择。
    interp2_top_symm_ce_all2x #(
        .STAGE_ID (2),
        .DATA_W   (DATA_W),
        .COEFF_W  (16),
        .ACC_W    (41),
        .NTAPS    (17),
        .FRAC_W   (15)
    ) u_interp2_all2x_stage2 (
        .clk              (clk),
        .rst_n            (rst_n),
        .ce_out           (ce4_out),
        .x_in             (y2_to_4_data),
        .x_in_valid       (y2_to_4_valid),
        .y_out            (y4_w),
        .y_out_valid      (y4_valid_w),
        .phase_dbg        (),
        .fir_in_dbg       (),
        .fir_in_valid_dbg ()
    );

    // 例化说明：调用 bridge_to_interp2_ce 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    bridge_to_interp2_ce #(
        .DATA_W (24)
    ) u_bridge_4_to_8 (
        .clk         (clk),
        .rst_n       (rst_n),
        .in_data     (y4_w),
        .in_valid    (y4_valid_w),
        .ce_out_next (ce8_out),
        .out_data    (y4_to_8_data),
        .out_valid   (y4_to_8_valid)
    );

    //=========================================================
    // Stage 3: 176.4 kHz -> 352.8 kHz
    //=========================================================
    // 例化说明：调用 interp2_top_symm_ce_all2x 插值子模块，完成对应级的数据展开、滤波或模式选择。
    interp2_top_symm_ce_all2x #(
        .STAGE_ID (3),
        .DATA_W   (DATA_W),
        .COEFF_W  (15),
        .ACC_W    (40),
        .NTAPS    (11),
        .FRAC_W   (14)
    ) u_interp2_all2x_stage3 (
        .clk              (clk),
        .rst_n            (rst_n),
        .ce_out           (ce8_out),
        .x_in             (y4_to_8_data),
        .x_in_valid       (y4_to_8_valid),
        .y_out            (y8_w),
        .y_out_valid      (y8_valid_w),
        .phase_dbg        (),
        .fir_in_dbg       (),
        .fir_in_valid_dbg ()
    );

    // 例化说明：调用 bridge_to_interp2_ce 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    bridge_to_interp2_ce #(
        .DATA_W (24)
    ) u_bridge_8_to_16 (
        .clk         (clk),
        .rst_n       (rst_n),
        .in_data     (y8_w),
        .in_valid    (y8_valid_w),
        .ce_out_next (ce16_out),
        .out_data    (y8_to_16_data),
        .out_valid   (y8_to_16_valid)
    );

    //=========================================================
    // Stage 4: 352.8 kHz -> 705.6 kHz
    //=========================================================
    // 例化说明：调用 interp2_all2x_v2_stage_select 插值子模块，完成对应级的数据展开、滤波或模式选择。
    interp2_all2x_v2_stage_select #(
        .USE_CANONICAL (FIRST_CANONICAL_STAGE <= 4),
        .STAGE_ID (4),
        .DATA_W   (DATA_W),
        .COEFF_W  (16),
        .ACC_W    (41),
        .NTAPS    (7),
        .FRAC_W   (15)
    ) u_interp2_all2x_stage4 (
        .clk              (clk),
        .rst_n            (rst_n),
        .ce_out           (ce16_out),
        .x_in             (y8_to_16_data),
        .x_in_valid       (y8_to_16_valid),
        .y_out            (y16_w),
        .y_out_valid      (y16_valid_w),
        .phase_dbg        (),
        .fir_in_dbg       (),
        .fir_in_valid_dbg ()
    );

    // 例化说明：调用 bridge_to_interp2_ce 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    bridge_to_interp2_ce #(
        .DATA_W (24)
    ) u_bridge_16_to_32 (
        .clk         (clk),
        .rst_n       (rst_n),
        .in_data     (y16_w),
        .in_valid    (y16_valid_w),
        .ce_out_next (ce32_out),
        .out_data    (y16_to_32_data),
        .out_valid   (y16_to_32_valid)
    );

    //=========================================================
    // Stage 5: 705.6 kHz -> 1.4112 MHz
    //=========================================================
    // 例化说明：调用 interp2_all2x_v2_stage_select 插值子模块，完成对应级的数据展开、滤波或模式选择。
    interp2_all2x_v2_stage_select #(
        .USE_CANONICAL (FIRST_CANONICAL_STAGE <= 5),
        .STAGE_ID (5),
        .DATA_W   (DATA_W),
        .COEFF_W  (14),
        .ACC_W    (39),
        .NTAPS    (7),
        .FRAC_W   (13)
    ) u_interp2_all2x_stage5 (
        .clk              (clk),
        .rst_n            (rst_n),
        .ce_out           (ce32_out),
        .x_in             (y16_to_32_data),
        .x_in_valid       (y16_to_32_valid),
        .y_out            (y32_w),
        .y_out_valid      (y32_valid_w),
        .phase_dbg        (),
        .fir_in_dbg       (),
        .fir_in_valid_dbg ()
    );

    // 例化说明：调用 bridge_to_interp2_ce 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    bridge_to_interp2_ce #(
        .DATA_W (24)
    ) u_bridge_32_to_64 (
        .clk         (clk),
        .rst_n       (rst_n),
        .in_data     (y32_w),
        .in_valid    (y32_valid_w),
        .ce_out_next (ce64_out),
        .out_data    (y32_to_64_data),
        .out_valid   (y32_to_64_valid)
    );

    //=========================================================
    // Stage 6: 1.4112 MHz -> 2.8224 MHz
    //=========================================================
    // 例化说明：调用 interp2_all2x_v2_stage_select 插值子模块，完成对应级的数据展开、滤波或模式选择。
    interp2_all2x_v2_stage_select #(
        .USE_CANONICAL (FIRST_CANONICAL_STAGE <= 6),
        .STAGE_ID (6),
        .DATA_W   (DATA_W),
        .COEFF_W  (13),
        .ACC_W    (38),
        .NTAPS    (7),
        .FRAC_W   (12)
    ) u_interp2_all2x_stage6 (
        .clk              (clk),
        .rst_n            (rst_n),
        .ce_out           (ce64_out),
        .x_in             (y32_to_64_data),
        .x_in_valid       (y32_to_64_valid),
        .y_out            (y64_w),
        .y_out_valid      (y64_valid_w),
        .phase_dbg        (),
        .fir_in_dbg       (),
        .fir_in_valid_dbg ()
    );

    // 例化说明：调用 bridge_to_interp2_ce 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    bridge_to_interp2_ce #(
        .DATA_W (24)
    ) u_bridge_64_to_128 (
        .clk         (clk),
        .rst_n       (rst_n),
        .in_data     (y64_w),
        .in_valid    (y64_valid_w),
        .ce_out_next (ce128_out),
        .out_data    (y64_to_128_data),
        .out_valid   (y64_to_128_valid)
    );

    //=========================================================
    // Stage 7: 2.8224 MHz -> 5.6448 MHz
    //=========================================================
    // 例化说明：调用 interp2_all2x_v2_stage_select 插值子模块，完成对应级的数据展开、滤波或模式选择。
    interp2_all2x_v2_stage_select #(
        .USE_CANONICAL (FIRST_CANONICAL_STAGE <= 7),
        .STAGE_ID (7),
        .DATA_W   (DATA_W),
        .COEFF_W  (14),
        .ACC_W    (38),
        .NTAPS    (7),
        .FRAC_W   (12)
    ) u_interp2_all2x_stage7 (
        .clk              (clk),
        .rst_n            (rst_n),
        .ce_out           (ce128_out),
        .x_in             (y64_to_128_data),
        .x_in_valid       (y64_to_128_valid),
        .y_out            (y128_w),
        .y_out_valid      (y128_valid_w),
        .phase_dbg        (),
        .fir_in_dbg       (),
        .fir_in_valid_dbg ()
    );

    assign y_out       = y128_w;
    assign y_out_valid = y128_valid_w;

    assign dbg_y2        = y2_w;
    assign dbg_y2_valid  = y2_valid_w;
    assign dbg_y4        = y4_w;
    assign dbg_y4_valid  = y4_valid_w;
    assign dbg_y8        = y8_w;
    assign dbg_y8_valid  = y8_valid_w;
    assign dbg_y16       = y16_w;
    assign dbg_y16_valid = y16_valid_w;
    assign dbg_y32       = y32_w;
    assign dbg_y32_valid = y32_valid_w;
    assign dbg_y64       = y64_w;
    assign dbg_y64_valid = y64_valid_w;

endmodule
