`timescale 1ns / 1ps

//=============================================================
// 文件名       : board_demo_audio_ce_test_top.v
// 模块名       : board_demo_audio_ce_test_top
// 功能简述     : 正式采样率 CE 发生器的板级测试顶层，
//                用于单独验证 audio_rate_ce_gen 是否能从 50MHz
//                系统时钟产生 48k 家族的 6.144MHz / 384kHz /
//                192kHz / 48kHz 等采样使能脉冲。
// 设计作者     : kafeizizi
// 创建日期     : 2026-05-16
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//=============================================================

module board_demo_audio_ce_test_top (
    input  wire       clk,       // 板载 50MHz 系统时钟
    input  wire       rst_n,     // 低有效复位

    output wire       dac_clk,   // 临时调试输出：接 ce128_out，不是真正 50% 占空比 DAC 时钟
    output wire [7:0] dac_data,  // 临时调试输出：接不同倍率的 CE 脉冲
    output wire [1:0] mode_led   // 临时调试输出：慢速闪烁，用来确认逻辑在运行
);

    //=========================================================
    // 1）声明 CE 发生器输出信号
    //
    // ce128_out：
    //   128x 输出节拍。
    //   在 48k 家族下，平均频率应该是 6.144MHz。
    //
    // ce8_out：
    //   8x 输出节拍。
    //   如果 ce128_out = 6.144MHz，则 ce8_out = 384kHz。
    //
    // ce4_out：
    //   4x 输出节拍。
    //   如果 ce128_out = 6.144MHz，则 ce4_out = 192kHz。
    //
    // x_in_update_ce：
    //   原始输入样本更新节拍。
    //   如果 ce128_out = 6.144MHz，则它对应 48kHz 输入节拍。
    //=========================================================
    wire ce4_out;
    wire ce8_out;
    wire ce16_out;
    wire ce32_out;
    wire ce64_out;
    wire ce128_out;
    wire x_in_update_ce;
    wire [6:0] ce128_phase_dbg;

    //=========================================================
    // 2）实例化正式采样率 CE 发生器
    //
    // rate_sel_48k = 1'b1：
    //   选择 48k 家族。
    //
    // 对应关系：
    //   输入采样率目标 = 48kHz
    //   4x  输出目标  = 192kHz
    //   8x  输出目标  = 384kHz
    //   128x 输出目标 = 6.144MHz
    //
    // 后续如果需要测试 44.1k 家族，
    // 只需要把 rate_sel_48k 改成 1'b0。
    //=========================================================
    audio_rate_ce_gen u_audio_rate_ce_gen (
        .clk             (clk),
        .rst_n           (rst_n),

        .rate_sel_48k    (1'b1),

        .ce4_out         (ce4_out),
        .ce8_out         (ce8_out),
        .ce16_out        (ce16_out),
        .ce32_out        (ce32_out),
        .ce64_out        (ce64_out),
        .ce128_out       (ce128_out),
        .x_in_update_ce  (x_in_update_ce),
        .ce128_phase_dbg (ce128_phase_dbg)
    );

    //=========================================================
    // 3）对 ce128_out 做慢速分频
    //
    // ce128_out 在 48k 家族下平均频率约为 6.144MHz。
    //
    // ce128_div_cnt 每收到一个 ce128_out 脉冲加 1。
    //
    // ce128_div_cnt[21] 翻转频率约为：
    //   6.144MHz / 2^22 ≈ 1.4648Hz
    //
    // ce128_div_cnt[20] 翻转频率约为：
    //   6.144MHz / 2^21 ≈ 2.9297Hz
    //
    // 这两个信号会接到 mode_led 上，
    // 方便用肉眼确认 CE 发生器已经在运行。
    //=========================================================
    reg [23:0] ce128_div_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ce128_div_cnt <= 24'd0;
        else if (ce128_out)
            ce128_div_cnt <= ce128_div_cnt + 24'd1;
    end

    //=========================================================
    // 4）把 CE 信号临时映射到 DAC 管脚
    //
    // 注意：
    //   当前版本不是给 DA9708 输出模拟波形。
    //   这里借用 dac_clk / dac_data[7:0] 作为示波器调试口。
    //
    // 映射关系：
    //   dac_clk     -> ce128_out，平均约 6.144MHz 窄脉冲
    //   dac_data[0] -> ce4_out，平均约 192kHz
    //   dac_data[1] -> ce8_out，平均约 384kHz
    //   dac_data[2] -> ce16_out，平均约 768kHz
    //   dac_data[3] -> ce32_out，平均约 1.536MHz
    //   dac_data[4] -> ce64_out，平均约 3.072MHz
    //   dac_data[5] -> x_in_update_ce，平均约 48kHz
    //   dac_data[6] -> ce128_div_cnt[21]，约 1.4648Hz 慢速翻转
    //   dac_data[7] -> ce128_div_cnt[20]，约 2.9297Hz 慢速翻转
    //=========================================================
    assign dac_clk     = ce128_out;

    assign dac_data[0] = ce4_out;
    assign dac_data[1] = ce8_out;
    assign dac_data[2] = ce16_out;
    assign dac_data[3] = ce32_out;
    assign dac_data[4] = ce64_out;
    assign dac_data[5] = x_in_update_ce;
    assign dac_data[6] = ce128_div_cnt[21];
    assign dac_data[7] = ce128_div_cnt[20];

    //=========================================================
    // 5）LED 慢闪状态显示
    //
    // mode_led[0]：
    //   接 ce128_div_cnt[21]，约 1.4648Hz 翻转。
    //
    // mode_led[1]：
    //   接 ce128_div_cnt[20]，约 2.9297Hz 翻转。
    //
    // 如果两个 LED 能够慢速闪烁，说明：
    //   clk / rst_n 正常
    //   audio_rate_ce_gen 正常运行
    //   ce128_out 正在产生
    //=========================================================
    assign mode_led[0] = ce128_div_cnt[21];
    assign mode_led[1] = ce128_div_cnt[20];

endmodule
