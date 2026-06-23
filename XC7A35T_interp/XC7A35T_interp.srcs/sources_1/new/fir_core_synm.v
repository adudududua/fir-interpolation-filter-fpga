`timescale 1ns / 1ps

module fir_core_symm #(
    parameter DATA_W  = 24,   // 输入数据位宽：24 位有符号
    parameter COEFF_W = 18,   // 系数位宽：18 位有符号
    parameter ACC_W   = 56,   // 累加器位宽：留宽一些，防止溢出
    parameter NTAPS   = 155   // FIR 抽头数：最终公共双模式版为 155 tap
)(
    input  wire                         clk,            // 系统时钟
    input  wire                         rst_n,          // 低有效复位

    input  wire signed [DATA_W-1:0]     fir_in,         // 输入给 FIR 的数据
    input  wire                         fir_in_valid,   // 输入数据有效信号

    output reg  signed [ACC_W-1:0]      fir_out_full,   // FIR 全精度输出（Q16 大位宽）
    output reg                          fir_out_valid   // 输出有效信号
);

    //====================================================
    // 1) 本模块内部用到的关键参数
    //
    // 对于奇数长度线性相位 FIR：
    //   NTAPS = 155
    //   HALF_TAPS = (155-1)/2 = 77
    //
    // 含义：
    //   - 对称对数 = 77 对
    //   - 中心抽头索引 = 77
    //   - 需要保存的半系数数 = 78 个（0~77）
    //====================================================
    localparam integer HALF_TAPS  = (NTAPS - 1) / 2;   // 77
    localparam integer HALF_COEFF = HALF_TAPS + 1;     // 78

    //====================================================
    // 2) 延时线寄存器
    //
    // x_reg[0]         : 当前输入样本
    // x_reg[1]         : 上一个输入样本
    // ...
    // x_reg[NTAPS-1]   : 最老的样本
    //====================================================
    reg signed [DATA_W-1:0] x_reg [0:NTAPS-1];

    //====================================================
    // 3) 半系数存储
    //
    // 因为 FIR 系数对称：
    //   h[k] = h[NTAPS-1-k]
    //
    // 所以只需要保存：
    //   coeff_half[0] ~ coeff_half[HALF_TAPS-1] : 对称对前半部分
    //   coeff_half[HALF_TAPS]                   : 中心系数
    //
    // 对于 155 tap：
    //   coeff_half[0:77]
    //====================================================
    reg signed [COEFF_W-1:0] coeff_half [0:HALF_COEFF-1];

    //====================================================
    // 4) 组合累加结果
    //
    // 对称优化后的公式：
    //
    // y[n] = Σ_{k=0}^{HALF_TAPS-1} h[k] * (x[n-k] + x[n-(NTAPS-1-k)])
    //      + h[HALF_TAPS] * x[n-HALF_TAPS]
    //
    // 对于 155 tap：
    // y[n] = Σ_{k=0}^{76} h[k] * (x[n-k] + x[n-(154-k)])
    //      + h[77] * x[n-77]
    //====================================================
    reg signed [ACC_W-1:0] acc_comb;

    //====================================================
    // 5) fir_in_valid 延迟一拍
    //====================================================
    reg fir_in_valid_d;

    integer i;
    integer k;

    //====================================================
    // 6) 系数初始化
    //
    // 这里不要手工再改，直接把 MATLAB 导出的
    // fir_coeff_half_for_verilog_v2.txt
    // 中的内容粘贴到 initial begin ... end 里即可。
    //
    // 注意：
    // 现在应当有 78 个系数：
    //   coeff_half[0]  ~ coeff_half[77]
    //====================================================
    initial begin
        // =====================================================
        // MATLAB 自动生成的对称优化 FIR 半系数赋值语句（公共双模式版）
        // 系数位宽: 18 bit
        // 小数位宽: 16 bit
        // 半系数总数: 78
        // =====================================================
        coeff_half[0] = 18'sd13;
        coeff_half[1] = 18'sd16;
        coeff_half[2] = 18'sd16;
        coeff_half[3] = 18'sd8;
        coeff_half[4] = -18'sd8;
        coeff_half[5] = -18'sd24;
        coeff_half[6] = -18'sd32;
        coeff_half[7] = -18'sd26;
        coeff_half[8] = -18'sd7;
        coeff_half[9] = 18'sd17;
        coeff_half[10] = 18'sd32;
        coeff_half[11] = 18'sd27;
        coeff_half[12] = 18'sd1;
        coeff_half[13] = -18'sd33;
        coeff_half[14] = -18'sd55;
        coeff_half[15] = -18'sd49;
        coeff_half[16] = -18'sd14;
        coeff_half[17] = 18'sd35;
        coeff_half[18] = 18'sd69;
        coeff_half[19] = 18'sd65;
        coeff_half[20] = 18'sd19;
        coeff_half[21] = -18'sd48;
        coeff_half[22] = -18'sd97;
        coeff_half[23] = -18'sd95;
        coeff_half[24] = -18'sd35;
        coeff_half[25] = 18'sd55;
        coeff_half[26] = 18'sd124;
        coeff_half[27] = 18'sd126;
        coeff_half[28] = 18'sd51;
        coeff_half[29] = -18'sd67;
        coeff_half[30] = -18'sd161;
        coeff_half[31] = -18'sd170;
        coeff_half[32] = -18'sd76;
        coeff_half[33] = 18'sd77;
        coeff_half[34] = 18'sd203;
        coeff_half[35] = 18'sd221;
        coeff_half[36] = 18'sd106;
        coeff_half[37] = -18'sd89;
        coeff_half[38] = -18'sd255;
        coeff_half[39] = -18'sd286;
        coeff_half[40] = -18'sd147;
        coeff_half[41] = 18'sd99;
        coeff_half[42] = 18'sd316;
        coeff_half[43] = 18'sd367;
        coeff_half[44] = 18'sd199;
        coeff_half[45] = -18'sd111;
        coeff_half[46] = -18'sd391;
        coeff_half[47] = -18'sd468;
        coeff_half[48] = -18'sd268;
        coeff_half[49] = 18'sd121;
        coeff_half[50] = 18'sd484;
        coeff_half[51] = 18'sd597;
        coeff_half[52] = 18'sd359;
        coeff_half[53] = -18'sd131;
        coeff_half[54] = -18'sd604;
        coeff_half[55] = -18'sd769;
        coeff_half[56] = -18'sd483;
        coeff_half[57] = 18'sd139;
        coeff_half[58] = 18'sd764;
        coeff_half[59] = 18'sd1008;
        coeff_half[60] = 18'sd664;
        coeff_half[61] = -18'sd147;
        coeff_half[62] = -18'sd998;
        coeff_half[63] = -18'sd1370;
        coeff_half[64] = -18'sd948;
        coeff_half[65] = 18'sd153;
        coeff_half[66] = 18'sd1382;
        coeff_half[67] = 18'sd1999;
        coeff_half[68] = 18'sd1473;
        coeff_half[69] = -18'sd157;
        coeff_half[70] = -18'sd2176;
        coeff_half[71] = -18'sd3424;
        coeff_half[72] = -18'sd2806;
        coeff_half[73] = 18'sd160;
        coeff_half[74] = 18'sd5012;
        coeff_half[75] = 18'sd10413;
        coeff_half[76] = 18'sd14631;
        coeff_half[77] = 18'sd16223;
    end

    //====================================================
    // 7) 延时线更新
    //
    // 每来一个有效输入样本，就把延时线整体后移一格
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
    // 8) 对称优化后的组合乘加
    //
    // 关键点：
    //   先把一对对称输入相加（注意要扩 1 位防止加法溢出）
    //   再乘一次对应系数
    //====================================================
    always @(*) begin
        acc_comb = {ACC_W{1'b0}};

        // 对称项：k = 0 ~ HALF_TAPS-1
        for (k = 0; k < HALF_TAPS; k = k + 1) begin
            acc_comb = acc_comb
                     + (
                         $signed({x_reg[k][DATA_W-1], x_reg[k]})
                       + $signed({x_reg[NTAPS-1-k][DATA_W-1], x_reg[NTAPS-1-k]})
                       )
                     * $signed(coeff_half[k]);
        end

        // 中心项：coeff_half[HALF_TAPS] * x_reg[HALF_TAPS]
        acc_comb = acc_comb
                 + $signed(x_reg[HALF_TAPS]) * $signed(coeff_half[HALF_TAPS]);
    end

    //====================================================
    // 9) 输出寄存
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
`default_nettype wire