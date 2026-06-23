`timescale 1ns / 1ps

module interp128_top_ce #(
    parameter DATA_W   = 24,
    parameter COEFF_W  = 18,
    parameter ACC_W    = 56,
    parameter NTAPS4X  = 155,
    parameter NTAPS2X  = 11
)(
    input  wire                         clk,
    input  wire                         rst_n,

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

    // 调试输出：观察 128x 级联内部各关键级
    output wire signed [23:0]           dbg_y4,
    output wire                         dbg_y4_valid,
    output wire signed [23:0]           dbg_y8,
    output wire                         dbg_y8_valid,
    output wire signed [23:0]           dbg_y32,
    output wire                         dbg_y32_valid,
    output wire signed [23:0]           dbg_y64,
    output wire                         dbg_y64_valid
);

    //====================================================
    // Stage 1 : 4x
    //====================================================
    wire signed [23:0] y4_w;
    wire               y4_valid_w;

    interp4_top_symm_ce #(
        .DATA_W  (DATA_W),
        .COEFF_W (COEFF_W),
        .ACC_W   (ACC_W),
        .NTAPS   (NTAPS4X)
    ) u_interp4_top_symm_ce (
        .clk              (clk),
        .rst_n            (rst_n),
        .ce_out           (ce4_out),
        .x_in             (x_in),
        .x_in_valid       (x_in_valid),
        .y_out            (y4_w),
        .y_out_valid      (y4_valid_w),
        .phase_dbg        (),
        .fir_in_dbg       (),
        .fir_in_valid_dbg ()
    );

    //====================================================
    // Bridge : 4x -> 8x
    //====================================================
    wire signed [23:0] y4_to_8_data;
    wire               y4_to_8_valid;

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

    //====================================================
    // Stage 2 : 8x
    //====================================================
    wire signed [23:0] y8_w;
    wire               y8_valid_w;

    interp2_top_symm_ce #(
        .DATA_W  (DATA_W),
        .COEFF_W (COEFF_W),
        .ACC_W   (ACC_W),
        .NTAPS   (NTAPS2X)
    ) u_interp2_top_8x (
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

    //====================================================
    // Bridge : 8x -> 16x
    //====================================================
    wire signed [23:0] y8_to_16_data;
    wire               y8_to_16_valid;

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

    //====================================================
    // Stage 3 : 16x
    //====================================================
    wire signed [23:0] y16_w;
    wire               y16_valid_w;

    interp2_top_symm_ce #(
        .DATA_W  (DATA_W),
        .COEFF_W (COEFF_W),
        .ACC_W   (ACC_W),
        .NTAPS   (NTAPS2X)
    ) u_interp2_top_16x (
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

    //====================================================
    // Bridge : 16x -> 32x
    //====================================================
    wire signed [23:0] y16_to_32_data;
    wire               y16_to_32_valid;

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

    //====================================================
    // Stage 4 : 32x
    //====================================================
    wire signed [23:0] y32_w;
    wire               y32_valid_w;

    interp2_top_symm_ce #(
        .DATA_W  (DATA_W),
        .COEFF_W (COEFF_W),
        .ACC_W   (ACC_W),
        .NTAPS   (NTAPS2X)
    ) u_interp2_top_32x (
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

    //====================================================
    // Bridge : 32x -> 64x
    //====================================================
    wire signed [23:0] y32_to_64_data;
    wire               y32_to_64_valid;

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

    //====================================================
    // Stage 5 : 64x
    //====================================================
    wire signed [23:0] y64_w;
    wire               y64_valid_w;

    interp2_top_symm_ce #(
        .DATA_W  (DATA_W),
        .COEFF_W (COEFF_W),
        .ACC_W   (ACC_W),
        .NTAPS   (NTAPS2X)
    ) u_interp2_top_64x (
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

    //====================================================
    // Bridge : 64x -> 128x
    //====================================================
    wire signed [23:0] y64_to_128_data;
    wire               y64_to_128_valid;

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

    //====================================================
    // Stage 6 : 128x
    //====================================================
    wire signed [23:0] y128_w;
    wire               y128_valid_w;

    interp2_top_symm_ce #(
        .DATA_W  (DATA_W),
        .COEFF_W (COEFF_W),
        .ACC_W   (ACC_W),
        .NTAPS   (NTAPS2X)
    ) u_interp2_top_128x (
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

    //====================================================
    // 调试引出
    //====================================================
    assign dbg_y4       = y4_w;
    assign dbg_y4_valid = y4_valid_w;

    assign dbg_y8       = y8_w;
    assign dbg_y8_valid = y8_valid_w;

    assign dbg_y32       = y32_w;
    assign dbg_y32_valid = y32_valid_w;

    assign dbg_y64       = y64_w;
    assign dbg_y64_valid = y64_valid_w;

endmodule