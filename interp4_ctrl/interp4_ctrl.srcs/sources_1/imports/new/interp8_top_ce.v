`timescale 1ns / 1ps

module interp8_top_ce #(
    parameter DATA_W   = 24,
    parameter COEFF_W  = 18,
    parameter ACC_W    = 56,
    parameter NTAPS4X  = 155,  // 前级 4x FIR 长度
    parameter NTAPS2X  = 11    // 后级 2x FIR 长度
)(
    input  wire                         clk,
    input  wire                         rst_n,

    //====================================================
    // 两级插值使用的使能
    //
    // ce4_out：
    //   给 4x 级使用，对应 4x 级的输出采样时刻
    //
    // ce8_out：
    //   给 2x 级使用，对应最终 8x 输出采样时刻
    //
    // 在最终 8x 时钟系统里，常见关系是：
    //   ce8_out = 1（每拍都有效）
    //   ce4_out = 每隔 2 拍有效一次
    //====================================================
    input  wire                         ce4_out,
    input  wire                         ce8_out,

    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,

    output wire signed [23:0]           y_out,
    output wire                         y_out_valid,

    // 调试输出：前级 4x
    output wire [1:0]                   phase4_dbg,
    output wire signed [23:0]           y4_dbg,
    output wire                         y4_valid_dbg,

    // 调试输出：后级 2x
    output wire                         phase2_dbg,
    output wire signed [23:0]           fir2_in_dbg,
    output wire                         fir2_in_valid_dbg
);

    //====================================================
    // 中间连线：4x 级输出 -> 2x 级输入
    //====================================================
    wire signed [23:0] y4_w;
    wire               y4_valid_w;

    // 4x -> 2x 之间打一拍，避免同一个 posedge 下后级读到旧值
    reg  signed [23:0] y4_d;
    reg                y4_valid_d;

    wire signed [23:0] fir4_in_dbg_w;
    wire               fir4_in_valid_dbg_w;

    //====================================================
    // 1) 前级：4x 最终版插值器
    //====================================================
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

        .phase_dbg        (phase4_dbg),
        .fir_in_dbg       (fir4_in_dbg_w),
        .fir_in_valid_dbg (fir4_in_valid_dbg_w)
    );

    //====================================================
    // 1.5) 4x 输出打一拍，再送给 2x
    //
    // 原因：
    // 4x 和 2x 都在 posedge clk 上更新寄存器。
    // 如果直接把 y4_w / y4_valid_w 连给 2x，
    // 那么 2x 在这个时钟边沿看到的是“上一拍的旧值”。
    //
    // 现在先打一拍，让 2x 在下一拍读到已经稳定的 y4 数据和 valid。
    //====================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y4_d       <= 24'sd0;
            y4_valid_d <= 1'b0;
        end
        else begin
            y4_d       <= y4_w;
            y4_valid_d <= y4_valid_w;
        end
    end

    //====================================================
    // 2) 后级：2x 插值器
    //====================================================
    interp2_top_symm_ce #(
        .DATA_W  (DATA_W),
        .COEFF_W (COEFF_W),
        .ACC_W   (ACC_W),
        .NTAPS   (NTAPS2X)
    ) u_interp2_top_symm_ce (
        .clk              (clk),
        .rst_n            (rst_n),
        .ce_out           (ce8_out),

        .x_in             (y4_d),
        .x_in_valid       (y4_valid_d),

        .y_out            (y_out),
        .y_out_valid      (y_out_valid),

        .phase_dbg        (phase2_dbg),
        .fir_in_dbg       (fir2_in_dbg),
        .fir_in_valid_dbg (fir2_in_valid_dbg)
    );

    //====================================================
    // 3) 调试引出
    //====================================================
    assign y4_dbg       = y4_w;
    assign y4_valid_dbg = y4_valid_w;

endmodule