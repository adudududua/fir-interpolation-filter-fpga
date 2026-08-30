`timescale 1ns / 1ps

//=============================================================
// 文件名       : fir_core_symm_interp2_all2x.v
// 模块名       : fir_core_symm_interp2_all2x
// 功能简述     : 全 2x 结构 128 倍插值链路的对称 FIR 核。
//                本模块用于 44.1kHz -> 5.6448MHz 专用优化方案，
//                通过 STAGE_ID 选择 7 个 2x 插值级中的对应系数。
//
//                当前版本以功能正确和 RTL/MATLAB 对拍为优先目标，
//                每一级采用直接对称乘加结构实现。后续若需要进一步
//                优化资源，可在通过功能验证后改为时分复用 MAC 结构。
//
//                当前默认配置：
//                  STAGE_ID=1： 93 tap，COEFF_W=17，FRAC_W=16
//                  STAGE_ID=2： 17 tap，COEFF_W=16，FRAC_W=15
//                  STAGE_ID=3： 11 tap，COEFF_W=15，FRAC_W=14
//                  STAGE_ID=4：  7 tap，COEFF_W=16，FRAC_W=15
//                  STAGE_ID=5：  7 tap，COEFF_W=14，FRAC_W=13
//                  STAGE_ID=6：  7 tap，COEFF_W=13，FRAC_W=12
//                  STAGE_ID=7：  7 tap，COEFF_W=14，FRAC_W=12
//                  所有系数均已包含 2 倍插值增益。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-10
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-10：新增全 2x 专用对称 FIR 核。
//                2026-07-10：同步 MATLAB bit-true 验证通过的新系数。
//                2026-07-10：Stage 2～7 常数乘法映射到 LUT，DSP 仅保留
//                            给 Stage 1 时分复用 MAC 使用。
//=============================================================

(* use_dsp = "no" *)
module fir_core_symm_interp2_all2x #(
    parameter integer STAGE_ID = 1,
    parameter integer DATA_W   = 24,
    parameter integer COEFF_W  = 18,
    parameter integer ACC_W    = 56,
    parameter integer NTAPS    = 101
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire signed [DATA_W-1:0]     fir_in,
    input  wire                         fir_in_valid,

    output reg  signed [ACC_W-1:0]      fir_out_full,
    output reg                          fir_out_valid
);

    localparam integer HALF_TAPS  = (NTAPS - 1) / 2;
    localparam integer HALF_COEFF = HALF_TAPS + 1;

    reg signed [DATA_W-1:0]  x_reg [0:NTAPS-1];
    reg signed [COEFF_W-1:0] coeff_half [0:HALF_COEFF-1];

    reg signed [ACC_W-1:0] acc_comb;
    reg                    fir_in_valid_d;

    integer i;
    integer k;

    initial begin
        for (i = 0; i < HALF_COEFF; i = i + 1) begin
            coeff_half[i] = {COEFF_W{1'b0}};
        end

        if (STAGE_ID == 1) begin
            coeff_half[0] = 17'sd14;
            coeff_half[1] = 17'sd24;
            coeff_half[2] = -17'sd14;
            coeff_half[3] = -17'sd31;
            coeff_half[4] = 17'sd18;
            coeff_half[5] = 17'sd52;
            coeff_half[6] = -17'sd25;
            coeff_half[7] = -17'sd79;
            coeff_half[8] = 17'sd33;
            coeff_half[9] = 17'sd115;
            coeff_half[10] = -17'sd43;
            coeff_half[11] = -17'sd163;
            coeff_half[12] = 17'sd54;
            coeff_half[13] = 17'sd224;
            coeff_half[14] = -17'sd67;
            coeff_half[15] = -17'sd301;
            coeff_half[16] = 17'sd81;
            coeff_half[17] = 17'sd396;
            coeff_half[18] = -17'sd96;
            coeff_half[19] = -17'sd513;
            coeff_half[20] = 17'sd111;
            coeff_half[21] = 17'sd657;
            coeff_half[22] = -17'sd128;
            coeff_half[23] = -17'sd831;
            coeff_half[24] = 17'sd145;
            coeff_half[25] = 17'sd1044;
            coeff_half[26] = -17'sd163;
            coeff_half[27] = -17'sd1303;
            coeff_half[28] = 17'sd180;
            coeff_half[29] = 17'sd1621;
            coeff_half[30] = -17'sd196;
            coeff_half[31] = -17'sd2018;
            coeff_half[32] = 17'sd212;
            coeff_half[33] = 17'sd2526;
            coeff_half[34] = -17'sd227;
            coeff_half[35] = -17'sd3198;
            coeff_half[36] = 17'sd239;
            coeff_half[37] = 17'sd4137;
            coeff_half[38] = -17'sd250;
            coeff_half[39] = -17'sd5565;
            coeff_half[40] = 17'sd259;
            coeff_half[41] = 17'sd8058;
            coeff_half[42] = -17'sd266;
            coeff_half[43] = -17'sd13734;
            coeff_half[44] = 17'sd270;
            coeff_half[45] = 17'sd41663;
            coeff_half[46] = 17'sd65265;
        end
        else if (STAGE_ID == 2) begin
            coeff_half[0] = -16'sd115;
            coeff_half[1] = -16'sd203;
            coeff_half[2] = 16'sd534;
            coeff_half[3] = 16'sd1233;
            coeff_half[4] = -16'sd1302;
            coeff_half[5] = -16'sd4595;
            coeff_half[6] = 16'sd2116;
            coeff_half[7] = 16'sd19945;
            coeff_half[8] = 16'sd30298;
        end
        else if (STAGE_ID == 3) begin
            coeff_half[0] = 15'sd202;
            coeff_half[1] = -15'sd74;
            coeff_half[2] = -15'sd1636;
            coeff_half[3] = 15'sd261;
            coeff_half[4] = 15'sd9625;
            coeff_half[5] = 15'sd16008;
        end
        else if (STAGE_ID == 4) begin
            coeff_half[0] = -16'sd2061;
            coeff_half[1] = 16'sd116;
            coeff_half[2] = 16'sd18447;
            coeff_half[3] = 16'sd32543;
        end
        else if (STAGE_ID == 5) begin
            coeff_half[0] = -14'sd513;
            coeff_half[1] = 14'sd7;
            coeff_half[2] = 14'sd4609;
            coeff_half[3] = 14'sd8178;
        end
        else if (STAGE_ID == 6) begin
            coeff_half[0] = -13'sd256;
            coeff_half[1] = 13'sd1;
            coeff_half[2] = 13'sd2304;
            coeff_half[3] = 13'sd4094;
        end
        else if (STAGE_ID == 7) begin
            coeff_half[0] = -14'sd256;
            coeff_half[1] = 14'sd0;
            coeff_half[2] = 14'sd2304;
            coeff_half[3] = 14'sd4096;
        end
    end

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

    always @(*) begin
        acc_comb = {ACC_W{1'b0}};

        for (k = 0; k < HALF_TAPS; k = k + 1) begin
            acc_comb = acc_comb
                     + (
                         $signed({x_reg[k][DATA_W-1], x_reg[k]})
                       + $signed({x_reg[NTAPS-1-k][DATA_W-1], x_reg[NTAPS-1-k]})
                       )
                     * $signed(coeff_half[k]);
        end

        acc_comb = acc_comb
                 + $signed(x_reg[HALF_TAPS]) * $signed(coeff_half[HALF_TAPS]);
    end

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
