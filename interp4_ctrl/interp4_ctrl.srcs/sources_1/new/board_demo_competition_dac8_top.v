`timescale 1ns / 1ps

// ============================================================
// 模块名：board_demo_competition_dac8_top
//
// 这是“当前 Zynq 板”的最外层封装。
// 它自己不做插值、不做模式切换、不做波形生成，
// 只是把公共演示层 demo_interp_dac8_common 包一层。
// ============================================================
module board_demo_competition_dac8_top (
    input  wire       clk,       // 板上的系统时钟
    input  wire       rst_n,     // 板上的低有效复位

    input  wire       sw0,       // 拨码开关 SW0：倍率选择低位
    input  wire       sw1,       // 拨码开关 SW1：倍率选择高位
    input  wire       sw2,       // 拨码开关 SW2：采样率家族选择

    output wire       dac_clk,   // 输出给外部 8bit 并行 DAC 的时钟
    output wire [7:0] dac_data   // 输出给外部 8bit 并行 DAC 的数据
);

    // // 直接实例化公共演示层
    // demo_interp_dac8_common u_demo_interp_dac8_common (
    //     .clk      (clk),
    //     .rst_n    (rst_n),
    //     .dac_clk  (dac_clk),
    //     .dac_data (dac_data),
    //     .mode_led (mode_led)
    // );

    // // 二编：临时修改为冒烟测试模块，等插值功能做好了再改回来    ：验证成功，出现锯齿波
    // demo_dac8_smoketest_common u_demo_dac8_smoketest_common (
    //     .clk      (clk),
    //     .rst_n    (rst_n),
    //     .dac_clk  (dac_clk),
    //     .dac_data (dac_data),
    //     .mode_led (mode_led)
    // );

    // // 三编:直接改成正弦波测试模块，等插值功能做好了再改回来   :验证成功，出现正弦波          
    // demo_dac8_sine_common u_demo_dac8_sine_common (
    //     .clk      (clk),
    //     .rst_n    (rst_n),
    //     .dac_clk  (dac_clk),
    //     .dac_data (dac_data),
    //     .mode_led (mode_led)
    // );

    // // 四编：直接改成正式采样率 CE 发生器测试模块，等插值功能做好了再改回来   :验证成功，出现不同频率的方波
    // wire [1:0] mode_led_unused;

    // demo_interp_dac8_audio_rate_common u_demo_interp_dac8_audio_rate_common (
    //     .clk          (clk),
    //     .rst_n        (rst_n),

    //     .mode_sel     ({sw1, sw0}),
    //     .rate_sel_48k (sw2),

    //     .dac_clk      (dac_clk),
    //     .dac_data     (dac_data),
    //     .mode_led     (mode_led_unused)
    // );

    // 五编：直接改成正式采样率 MMCM 版本的公共演示层，等插值功能做好了再改回来   :验证成功，出现不同频率的方波
    wire clk_audio_128x_48k;
    wire clk_audio_128x_44k1;
    wire mmcm_locked_48k;
    wire mmcm_locked_44k1;
    wire mmcm_locked_sel;

    wire clkfb_48k;
    wire clkfb_44k1;

    wire clk_audio_128x_sel;
    wire rst_audio_n;
    reg  [2:0] rst_audio_sync;

    wire clk_ibuf;
    wire clk_sys_bufg;

    IBUF u_ibuf_sys_clk (
        .I (clk),
        .O (clk_ibuf)
    );

    BUFG u_bufg_sys_clk (
        .I (clk_ibuf),
        .O (clk_sys_bufg)
    );

    clk_wiz_audio_48k u_clk_wiz_audio_48k (
        .clk_out1  (clk_audio_128x_48k),
        .reset     (~rst_n),
        .locked    (mmcm_locked_48k),
        .clk_in1   (clk_sys_bufg),
        .clkfb_in  (clkfb_48k),
        .clkfb_out (clkfb_48k)
    );

    clk_wiz_audio_44k1 u_clk_wiz_audio_44k1 (
        .clk_out1  (clk_audio_128x_44k1),       
        .reset     (~rst_n),
        .locked    (mmcm_locked_44k1),
        .clk_in1   (clk_sys_bufg),
        .clkfb_in  (clkfb_44k1),
        .clkfb_out (clkfb_44k1)
    );

    //=========================================================
    // 用 BUFGMUX 选择 44.1kHz / 48kHz 家族音频时钟
    //
    // 普通 assign 不适合直接选择两个时钟。
    // BUFGMUX 是 Xilinx 提供的全局时钟选择资源。
    //
    // S = 0：
    //   选择 I0，也就是 44.1kHz 家族的 5.6448MHz。
    //
    // S = 1：
    //   选择 I1，也就是 48kHz 家族的 6.144MHz。
    //
    // 注意：
    //   当前 SW2 是手动拨码开关。
    //   建议切换 SW2 后按一次复位，再观察输出。
    //=========================================================
    BUFGMUX #(
        .CLK_SEL_TYPE ("ASYNC")
    ) u_bufgmux_audio_clk (
        .O  (clk_audio_128x_sel),
        .I0 (clk_audio_128x_44k1),
        .I1 (clk_audio_128x_48k),
        .S  (sw2)
    );

    assign mmcm_locked_sel = sw2 ? mmcm_locked_48k : mmcm_locked_44k1;

    always @(posedge clk_audio_128x_sel or negedge rst_n) begin
        if (!rst_n)
            rst_audio_sync <= 3'b000;
        else if (!mmcm_locked_sel)
            rst_audio_sync <= 3'b000;
        else
            rst_audio_sync <= {rst_audio_sync[1:0], 1'b1};
    end

    assign rst_audio_n = rst_audio_sync[2];

    demo_interp_dac8_mmcm_common u_demo_interp_dac8_mmcm_common (
        .clk_audio_128x (clk_audio_128x_sel),
        .rst_n          (rst_audio_n),
        .mode_sel       ({sw1, sw0}),
        .dac_clk        (dac_clk),
        .dac_data       (dac_data),
        .mode_led       ()
    );


endmodule
