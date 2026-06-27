`timescale 1ns / 1ps
//=============================================================
// 文件名       : board_demo_competition_dac8_top.v
// 模块名       : board_demo_competition_dac8_top
// 功能简述     : Artix-7 XC7A35T 赛方板 AD9708 DAC 静态 48kHz
//                采样率家族单 MMCM 探索顶层。
//                本版本仅保留：
//                  50MHz -> clk_wiz_audio_48k -> 6.144MHz
//                不再实例化 44.1kHz 家族 Clock Wizard。
//                sw1 sw0 仍选择 4x、8x、128x 插值输出。
//                sw2 端口保留用于兼容原 XDC，但本探索版本不使用。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-06-20
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-06-20：恢复原已验证的双频率家族时钟结构。
//                2026-06-20：去掉外部 rst_n 端口，改为内部上电复位。
//                2026-06-20：不使用外部反馈 BUFG。
//                2026-06-20：不使用 CLOCK_DEDICATED_ROUTE FALSE。
//                2026-06-27：加入采样率家族 mode-aware MMCM reset gating。
//                2026-06-27：Stage 2c 静态单采样率家族探索，
//                            仅保留 48kHz 家族 Clock Wizard，
//                            用于评估单 MMCM 结构的资源和功耗报告变化。
// 其他描述     :
//                1. 本版本固定为 48kHz 家族。
//                   128x 时钟约为 6.144MHz。
//                2. sw1 sw0 = 00：4x 插值输出，约 192kHz。
//                3. sw1 sw0 = 01：8x 插值输出，约 384kHz。
//                4. sw1 sw0 = 10/11：128x 插值输出，约 6.144MHz。
//                5. sw2 在本探索版本中不参与逻辑，仅保留顶层端口。
//=============================================================

module board_demo_competition_dac8_top (
    input  wire       clk,       // 板载 50MHz 系统时钟

    input  wire       sw0,       // 拨码 SW0：倍率选择低位
    input  wire       sw1,       // 拨码 SW1：倍率选择高位
    input  wire       sw2,       // 拨码 SW2：本静态探索版本中不使用，仅兼容原 XDC

    output wire       dac_clk,   // AD9708 DA_CLK
    output wire [7:0] dac_data   // AD9708 DA_D0~DA_D7
);

    //=========================================================
    // 1）系统时钟输入缓冲
    //
    // 系统时钟路径：
    //   外部 50MHz -> IBUF -> BUFG -> clk_wiz_audio_48k
    //
    // 本探索版本只保留 48kHz 家族 Clock Wizard。
    //=========================================================
    wire clk_ibuf;
    wire clk_sys_bufg;

    IBUF u_ibuf_sys_clk (
        .I(clk),
        .O(clk_ibuf)
    );

    BUFG u_bufg_sys_clk (
        .I(clk_ibuf),
        .O(clk_sys_bufg)
    );

    //=========================================================
    // 2）拨码输入缓冲
    //
    // sw0/sw1 用来选择插值倍率。
    // sw2 在本静态探索版本中不使用。
    //=========================================================
    wire sw0_ibuf;
    wire sw1_ibuf;

    IBUF u_ibuf_sw0 (
        .I(sw0),
        .O(sw0_ibuf)
    );

    IBUF u_ibuf_sw1 (
        .I(sw1),
        .O(sw1_ibuf)
    );

    // 防止部分综合设置对未使用顶层输入给出过多告警。
    // 该信号不参与功能逻辑。
    wire sw2_unused;
    assign sw2_unused = sw2;

    //=========================================================
    // 3）内部上电复位
    //
    // 当前赛方板没有明确外部 rst_n 管脚。
    // 所以这里用 50MHz 系统时钟产生一个上电复位。
    //=========================================================
    reg [15:0] pwr_rst_cnt = 16'd0;
    wire       rst_n_int;

    always @(posedge clk_sys_bufg) begin
        if (pwr_rst_cnt != 16'hFFFF)
            pwr_rst_cnt <= pwr_rst_cnt + 16'd1;
        else
            pwr_rst_cnt <= pwr_rst_cnt;
    end

    assign rst_n_int = (pwr_rst_cnt == 16'hFFFF);

    //=========================================================
    // 4）Clock Wizard：48kHz 家族
    //
    // 输入：
    //   clk_sys_bufg = 50MHz
    //
    // 输出：
    //   clk_audio_128x_48k = 6.144MHz
    //
    // 本探索版本不实例化 44.1kHz 家族 Clock Wizard，
    // 用于观察单 MMCM 结构下资源和默认功耗报告的变化。
    //=========================================================
    wire clk_audio_128x_48k;
    wire mmcm_locked_48k;
    wire clkfb_48k;

    clk_wiz_audio_48k u_clk_wiz_audio_48k (
        .clk_out1  (clk_audio_128x_48k),
        .reset     (~rst_n_int),
        .locked    (mmcm_locked_48k),
        .clk_in1   (clk_sys_bufg),
        .clkfb_in  (clkfb_48k),
        .clkfb_out (clkfb_48k)
    );

    //=========================================================
    // 5）音频时钟全局缓冲
    //
    // Stage 2 主版本使用 BUFGMUX 在两个 Clock Wizard 之间选择。
    // 本探索版本只有一个音频时钟源，因此使用 BUFG 送入后级逻辑。
    //=========================================================
    wire clk_audio_128x_sel;

    BUFG u_bufg_audio_clk (
        .I(clk_audio_128x_48k),
        .O(clk_audio_128x_sel)
    );

    //=========================================================
    // 6）音频时钟域复位同步
    //
    // 48kHz 家族 MMCM 未 locked 前，后级音频逻辑保持复位；
    // MMCM locked 后，在当前音频时钟域内同步释放复位。
    //=========================================================
    reg [2:0] rst_audio_sync;

    wire rst_audio_async_n;

    assign rst_audio_async_n = rst_n_int & mmcm_locked_48k;

    always @(posedge clk_audio_128x_sel or negedge rst_audio_async_n) begin
        if (!rst_audio_async_n) begin
            rst_audio_sync <= 3'b000;
        end
        else begin
            rst_audio_sync <= {rst_audio_sync[1:0], 1'b1};
        end
    end

    wire rst_audio_n;

    assign rst_audio_n = rst_audio_sync[2];

    //=========================================================
    // 7）实例化正式插值 DAC 公共模块
    //
    // 该公共模块内部仍支持 4x / 8x / 128x 三档输出。
    // 本顶层固定提供 48kHz 家族的 128x 音频时钟。
    //=========================================================
    wire [1:0] mode_led_unused;

    demo_interp_dac8_audio_pcm_common u_demo_interp_dac8_audio_pcm_common (
        .clk_audio_128x (clk_audio_128x_sel),
        .rst_n          (rst_audio_n),
        .mode_sel       ({sw1_ibuf, sw0_ibuf}),

        .dac_clk        (dac_clk),
        .dac_data       (dac_data),
        .mode_led       (mode_led_unused)
    );

endmodule
