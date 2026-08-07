`timescale 1ns / 1ps

//=============================================================
// 文件名       : fir_core_symm_interp2_stage1_mac.v
// 模块名       : fir_core_symm_interp2_stage1_mac
// 功能简述     : 全 2x 结构 Stage 1 的单乘法器时分复用对称 FIR 核。
//                本模块在每次 fir_in_valid 后移入一个补零序列样点，
//                随后用 47 个时钟周期依次完成 46 对对称 tap 和
//                1 个中心 tap 的乘加运算，输出 43bit 全精度结果。
//
//                Stage 1 输出采样间隔为 64 个 5.6448MHz 时钟周期，
//                因此 47 周期 MAC 可以在下一个输入到来前完成。
//
// 当前默认配置：
//                  FIR 长度  ：93 tap
//                  半系数数目：47
//                  系数位宽  ：17bit signed
//                  累加器位宽：43bit signed
//                  插值增益  ：系数已包含 2 倍增益
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-10
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-10：新增 Stage 1 单乘法器时分复用 FIR 核。
//=============================================================

module fir_core_symm_interp2_stage1_mac #(
    parameter integer DATA_W  = 24,
    parameter integer COEFF_W = 17,
    parameter integer ACC_W   = 43,
    parameter integer NTAPS   = 93
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
    localparam integer PROD_W     = DATA_W + 1 + COEFF_W;

    reg signed [DATA_W-1:0]    x_reg [0:NTAPS-1];
    reg signed [COEFF_W-1:0]   coeff_half [0:HALF_COEFF-1];

    reg signed [ACC_W-1:0]     acc_reg;
    reg [5:0]                  mac_idx;
    reg                        busy;

    reg signed [DATA_W:0]      sample_sum_comb;
    reg signed [COEFF_W-1:0]   coeff_comb;

    wire signed [PROD_W-1:0]   product_comb;
    wire signed [ACC_W-1:0]    product_ext;

    integer i;

    initial begin
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

    always @(*) begin
        coeff_comb = coeff_half[mac_idx];

        if (mac_idx < HALF_TAPS) begin
            sample_sum_comb =
                $signed({x_reg[mac_idx][DATA_W-1], x_reg[mac_idx]}) +
                $signed({x_reg[NTAPS-1-mac_idx][DATA_W-1],
                         x_reg[NTAPS-1-mac_idx]});
        end
        else begin
            sample_sum_comb =
                $signed({x_reg[HALF_TAPS][DATA_W-1], x_reg[HALF_TAPS]});
        end
    end

    assign product_comb = sample_sum_comb * coeff_comb;
    assign product_ext = {{(ACC_W-PROD_W){product_comb[PROD_W-1]}},
                          product_comb};

    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < NTAPS; i = i + 1)
                x_reg[i] <= {DATA_W{1'b0}};

            acc_reg       <= {ACC_W{1'b0}};
            mac_idx       <= 6'd0;
            busy          <= 1'b0;
            fir_out_full  <= {ACC_W{1'b0}};
            fir_out_valid <= 1'b0;
        end
        else begin
            fir_out_valid <= 1'b0;

            if (fir_in_valid && !busy) begin
                x_reg[0] <= fir_in;
                for (i = 1; i < NTAPS; i = i + 1)
                    x_reg[i] <= x_reg[i-1];

                acc_reg <= {ACC_W{1'b0}};
                mac_idx <= 6'd0;
                busy    <= 1'b1;
            end
            else if (busy) begin
                if (mac_idx == HALF_TAPS) begin
                    fir_out_full  <= acc_reg + product_ext;
                    fir_out_valid <= 1'b1;
                    busy          <= 1'b0;
                end
                else begin
                    acc_reg <= acc_reg + product_ext;
                    mac_idx <= mac_idx + 6'd1;
                end
            end
        end
    end

endmodule
