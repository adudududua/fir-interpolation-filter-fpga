`timescale 1ns / 1ps

//=============================================================
// 文件名       : board_demo_audio_mmcm_clk_test_top.v
// 模块名       : board_demo_audio_mmcm_clk_test_top
// 功能简述     : MMCM 音频时钟测试顶层。
//                用于单独验证 clk_wiz_audio_48k 是否能从
//                50MHz 系统时钟产生接近 6.144MHz 的连续
//                128x 音频时钟，并通过分频信号观察 384kHz、
//                192kHz、48kHz 等频率。
// 设计作者     : kafeizizi
// 创建日期     : 2026-05-17
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
// 其他描述     :
//=============================================================

module board_demo_audio_mmcm_clk_test_top (
    input  wire       clk,       // 板载 50MHz 系统时钟
    input  wire       rst_n,     // 低有效复位

    input  wire       sw0,       // 当前测试顶层暂时不用
    input  wire       sw1,       // 当前测试顶层暂时不用
    input  wire       sw2,       // 当前测试顶层暂时不用

    output wire       dac_clk,   // 输出 6.144MHz 连续时钟
    output wire [7:0] dac_data   // 输出若干分频测试信号
);

    //=========================================================
    // 1）实例化 48kHz 家族 MMCM
    //
    // clk_wiz_audio_48k 的作用：
    //   输入  50MHz 系统时钟。
    //   输出  6.144MHz 连续时钟。
    //
    // 6.144MHz 的来源：
    //   48kHz * 128 = 6.144MHz。
    //
    // reset：
    //   Clocking Wizard 默认 reset 通常是高有效，
    //   所以这里接 ~rst_n。
    //
    // locked：
    //   locked=1 表示 MMCM 已经锁定，输出时钟稳定。
    //=========================================================
    wire clk_audio_128x;
    wire mmcm_locked;

    clk_wiz_audio_48k u_clk_wiz_audio_48k (
        .clk_out1 (clk_audio_128x),
        .reset    (~rst_n),
        .locked   (mmcm_locked),
        .clk_in1  (clk)
    );

    //=========================================================
    // 2）在 6.144MHz 时钟域下做简单分频
    //
    // div_cnt 每来一个 6.144MHz 时钟加 1。
    //
    // 对二进制计数器来说：
    //   div_cnt[3] = 6.144MHz / 16  = 384kHz
    //   div_cnt[4] = 6.144MHz / 32  = 192kHz
    //   div_cnt[6] = 6.144MHz / 128 = 48kHz
    //
    // 这些信号用于示波器验证 MMCM 输出频率是否正确。
    //=========================================================
    reg [7:0] div_cnt;

    always @(posedge clk_audio_128x or negedge rst_n) begin
        if (!rst_n)
            div_cnt <= 8'd0;
        else if (!mmcm_locked)
            div_cnt <= 8'd0;
        else
            div_cnt <= div_cnt + 8'd1;
    end

    //=========================================================
    // 3）输出到原 DAC 管脚做示波器观察
    //
    // dac_clk：
    //   直接输出 MMCM 产生的 6.144MHz 连续时钟。
    //
    // dac_data[0]：
    //   输出 192kHz 方波。
    //
    // dac_data[1]：
    //   输出 384kHz 方波。
    //
    // dac_data[2]：
    //   输出 48kHz 方波。
    //
    // dac_data[7]：
    //   输出 MMCM locked 状态。
    //=========================================================
    assign dac_clk     = clk_audio_128x;

    assign dac_data[0] = div_cnt[4];
    assign dac_data[1] = div_cnt[3];
    assign dac_data[2] = div_cnt[6];
    assign dac_data[3] = 1'b0;
    assign dac_data[4] = 1'b0;
    assign dac_data[5] = 1'b0;
    assign dac_data[6] = 1'b0;
    assign dac_data[7] = mmcm_locked;

endmodule