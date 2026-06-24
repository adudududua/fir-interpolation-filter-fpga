`timescale 1ns / 1ps

module fir_core_symm_interp2_v2 #(
    // parameter DATA_W  = 24,   // 输入数据位宽
    // parameter COEFF_W = 18,   // 系数位宽
    // parameter ACC_W   = 45,   // 累加器位宽
    // parameter NTAPS   = 29    // 2x 后级当前为 11 tap

    // acc_opt 稳定版参数：
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
    // 对于 29 tap acc_opt 后级 2x FIR：
    //   HALF_TAPS  = (29-1)/2 = 14
    //   HALF_COEFF = 15
    //
    // 对称项：
    //   k = 0 ~ HALF_TAPS-1
    // 中心项：
    //   k = HALF_TAPS
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

    //====================================================
    // 系数初始化
    //
    // 请把 MATLAB 生成文件：
    //   interp2_coeff_half_for_verilog.txt
    // 中的 15 行 coeff_half[...] 赋值语句
    // 直接粘贴到下面 initial begin ... end 里
    //
    // 你最后应看到：
    //   coeff_half[0] = ...
    //   coeff_half[1] = ...
    //   ...
    //   coeff_half[14] = ...
    //====================================================
    initial begin
        // coeff_half[0] = 18'sd420;
        // coeff_half[1] = -18'sd59;
        // coeff_half[2] = -18'sd3310;
        // coeff_half[3] = 18'sd208;
        // coeff_half[4] = 18'sd19273;
        // coeff_half[5] = 18'sd32470;

        // =====================================================
        // 2x FIR word-length optimized half coefficients
        // 阶数 n     : 28
        // tap 数     : 29
        // 系数位宽   : 14 bit
        // 小数位宽   : 12 bit
        // 裁剪阈值   : 0
        // 半系数总数 : 15
        // =====================================================
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

        // HALF_TAPS 对对称项
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