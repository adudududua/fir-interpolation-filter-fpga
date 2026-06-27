`timescale 1ns / 1ps
//=============================================================
// 文件名       : board_demo_competition_dac8_top.v
// 模块名       : board_demo_competition_dac8_top
// 功能简述     : Artix-7 XC7A35T 赛方板 AD9708 DAC 双频率家族
//                插值演示顶层。
//                本版本采用已验证的双 MMCM + BUFGMUX 结构，
//                并加入采样率家族感知的 MMCM reset gating：
//                50MHz -> clk_wiz_audio_44k1 -> 5.6448MHz
//                50MHz -> clk_wiz_audio_48k  -> 6.144MHz
//                sw2 通过 BUFGMUX 选择当前音频 128x 时钟，
//                同时控制未使用采样率家族 Clock Wizard 复位。
//                sw1 sw0 选择 4x、8x、128x 插值输出。
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
//                2026-06-27：加入采样率家族 mode-aware MMCM reset gating，
//                            未选中的 Clock Wizard 保持复位以降低无效功耗。
// 其他描述     :
//                1. sw2 = 0：选择 44.1kHz 家族。
//                   128x 时钟约为 5.6448MHz。
//                2. sw2 = 1：选择 48kHz 家族。
//                   128x 时钟约为 6.144MHz。
//                3. sw1 sw0 = 00：4x 插值输出。
//                4. sw1 sw0 = 01：8x 插值输出。
//                5. sw1 sw0 = 10/11：128x 插值输出。
//=============================================================

module board_demo_competition_dac8_top (
    input  wire       clk,       // 板载 50MHz 系统时钟

    input  wire       sw0,       // 拨码 SW0：倍率选择低位
    input  wire       sw1,       // 拨码 SW1：倍率选择高位
    input  wire       sw2,       // 拨码 SW2：采样率家族选择，0=44.1k，1=48k

    output wire       dac_clk,   // AD9708 DA_CLK
    output wire [7:0] dac_data   // AD9708 DA_D0~DA_D7
);

    //=========================================================
    // 1）系统时钟输入缓冲
    //
    // 系统时钟路径：
    //   外部 50MHz -> IBUF -> BUFG -> 两个 Clock Wizard
    //
    // 两个 Clock Wizard 分别产生 44.1kHz 家族和 48kHz 家族
    // 所需的 128x 音频时钟。
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
    // sw2 用来选择频率家族。
    //=========================================================
    wire sw0_ibuf;
    wire sw1_ibuf;
    wire sw2_ibuf;

    IBUF u_ibuf_sw0 (
        .I(sw0),
        .O(sw0_ibuf)
    );

    IBUF u_ibuf_sw1 (
        .I(sw1),
        .O(sw1_ibuf)
    );

    IBUF u_ibuf_sw2 (
        .I(sw2),
        .O(sw2_ibuf)
    );

    //=========================================================
    // 3）sw2 采样率家族选择同步
    //
    // use_48k = 0：选择 44.1kHz 家族；
    // use_48k = 1：选择 48kHz 家族。
    //
    // 原工程中 sw2_ibuf 直接驱动 BUFGMUX 选择端。
    // 本阶段为了同时控制两个 Clock Wizard 的 reset，
    // 先在 50MHz 系统时钟域做两级同步，减少拨码输入
    // 对 MMCM reset / BUFGMUX select 的异步影响。
    //
    // 注意：
    //   机械拨码仍可能存在抖动。板级验证时先拨好 sw2，
    //   等待约 1 秒后再观察输出频率和波形。
    //=========================================================
    reg sw2_meta = 1'b0;
    reg sw2_sync = 1'b0;

    always @(posedge clk_sys_bufg) begin
        sw2_meta <= sw2_ibuf;
        sw2_sync <= sw2_meta;
    end

    wire use_48k;

    assign use_48k = sw2_sync;

    //=========================================================
    // 4）内部上电复位
    //
    // 当前赛方板没有明确外部 rst_n 管脚。
    // 所以这里用 50MHz 系统时钟产生一个上电复位。
    //
    // pwr_rst_cnt 计满前：
    //   rst_n_int = 0
    //
    // pwr_rst_cnt 计满后：
    //   rst_n_int = 1
    //
    // 作用：
    //   给两个 Clock Wizard 和后级逻辑一个稳定启动过程。
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
    // 5）Clock Wizard：48kHz 家族
    //
    // 输入：
    //   clk_sys_bufg = 50MHz
    //
    // 输出：
    //   clk_audio_128x_48k = 6.144MHz
    //
    // 注意：
    //   这里恢原来已验证的写法：
    //   clkfb_in 和 clkfb_out 直接通过同一个 wire 相连。
    //   不再额外插入外部 BUFG。
    //=========================================================
    wire clk_audio_128x_48k;
    wire mmcm_locked_48k;
    wire clkfb_48k;

    // Stage 2 低功耗探索：
    // sw2/use_48k = 1 时启用 48kHz 家族 Clock Wizard；
    // sw2/use_48k = 0 时将其保持复位，避免未使用 MMCM 持续工作。
    wire rst_mmcm_48k;

    assign rst_mmcm_48k = (~rst_n_int) | (~use_48k);

    clk_wiz_audio_48k u_clk_wiz_audio_48k (
        .clk_out1  (clk_audio_128x_48k),
        .reset     (rst_mmcm_48k),
        .locked    (mmcm_locked_48k),
        .clk_in1   (clk_sys_bufg),
        .clkfb_in  (clkfb_48k),
        .clkfb_out (clkfb_48k)
    );

    //=========================================================
    // 6）Clock Wizard：44.1kHz 家族
    //
    // 输入：
    //   clk_sys_bufg = 50MHz
    //
    // 输出：
    //   clk_audio_128x_44k1 = 5.6448MHz
    //
    // 同样恢复原先已验证的反馈连接方式。
    //=========================================================
    wire clk_audio_128x_44k1;
    wire mmcm_locked_44k1;
    wire clkfb_44k1;

    // Stage 2 低功耗探索：
    // sw2/use_48k = 0 时启用 44.1kHz 家族 Clock Wizard；
    // sw2/use_48k = 1 时将其保持复位，避免未使用 MMCM 持续工作。
    wire rst_mmcm_44k1;

    assign rst_mmcm_44k1 = (~rst_n_int) | use_48k;

    clk_wiz_audio_44k1 u_clk_wiz_audio_44k1 (
        .clk_out1  (clk_audio_128x_44k1),
        .reset     (rst_mmcm_44k1),
        .locked    (mmcm_locked_44k1),
        .clk_in1   (clk_sys_bufg),
        .clkfb_in  (clkfb_44k1),
        .clkfb_out (clkfb_44k1)
    );

    //=========================================================
    // 7）BUFGMUX 选择两个频率家族
    //
    // sw2_ibuf = 0：
    //   选择 I0，即 44.1kHz 家族 5.6448MHz。
    //
    // sw2_ibuf = 1：
    //   选择 I1，即 48kHz 家族 6.144MHz。
    //
    // 注：
    //   在下载 bitstream 前先拨好 sw2。
    //   如果运行中切换 sw2，可能会有短暂过渡。
    //=========================================================
    wire clk_audio_128x_sel;

    BUFGMUX #(
        .CLK_SEL_TYPE("ASYNC")
    ) u_bufgmux_audio_clk (
        .O  (clk_audio_128x_sel),
        .I0 (clk_audio_128x_44k1),
        .I1 (clk_audio_128x_48k),
        .S  (use_48k)
    );

    // 当前被选择的 MMCM locked 信号
    wire mmcm_locked_sel;

    assign mmcm_locked_sel = use_48k ? mmcm_locked_48k : mmcm_locked_44k1;

    //=========================================================
    // 8）音频时钟域复位同步
    //
    // rst_audio_sync：
    //   在当前选择的音频时钟域内释放复位。
    //
    // rst_audio_n：
    //   送给正式插值公共模块。
    //=========================================================
    reg [2:0] rst_audio_sync;

    // 被选中 MMCM 未锁定时立即复位音频域；
    // 锁定后再在当前音频时钟域内同步释放复位。
    // 这样在切换 sw2 时，新时钟家族锁定前不会让插值链误运行。
    wire rst_audio_async_n;

    assign rst_audio_async_n = rst_n_int & mmcm_locked_sel;

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
    // 9）实例化正式插值 DAC 公共模块
    //
    // 注意：
    //   如果你当前正式公共模块名字是：
    //     demo_interp_dac8_mmcm48_common
    //   就使用下面这个实例。
    //
    //   如果工程里模块名仍然叫：
    //     demo_interp_dac8_mmcm_common
    //   那只需要把实例化模块名改成 demo_interp_dac8_mmcm_common。
    //=========================================================
    wire [1:0] mode_led_unused;

    // demo_interp_dac8_mmcm48_common u_demo_interp_dac8_mmcm48_common (
    demo_interp_dac8_audio_pcm_common u_demo_interp_dac8_audio_pcm_common (
        .clk_audio_128x (clk_audio_128x_sel),
        .rst_n          (rst_audio_n),
        .mode_sel       ({sw1_ibuf, sw0_ibuf}),

        .dac_clk        (dac_clk),
        .dac_data       (dac_data),
        .mode_led       (mode_led_unused)
    );

endmodule
