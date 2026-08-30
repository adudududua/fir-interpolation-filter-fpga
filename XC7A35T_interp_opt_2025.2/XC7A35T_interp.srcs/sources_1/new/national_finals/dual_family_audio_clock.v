`timescale 1ps / 1ps

//=============================================================
// 文件名       : dual_family_audio_clock.v
// 模块名       : dual_family_audio_clock
// 功能简述     : 由板载 20 MHz 同时产生 44.1 kHz 与 48 kHz 家族
//                的 128x 音频时钟，并用专用全局时钟资源切换。
//
//                family_48k=0: 5.644796 MHz，误差约 -0.64 ppm
//                family_48k=1: 6.144068 MHz，误差约 +11.03 ppm
//
//                48 kHz 配置使用 M=36.25、D=1、O=118，相比原
//                Clock Wizard 保存配置的约 +162 ppm 明显更准确。
//                两路输出只消耗 MMCM/BUFG 时钟专用资源，不复制
//                FIR、DSP 或数据 BRAM。
// 设计作者     : kafeizizi
// 创建日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     : V2025.2 统一文件头并补充双采样率时钟配置说明。
//=============================================================
//=============================================================
// 1）模块名称：dual_family_audio_clock
// 功能说明：双采样率族时钟模块：在 44.1 kHz 与 48 kHz 时钟族之间安全切换。
// 工程版本：Vivado 2025.2。
//=============================================================

module dual_family_audio_clock (
    input  wire clk_20m,
    input  wire reset,
    input  wire family_48k,
    output wire clk_audio_128x,
    output wire locked_selected,
    output wire locked_44k1,
    output wire locked_48k
);

    wire clk_44k1_raw;
    wire clk_48k_raw;
    wire clkfb_44k1;
    wire clkfb_48k;
    wire clkfb_44k1_b_unused;
    wire clkfb_48k_b_unused;
    wire clkout0b_44k1_unused;
    wire clkout0b_48k_unused;
    wire clkout1_44k1_unused;
    wire clkout1_48k_unused;
    wire clkout1b_44k1_unused;
    wire clkout1b_48k_unused;
    wire clkout2_44k1_unused;
    wire clkout2_48k_unused;
    wire clkout2b_44k1_unused;
    wire clkout2b_48k_unused;
    wire clkout3_44k1_unused;
    wire clkout3_48k_unused;
    wire clkout3b_44k1_unused;
    wire clkout3b_48k_unused;
    wire clkout4_44k1_unused;
    wire clkout4_48k_unused;
    wire clkout5_44k1_unused;
    wire clkout5_48k_unused;
    wire clkout6_44k1_unused;
    wire clkout6_48k_unused;
    wire clkinstopped_44k1_unused;
    wire clkinstopped_48k_unused;
    wire clkfbstopped_44k1_unused;
    wire clkfbstopped_48k_unused;
    wire [15:0] do_44k1_unused;
    wire [15:0] do_48k_unused;
    wire drdy_44k1_unused;
    wire drdy_48k_unused;
    wire psdone_44k1_unused;
    wire psdone_48k_unused;

    // 例化说明：调用 7 系列 MMCM 原语，完成音频采样率族所需的时钟合成和锁定检测。
    MMCME2_ADV #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKOUT4_CASCADE("FALSE"),
        .COMPENSATION("ZHOLD"),
        .STARTUP_WAIT("FALSE"),
        .DIVCLK_DIVIDE(2),
        .CLKFBOUT_MULT_F(62.375),
        .CLKFBOUT_PHASE(0.0),
        .CLKFBOUT_USE_FINE_PS("FALSE"),
        .CLKOUT0_DIVIDE_F(110.500),
        .CLKOUT0_PHASE(0.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_USE_FINE_PS("FALSE"),
        .CLKIN1_PERIOD(50.0)
    ) u_mmcm_44k1 (
        .CLKFBOUT(clkfb_44k1),
        .CLKFBOUTB(clkfb_44k1_b_unused),
        .CLKOUT0(clk_44k1_raw),
        .CLKOUT0B(clkout0b_44k1_unused),
        .CLKOUT1(clkout1_44k1_unused),
        .CLKOUT1B(clkout1b_44k1_unused),
        .CLKOUT2(clkout2_44k1_unused),
        .CLKOUT2B(clkout2b_44k1_unused),
        .CLKOUT3(clkout3_44k1_unused),
        .CLKOUT3B(clkout3b_44k1_unused),
        .CLKOUT4(clkout4_44k1_unused),
        .CLKOUT5(clkout5_44k1_unused),
        .CLKOUT6(clkout6_44k1_unused),
        .CLKFBIN(clkfb_44k1),
        .CLKIN1(clk_20m),
        .CLKIN2(1'b0),
        .CLKINSEL(1'b1),
        .DADDR(7'd0),
        .DCLK(1'b0),
        .DEN(1'b0),
        .DI(16'd0),
        .DO(do_44k1_unused),
        .DRDY(drdy_44k1_unused),
        .DWE(1'b0),
        .PSCLK(1'b0),
        .PSEN(1'b0),
        .PSINCDEC(1'b0),
        .PSDONE(psdone_44k1_unused),
        .LOCKED(locked_44k1),
        .CLKINSTOPPED(clkinstopped_44k1_unused),
        .CLKFBSTOPPED(clkfbstopped_44k1_unused),
        .PWRDWN(1'b0),
        .RST(reset)
    );

    // 例化说明：调用 7 系列 MMCM 原语，完成音频采样率族所需的时钟合成和锁定检测。
    MMCME2_ADV #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKOUT4_CASCADE("FALSE"),
        .COMPENSATION("ZHOLD"),
        .STARTUP_WAIT("FALSE"),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(36.250),
        .CLKFBOUT_PHASE(0.0),
        .CLKFBOUT_USE_FINE_PS("FALSE"),
        .CLKOUT0_DIVIDE_F(118.000),
        .CLKOUT0_PHASE(0.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_USE_FINE_PS("FALSE"),
        .CLKIN1_PERIOD(50.0)
    ) u_mmcm_48k (
        .CLKFBOUT(clkfb_48k),
        .CLKFBOUTB(clkfb_48k_b_unused),
        .CLKOUT0(clk_48k_raw),
        .CLKOUT0B(clkout0b_48k_unused),
        .CLKOUT1(clkout1_48k_unused),
        .CLKOUT1B(clkout1b_48k_unused),
        .CLKOUT2(clkout2_48k_unused),
        .CLKOUT2B(clkout2b_48k_unused),
        .CLKOUT3(clkout3_48k_unused),
        .CLKOUT3B(clkout3b_48k_unused),
        .CLKOUT4(clkout4_48k_unused),
        .CLKOUT5(clkout5_48k_unused),
        .CLKOUT6(clkout6_48k_unused),
        .CLKFBIN(clkfb_48k),
        .CLKIN1(clk_20m),
        .CLKIN2(1'b0),
        .CLKINSEL(1'b1),
        .DADDR(7'd0),
        .DCLK(1'b0),
        .DEN(1'b0),
        .DI(16'd0),
        .DO(do_48k_unused),
        .DRDY(drdy_48k_unused),
        .DWE(1'b0),
        .PSCLK(1'b0),
        .PSEN(1'b0),
        .PSINCDEC(1'b0),
        .PSDONE(psdone_48k_unused),
        .LOCKED(locked_48k),
        .CLKINSTOPPED(clkinstopped_48k_unused),
        .CLKFBSTOPPED(clkfbstopped_48k_unused),
        .PWRDWN(1'b0),
        .RST(reset)
    );

    // BUFGMUX_CTRL 在专用时钟网络中完成无毛刺切换。板级顶层会
    // 在 family_48k 改变前异步复位数据通路，切换后等待稳定窗口
    // 再同步释放，因此滤波状态不会跨采样率家族泄漏。
    BUFGMUX_CTRL u_bufgmux_audio_family (
        .I0(clk_44k1_raw),
        .I1(clk_48k_raw),
        .S(family_48k),
        .O(clk_audio_128x)
    );

    assign locked_selected = family_48k ? locked_48k : locked_44k1;

endmodule
