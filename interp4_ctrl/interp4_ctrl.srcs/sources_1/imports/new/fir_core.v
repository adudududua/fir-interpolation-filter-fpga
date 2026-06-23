`timescale 1ns / 1ps

module fir_core #(
    parameter DATA_W  = 24,   // 输入数据位宽：24位有符号
    parameter COEFF_W = 18,   // 系数位宽：18位有符号
    parameter ACC_W   = 56,   // 累加器位宽：这里留得比较宽，防止溢出
    parameter NTAPS   = 105   // FIR 抽头数：现在使用 MATLAB 导出的真实系数，共 105 个
)(
    input  wire                         clk,            // 系统时钟
    input  wire                         rst_n,          // 低有效复位

    input  wire signed [DATA_W-1:0]     fir_in,         // 输入给 FIR 的数据
    input  wire                         fir_in_valid,   // 输入数据有效信号

    output reg  signed [ACC_W-1:0]      fir_out_full,   // FIR 全精度输出（尚未截位）
    output reg                          fir_out_valid   // FIR 输出有效信号
);

    //====================================================
    // 1) 延时线寄存器
    //
    // x_reg[0] 存当前输入样本
    // x_reg[1] 存上一个输入样本
    // x_reg[2] 存上上个输入样本
    // ...
    // x_reg[104] 存最老的那个样本
    //
    // 这就是 FIR 最基本的"移位寄存器延时线"结构
    //====================================================
    reg signed [DATA_W-1:0] x_reg [0:NTAPS-1];

    //====================================================
    // 2) 系数存储器
    //
    // coeff[k] 存第 k 个 FIR 系数
    // 这里用的是 MATLAB 导出的 18 位整数定点系数
    //====================================================
    reg signed [COEFF_W-1:0] coeff [0:NTAPS-1];

    //====================================================
    // 3) 组合乘加结果
    //
    // 这个信号表示：
    //   acc_comb = x_reg[0]*coeff[0]
    //            + x_reg[1]*coeff[1]
    //            + ...
    //            + x_reg[104]*coeff[104]
    //
    // 注意：
    // 当前系数是 Q16 定点数，所以这个输出相当于
    // "真实 FIR 输出 × 2^16"
    //====================================================
    reg signed [ACC_W-1:0] acc_comb;

    //====================================================
    // 4) fir_in_valid 延迟一拍
    //
    // 因为 acc_comb 是由当前延时线组合计算出来的，
    // 我们再把它寄存到 fir_out_full，
    // 所以这里让输出 valid 相对输入 valid 延迟 1 个时钟周期
    //====================================================
    reg fir_in_valid_d;

    integer i;
    integer k;

    //====================================================
    // 5) 系数初始化
    //
    // 这些系数由 MATLAB 自动导出：
    //   fir_coeff_for_verilog.txt
    //
    // 系数特点：
    // 1. 总长度 105
    // 2. 左右对称，因此是线性相位 FIR
    // 3. 中心系数 coeff[52] = 65536，表示约 1.0（Q16）
    //====================================================
    initial begin
        coeff[0] = 18'sd0;
        coeff[1] = 18'sd13;
        coeff[2] = 18'sd26;
        coeff[3] = 18'sd25;
        coeff[4] = 18'sd0;
        coeff[5] = -18'sd42;
        coeff[6] = -18'sd74;
        coeff[7] = -18'sd65;
        coeff[8] = 18'sd0;
        coeff[9] = 18'sd97;
        coeff[10] = 18'sd165;
        coeff[11] = 18'sd138;
        coeff[12] = 18'sd0;
        coeff[13] = -18'sd191;
        coeff[14] = -18'sd315;
        coeff[15] = -18'sd258;
        coeff[16] = 18'sd0;
        coeff[17] = 18'sd340;
        coeff[18] = 18'sd549;
        coeff[19] = 18'sd441;
        coeff[20] = 18'sd0;
        coeff[21] = -18'sd564;
        coeff[22] = -18'sd897;
        coeff[23] = -18'sd712;
        coeff[24] = 18'sd0;
        coeff[25] = 18'sd889;
        coeff[26] = 18'sd1400;
        coeff[27] = 18'sd1100;
        coeff[28] = 18'sd0;
        coeff[29] = -18'sd1353;
        coeff[30] = -18'sd2118;
        coeff[31] = -18'sd1656;
        coeff[32] = 18'sd0;
        coeff[33] = 18'sd2021;
        coeff[34] = 18'sd3157;
        coeff[35] = 18'sd2466;
        coeff[36] = 18'sd0;
        coeff[37] = -18'sd3020;
        coeff[38] = -18'sd4737;
        coeff[39] = -18'sd3725;
        coeff[40] = 18'sd0;
        coeff[41] = 18'sd4659;
        coeff[42] = 18'sd7429;
        coeff[43] = 18'sd5968;
        coeff[44] = 18'sd0;
        coeff[45] = -18'sd7964;
        coeff[46] = -18'sd13340;
        coeff[47] = -18'sd11465;
        coeff[48] = 18'sd0;
        coeff[49] = 18'sd19465;
        coeff[50] = 18'sd41530;
        coeff[51] = 18'sd58935;
        coeff[52] = 18'sd65536;
        coeff[53] = 18'sd58935;
        coeff[54] = 18'sd41530;
        coeff[55] = 18'sd19465;
        coeff[56] = 18'sd0;
        coeff[57] = -18'sd11465;
        coeff[58] = -18'sd13340;
        coeff[59] = -18'sd7964;
        coeff[60] = 18'sd0;
        coeff[61] = 18'sd5968;
        coeff[62] = 18'sd7429;
        coeff[63] = 18'sd4659;
        coeff[64] = 18'sd0;
        coeff[65] = -18'sd3725;
        coeff[66] = -18'sd4737;
        coeff[67] = -18'sd3020;
        coeff[68] = 18'sd0;
        coeff[69] = 18'sd2466;
        coeff[70] = 18'sd3157;
        coeff[71] = 18'sd2021;
        coeff[72] = 18'sd0;
        coeff[73] = -18'sd1656;
        coeff[74] = -18'sd2118;
        coeff[75] = -18'sd1353;
        coeff[76] = 18'sd0;
        coeff[77] = 18'sd1100;
        coeff[78] = 18'sd1400;
        coeff[79] = 18'sd889;
        coeff[80] = 18'sd0;
        coeff[81] = -18'sd712;
        coeff[82] = -18'sd897;
        coeff[83] = -18'sd564;
        coeff[84] = 18'sd0;
        coeff[85] = 18'sd441;
        coeff[86] = 18'sd549;
        coeff[87] = 18'sd340;
        coeff[88] = 18'sd0;
        coeff[89] = -18'sd258;
        coeff[90] = -18'sd315;
        coeff[91] = -18'sd191;
        coeff[92] = 18'sd0;
        coeff[93] = 18'sd138;
        coeff[94] = 18'sd165;
        coeff[95] = 18'sd97;
        coeff[96] = 18'sd0;
        coeff[97] = -18'sd65;
        coeff[98] = -18'sd74;
        coeff[99] = -18'sd42;
        coeff[100] = 18'sd0;
        coeff[101] = 18'sd25;
        coeff[102] = 18'sd26;
        coeff[103] = 18'sd13;
        coeff[104] = 18'sd0;
    end

    //====================================================
    // 6) 延时线更新
    //
    // 每来一个有效输入样本，就把整个延时线向后推一格：
    //
    //   x_reg[0] <= fir_in
    //   x_reg[1] <= x_reg[0]
    //   x_reg[2] <= x_reg[1]
    //   ...
    //
    // 这样 x_reg[] 中就始终保存"最近 105 个输入样本"
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
    // 7) 组合乘加
    //
    // 计算：
    //   acc_comb = Σ x_reg[k] * coeff[k]
    //
    // 注意：
    // 这里是"组合逻辑乘加"，结构最直观，便于学习和仿真
    // 后面如果要做资源优化，可以再改成：
    //   - 对称系数优化
    //   - 多相结构
    //   - 时分复用乘法器
    //====================================================
    always @(*) begin
        acc_comb = {ACC_W{1'b0}};
        for (k = 0; k < NTAPS; k = k + 1) begin
            acc_comb = acc_comb + $signed(x_reg[k]) * $signed(coeff[k]);
        end
    end

    //====================================================
    // 8) 输出寄存
    //
    // 把组合乘加结果寄存起来，形成同步输出
    // fir_out_valid 相对于 fir_in_valid 延迟 1 个时钟
    //====================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fir_out_full  <= {ACC_W{1'b0}};
            fir_out_valid <= 1'b0;
            fir_in_valid_d <= 1'b0;
        end
        else begin
            fir_in_valid_d <= fir_in_valid;
            fir_out_full   <= acc_comb;
            fir_out_valid  <= fir_in_valid_d;
        end
    end

endmodule