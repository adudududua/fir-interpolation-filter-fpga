`timescale 1ns / 1ps

//=============================================================
// 文件名       : audio_rate_ce_gen.v
// 模块名       : audio_rate_ce_gen
// 功能简述     : 基于 50MHz 系统时钟，通过 32bit 相位累加器
//                产生赛题正式采样率所需的多级 CE 使能脉冲。
//                支持 48kHz 家族和 44.1kHz 家族：
//                48kHz 家族：ce128_out 平均频率为 6.144MHz，
//                           原始输入采样率为 48kHz。
//                44.1kHz 家族：ce128_out 平均频率为 5.6448MHz，
//                             原始输入采样率为 44.1kHz。
// 设计作者     : 
// 创建日期     : 2026-05-16
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
// V1.0 初始版本 完成基础逻辑编写
//=============================================================

module audio_rate_ce_gen (
    input  wire       clk,             // 50MHz 系统时钟
    input  wire       rst_n,           // 低有效复位

    input  wire       rate_sel_48k,    // 采样率选择：1=48kHz 家族，0=44.1kHz 家族

    output reg        ce4_out,         // 4x 输出采样使能：48k 家族为 192kHz，44.1k 家族为 176.4kHz
    output reg        ce8_out,         // 8x 输出采样使能：48k 家族为 384kHz，44.1k 家族为 352.8kHz
    output reg        ce16_out,        // 16x 输出采样使能
    output reg        ce32_out,        // 32x 输出采样使能
    output reg        ce64_out,        // 64x 输出采样使能
    output reg        ce128_out,       // 128x 输出采样使能：48k 家族为 6.144MHz，44.1k 家族为 5.6448MHz

    output reg        x_in_update_ce,  // 原始输入样本更新使能：48kHz 或 44.1kHz

    output reg [6:0]  ce128_phase_dbg  // 调试信号：当前 ce128 计数相位，范围 0~127
);

    //=========================================================
    // 1）定义相位累加器步进值
    //
    // 本模块使用 32bit 相位累加器产生分数频率 CE。
    //
    // 基本原理：
    //   每个 50MHz 系统时钟周期，相位累加器加上一个固定步进值。
    //   当加法结果产生溢出时，说明“目标采样时刻”到来，
    //   此时输出一个 ce128_out 单周期脉冲。
    //
    // 步进值计算公式：
    //   PHASE_INC = round(目标频率 / 50MHz * 2^32)
    //
    // 对 48kHz 家族：
    //   目标 ce128_out 频率 = 48kHz * 128 = 6.144MHz
    //   PHASE_INC_48K = round(6.144MHz / 50MHz * 2^32)
    //                  = 32'h1F75104D
    //
    // 对 44.1kHz 家族：
    //   目标 ce128_out 频率 = 44.1kHz * 128 = 5.6448MHz
    //   PHASE_INC_44K1 = round(5.6448MHz / 50MHz * 2^32)
    //                   = 32'h1CE6C094
    //
    // 注意：
    //   ce128_out 是单周期 CE 脉冲，不是连续 50% 占空比时钟。
    //=========================================================
    localparam [31:0] PHASE_INC_48K  = 32'h1F75104D;
    localparam [31:0] PHASE_INC_44K1 = 32'h1CE6C094;

    reg  [31:0] phase_acc;
    reg  [6:0]  ce128_cnt;

    wire [31:0] phase_inc;
    wire [32:0] phase_sum;
    wire        phase_overflow;

    assign phase_inc      = rate_sel_48k ? PHASE_INC_48K : PHASE_INC_44K1;
    assign phase_sum      = {1'b0, phase_acc} + {1'b0, phase_inc};
    assign phase_overflow = phase_sum[32];

    //=========================================================
    // 2）产生 ce128_out 基础采样使能
    //
    // ce128_out 是所有后续 CE 的基础。
    //
    // 当 phase_sum[32] = 1 时，表示相位累加器发生溢出，
    // 本时钟周期输出一个 ce128_out 脉冲。
    //
    // 平均频率：
    //   rate_sel_48k = 1 时，ce128_out ≈ 6.144MHz
    //   rate_sel_48k = 0 时，ce128_out ≈ 5.6448MHz
    //
    // 由于 6.144MHz / 5.6448MHz 不能被 50MHz 整数分频得到，
    // 所以 ce128_out 的相邻脉冲间隔不是完全固定的。
    // 例如 48kHz 家族下，脉冲间隔大约会在 8 个和 9 个
    // 50MHz 时钟周期之间跳变，但长期平均频率非常接近目标值。
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_acc       <= 32'd0;
            ce128_cnt       <= 7'd0;
            ce128_phase_dbg <= 7'd0;

            ce4_out         <= 1'b0;
            ce8_out         <= 1'b0;
            ce16_out        <= 1'b0;
            ce32_out        <= 1'b0;
            ce64_out        <= 1'b0;
            ce128_out       <= 1'b0;
            x_in_update_ce  <= 1'b0;
        end
        else begin
            phase_acc <= phase_sum[31:0];

            ce4_out        <= 1'b0;
            ce8_out        <= 1'b0;
            ce16_out       <= 1'b0;
            ce32_out       <= 1'b0;
            ce64_out       <= 1'b0;
            ce128_out      <= 1'b0;
            x_in_update_ce <= 1'b0;

            if (phase_overflow) begin
                ce128_out <= 1'b1;

                ce64_out  <= (ce128_cnt[0]   == 1'b0);
                ce32_out  <= (ce128_cnt[1:0] == 2'b00);
                ce16_out  <= (ce128_cnt[2:0] == 3'b000);
                ce8_out   <= (ce128_cnt[3:0] == 4'b0000);
                ce4_out   <= (ce128_cnt[4:0] == 5'b00000);

                x_in_update_ce <= (ce128_cnt == 7'd127);

                ce128_phase_dbg <= ce128_cnt;
                ce128_cnt       <= ce128_cnt + 7'd1;
            end
        end
    end

    //=========================================================
    // 3）各级 CE 频率关系说明
    //
    // 本模块中各级 CE 均由 ce128_out 分频得到。
    //
    // 当 rate_sel_48k = 1 时：
    //   ce128_out      ≈ 6.144MHz
    //   ce64_out       ≈ 3.072MHz
    //   ce32_out       ≈ 1.536MHz
    //   ce16_out       ≈ 768kHz
    //   ce8_out        ≈ 384kHz
    //   ce4_out        ≈ 192kHz
    //   x_in_update_ce ≈ 48kHz
    //
    // 当 rate_sel_48k = 0 时：
    //   ce128_out      ≈ 5.6448MHz
    //   ce64_out       ≈ 2.8224MHz
    //   ce32_out       ≈ 1.4112MHz
    //   ce16_out       ≈ 705.6kHz
    //   ce8_out        ≈ 352.8kHz
    //   ce4_out        ≈ 176.4kHz
    //   x_in_update_ce ≈ 44.1kHz
    //
    // ce128_phase_dbg 用于调试：
    //   它记录当前 ce128_out 属于 0~127 中的哪一个相位。
    //   当 ce128_phase_dbg = 127 时，下一次原始输入样本将被更新。
    //=========================================================

endmodule
