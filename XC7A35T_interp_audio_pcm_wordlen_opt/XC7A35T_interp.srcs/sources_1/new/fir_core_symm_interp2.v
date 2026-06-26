`timescale 1ns / 1ps

//=============================================================
// 2x 后级 FIR：No-DSP 版本
// 修改目的：NTAPS2X=29 后，5 个 2x FIR 容易被 Vivado 映射成大量 DSP。
// 本版本保持算法、系数、模块名、端口不变，只用 use_dsp="no" 强制
// 后级 2x FIR 的乘法用 LUT 实现，从而把 DSP 留给 4x MAC2 前级。
//=============================================================
(* use_dsp = "no" *)
module fir_core_symm_interp2_v2 #(
    // parameter DATA_W  = 24,   // 输入数据位宽
    // parameter COEFF_W = 18,   // 系数位宽
    // parameter ACC_W   = 56,   // 累加器位宽
    // parameter NTAPS   = 11    // 2x 后级当前为 11 tap

    // 字长优化后：
    parameter DATA_W  = 24,
    parameter COEFF_W = 14,
    parameter ACC_W   = 45,
    parameter NTAPS   = 29
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire signed [DATA_W-1:0]     fir_in,
    input  wire                         fir_in_valid,

    output reg  signed [ACC_W-1:0]      fir_out_full,
    output reg                          fir_out_valid
);

    //====================================================
    // 对于 11 tap：
    // HALF_TAPS  = (11-1)/2 = 5
    // HALF_COEFF = 6
    //
    // 对称对：
    //   k = 0~4
    // 中心项：
    //   k = 5
    //====================================================
    localparam integer HALF_TAPS  = (NTAPS - 1) / 2;   // 5
    localparam integer HALF_COEFF = HALF_TAPS + 1;     // 6

    // 延时线
    reg signed [DATA_W-1:0] x_reg [0:NTAPS-1];

    // 半系数
    reg signed [COEFF_W-1:0] coeff_half [0:HALF_COEFF-1];

    // 组合累加结果
    reg signed [ACC_W-1:0] acc_comb;

    // valid 延迟 1 拍
    reg fir_in_valid_d;

    integer i;
    integer k;


    initial begin
        coeff_half[0] = 14'sd0;
        coeff_half[1] = 14'sd0;
        coeff_half[2] = 14'sd0;
        coeff_half[3] = -14'sd1;
        coeff_half[4] = 14'sd2;
        coeff_half[5] = 14'sd8;
        coeff_half[6] = -14'sd8;
        coeff_half[7] = -14'sd34;
        coeff_half[8] = 14'sd20;
        coeff_half[9] = 14'sd111;
        coeff_half[10] = -14'sd38;
        coeff_half[11] = -14'sd321;
        coeff_half[12] = 14'sd55;
        coeff_half[13] = 14'sd1261;
        coeff_half[14] = 14'sd1986;

    end

    //====================================================
    // 延时线更新
    //====================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NTAPS; i = i + 1) begin
                x_reg[i] <= {DATA_W{1'b0}};
            end
        end
        else if (fir_in_valid) begin
            x_reg[0] <= fir_in;
            for (i = 1; i < NTAPS; i = i + 1) begin
                x_reg[i] <= x_reg[i-1];
            end
        end
    end

    //====================================================
    // 对称优化后的组合乘加
    //====================================================
    always @(*) begin
        acc_comb = {ACC_W{1'b0}};

        // 5 对对称项
        for (k = 0; k < HALF_TAPS; k = k + 1) begin
            acc_comb = acc_comb
                     + (
                         $signed({x_reg[k][DATA_W-1], x_reg[k]})
                       + $signed({x_reg[NTAPS-1-k][DATA_W-1], x_reg[NTAPS-1-k]})
                       )
                     * $signed(coeff_half[k]);
        end

        // 中心项
        acc_comb = acc_comb
                 + $signed(x_reg[HALF_TAPS]) * $signed(coeff_half[HALF_TAPS]);
    end

    //====================================================
    // 输出寄存
    //====================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fir_out_full   <= {ACC_W{1'b0}};
            fir_out_valid  <= 1'b0;
            fir_in_valid_d <= 1'b0;
        end
        else begin
            fir_in_valid_d <= fir_in_valid;
            fir_out_full   <= acc_comb;
            fir_out_valid  <= fir_in_valid_d;
        end
    end

endmodule