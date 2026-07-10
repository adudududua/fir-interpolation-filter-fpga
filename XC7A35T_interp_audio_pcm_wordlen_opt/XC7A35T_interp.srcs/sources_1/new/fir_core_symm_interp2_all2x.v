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
//                  STAGE_ID=1：101 tap，COEFF_W=18，FRAC_W=16
//                  STAGE_ID=2： 17 tap，COEFF_W=18，FRAC_W=16
//                  STAGE_ID=3： 11 tap，COEFF_W=17，FRAC_W=15
//                  STAGE_ID=4：  7 tap，COEFF_W=18，FRAC_W=16
//                  STAGE_ID=5：  7 tap，COEFF_W=14，FRAC_W=12
//                  STAGE_ID=6：  7 tap，COEFF_W=15，FRAC_W=13
//                  STAGE_ID=7：  7 tap，COEFF_W=14，FRAC_W=12
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-10
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-10：新增全 2x 专用对称 FIR 核。
//=============================================================

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
            coeff_half[0] = 18'sd4;
            coeff_half[1] = 18'sd7;
            coeff_half[2] = -18'sd4;
            coeff_half[3] = -18'sd9;
            coeff_half[4] = 18'sd6;
            coeff_half[5] = 18'sd16;
            coeff_half[6] = -18'sd8;
            coeff_half[7] = -18'sd24;
            coeff_half[8] = 18'sd11;
            coeff_half[9] = 18'sd36;
            coeff_half[10] = -18'sd14;
            coeff_half[11] = -18'sd52;
            coeff_half[12] = 18'sd18;
            coeff_half[13] = 18'sd72;
            coeff_half[14] = -18'sd23;
            coeff_half[15] = -18'sd98;
            coeff_half[16] = 18'sd28;
            coeff_half[17] = 18'sd131;
            coeff_half[18] = -18'sd34;
            coeff_half[19] = -18'sd171;
            coeff_half[20] = 18'sd41;
            coeff_half[21] = 18'sd221;
            coeff_half[22] = -18'sd47;
            coeff_half[23] = -18'sd281;
            coeff_half[24] = 18'sd55;
            coeff_half[25] = 18'sd354;
            coeff_half[26] = -18'sd62;
            coeff_half[27] = -18'sd442;
            coeff_half[28] = 18'sd70;
            coeff_half[29] = 18'sd548;
            coeff_half[30] = -18'sd77;
            coeff_half[31] = -18'sd677;
            coeff_half[32] = 18'sd85;
            coeff_half[33] = 18'sd836;
            coeff_half[34] = -18'sd92;
            coeff_half[35] = -18'sd1033;
            coeff_half[36] = 18'sd99;
            coeff_half[37] = 18'sd1285;
            coeff_half[38] = -18'sd106;
            coeff_half[39] = -18'sd1619;
            coeff_half[40] = 18'sd111;
            coeff_half[41] = 18'sd2086;
            coeff_half[42] = -18'sd116;
            coeff_half[43] = -18'sd2796;
            coeff_half[44] = 18'sd120;
            coeff_half[45] = 18'sd4039;
            coeff_half[46] = -18'sd123;
            coeff_half[47] = -18'sd6873;
            coeff_half[48] = 18'sd124;
            coeff_half[49] = 18'sd20834;
            coeff_half[50] = 18'sd32643;
        end
        else if (STAGE_ID == 2) begin
            coeff_half[0] = -18'sd115;
            coeff_half[1] = -18'sd203;
            coeff_half[2] = 18'sd534;
            coeff_half[3] = 18'sd1233;
            coeff_half[4] = -18'sd1302;
            coeff_half[5] = -18'sd4595;
            coeff_half[6] = 18'sd2116;
            coeff_half[7] = 18'sd19945;
            coeff_half[8] = 18'sd30298;
        end
        else if (STAGE_ID == 3) begin
            coeff_half[0] = 17'sd202;
            coeff_half[1] = -17'sd74;
            coeff_half[2] = -17'sd1636;
            coeff_half[3] = 17'sd261;
            coeff_half[4] = 17'sd9625;
            coeff_half[5] = 17'sd16008;
        end
        else if (STAGE_ID == 4) begin
            coeff_half[0] = -18'sd2061;
            coeff_half[1] = 18'sd116;
            coeff_half[2] = 18'sd18447;
            coeff_half[3] = 18'sd32543;
        end
        else if (STAGE_ID == 5) begin
            coeff_half[0] = -14'sd128;
            coeff_half[1] = 14'sd2;
            coeff_half[2] = 14'sd1152;
            coeff_half[3] = 14'sd2044;
        end
        else if (STAGE_ID == 6) begin
            coeff_half[0] = -15'sd256;
            coeff_half[1] = 15'sd1;
            coeff_half[2] = 15'sd2304;
            coeff_half[3] = 15'sd4094;
        end
        else if (STAGE_ID == 7) begin
            coeff_half[0] = -14'sd128;
            coeff_half[1] = 14'sd0;
            coeff_half[2] = 14'sd1152;
            coeff_half[3] = 14'sd2048;
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
