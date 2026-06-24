`timescale 1ns / 1ps
//=============================================================
// 文件名       : fir_core_symm_interp2.v
// 模块名       : fir_core_symm_interp2_v2
// 功能简述     : 后级 2x 插值 FIR 核心，halfband 13-tap 优化版，
//                shift-add 常数乘法版，不使用 DSP 乘法器。
//
// MATLAB halfband 搜索结果：
//   NTAPS   = 13
//   COEFF_W = 14
//   FRAC_W  = 12
//   beta    = 5.0
//
// 完整 Q12 系数：
//   [0, 39, 0, -240, 0, 1225, 2048,
//    1225, 0, -240, 0, 39, 0]
//
// halfband 对称结构：
//   y = (x1+x11)*39 + (x3+x9)*(-240)
//     + (x5+x7)*1225 + x6*2048
//
// 常数乘法改写为移位加法：
//   39   = 32 + 4 + 2 + 1
//   -240 = 16 - 256
//   1225 = 1024 + 128 + 64 + 8 + 1
//   2048 = 2^11
//
// 这样可以避免 Vivado 将 2x 后级 halfband 常数乘法映射到 DSP48。
// 理论上综合后 DSP 应回到接近 acc_opt 的水平，即主要只保留 4x 前级中的少量 DSP。
//
// 设计作者     : kafeizizi
// 修改建议     : ChatGPT
// 日期         : 2026-06-24
//=============================================================

module fir_core_symm_interp2_v2 #(
    parameter DATA_W  = 24,
    parameter COEFF_W = 14,
    parameter ACC_W   = 45,
    parameter NTAPS   = 13
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire signed [DATA_W-1:0]     fir_in,
    input  wire                         fir_in_valid,

    output reg  signed [ACC_W-1:0]      fir_out_full,
    output reg                          fir_out_valid
);

    //=========================================================
    // 1）固定 13-tap halfband 结构
    //=========================================================
    localparam integer HB_NTAPS = 13;
    localparam integer MID      = 6;

    // 延时线
    reg signed [DATA_W-1:0] x_reg [0:HB_NTAPS-1];

    integer i;

    //=========================================================
    // 2）延时线更新
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < HB_NTAPS; i = i + 1) begin
                x_reg[i] <= {DATA_W{1'b0}};
            end
        end
        else if (fir_in_valid) begin
            x_reg[0] <= fir_in;
            for (i = 1; i < HB_NTAPS; i = i + 1) begin
                x_reg[i] <= x_reg[i-1];
            end
        end
    end

    //=========================================================
    // 3）halfband 对称加法
    //=========================================================
    wire signed [DATA_W:0] sum_1_11;
    wire signed [DATA_W:0] sum_3_9;
    wire signed [DATA_W:0] sum_5_7;

    assign sum_1_11 = $signed({x_reg[1][DATA_W-1],  x_reg[1]})
                    + $signed({x_reg[11][DATA_W-1], x_reg[11]});

    assign sum_3_9  = $signed({x_reg[3][DATA_W-1],  x_reg[3]})
                    + $signed({x_reg[9][DATA_W-1],  x_reg[9]});

    assign sum_5_7  = $signed({x_reg[5][DATA_W-1],  x_reg[5]})
                    + $signed({x_reg[7][DATA_W-1],  x_reg[7]});

    //=========================================================
    // 4）把 25bit 对称和统一扩展到 ACC_W
    //
    // 注意：
    //   这里先扩展再移位，避免不同宽度移位时产生截断。
    //=========================================================
    wire signed [ACC_W-1:0] s1_ext;
    wire signed [ACC_W-1:0] s3_ext;
    wire signed [ACC_W-1:0] s5_ext;
    wire signed [ACC_W-1:0] c_ext;

    assign s1_ext = {{(ACC_W-(DATA_W+1)){sum_1_11[DATA_W]}}, sum_1_11};
    assign s3_ext = {{(ACC_W-(DATA_W+1)){sum_3_9 [DATA_W]}}, sum_3_9 };
    assign s5_ext = {{(ACC_W-(DATA_W+1)){sum_5_7 [DATA_W]}}, sum_5_7 };

    assign c_ext  = {{(ACC_W-DATA_W){x_reg[MID][DATA_W-1]}}, x_reg[MID]};

    //=========================================================
    // 5）shift-add 实现常数乘法
    //
    //   39   = 32 + 4 + 2 + 1
    //   -240 = 16 - 256
    //   1225 = 1024 + 128 + 64 + 8 + 1
    //   2048 = 2^11
    //
    // 下面不出现 '*'，Vivado 不应再为 2x 后级推 DSP。
    //=========================================================
    wire signed [ACC_W-1:0] term_39;
    wire signed [ACC_W-1:0] term_m240;
    wire signed [ACC_W-1:0] term_1225;
    wire signed [ACC_W-1:0] term_2048;

    assign term_39   = (s1_ext <<< 5)
                     + (s1_ext <<< 2)
                     + (s1_ext <<< 1)
                     +  s1_ext;

    assign term_m240 = (s3_ext <<< 4)
                     - (s3_ext <<< 8);

    assign term_1225 = (s5_ext <<< 10)
                     + (s5_ext <<< 7)
                     + (s5_ext <<< 6)
                     + (s5_ext <<< 3)
                     +  s5_ext;

    assign term_2048 = (c_ext <<< 11);

    wire signed [ACC_W-1:0] acc_comb;
    assign acc_comb = term_39
                    + term_m240
                    + term_1225
                    + term_2048;

    // valid 延迟 1 拍
    reg fir_in_valid_d;

    //=========================================================
    // 6）输出寄存
    //=========================================================
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
