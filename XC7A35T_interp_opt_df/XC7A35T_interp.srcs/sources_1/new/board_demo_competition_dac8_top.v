`timescale 1ns / 1ps
//=============================================================
// 文件名       : board_demo_competition_dac8_top.v
// 模块名       : board_demo_competition_dac8_top
// 功能简述     : Artix-7 XC7A35T 赛方板 AD9708 DAC 的 44.1kHz
//                专用全 2x 插值演示顶层。
//                当前展示版本只保留：
//                20MHz -> clk_wiz_audio_44k1 -> 5.6448MHz
//                矩阵按键用于选择插值节点并调节输入正弦波频率。
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
//                2026-07-10：删除 48kHz MMCM 与 BUFGMUX，固定使用
//                            44.1kHz / 5.6448MHz 时钟家族。
//                2026-07-10：板级公共模块切换为全 2x 插值链路。
//                2026-07-10：增加 mode_sel 的音频时钟域两级同步器。
//                2026-07-12：增加 1x 原始 PCM 旁路档，SW1～SW4
//                            映射为 1x/4x/8x/128x。
//                2026-07-18：增加 Stage 2/3 单读 LUTRAM 板级候选参数；
//                            默认关闭，稳定版本行为保持不变。
//                2026-07-18：增加紧凑四档矩阵按键候选参数；
//                            默认关闭，完整 16 键扫描器继续保留。
//                2026-07-18：增加紧凑键盘扫描分频参数，便于独立比较
//                            20000 与二次幂 16384 的资源实现。
//                2026-07-18：增加上电计数器复用扫描候选，默认关闭。
//                2026-07-18：增加 CIC burst 计数器 DSP/LUT 选择参数。
//                2026-07-18：增加 Stage2/3 交叉系数 BRAM 打包参数。
//                2026-07-18：增加 12864T 图形液晶界面，显示当前
//                            插值倍率、采样率和 SW1～SW8 映射。
//                2026-07-18：增加 1kHz～20kHz 可调 NCO；SW5～SW8
//                            用于频率步进、15kHz 复位和自动扫频，
//                            液晶同步显示当前输入频率与扫频状态。
//                2026-07-19：保留 SW1～SW8 全部功能，新增 SW9
//                            进入/退出 ILA 镜像抑制演示模式。
//                2026-07-19：在现有音频MMCM增加100MHz调试输出，
//                            专门驱动Debug Hub；音频时钟保持不变。
//                2026-07-19：ILA 新增实际 DAC 码流、当前 DAC 模式、
//                            DAC 时钟和 1x～128x 逐级采样率探针。
//                2026-07-19：增加独立100MHz参考时钟测频，ILA直接
//                            显示DAC_CLK的Hz值、100ms边沿数和有效脉冲。
// 其他描述     :
//                1. SW1/SW2/SW3/SW4：1x/4x/8x/128x。
//                2. SW5/SW6/SW7/SW8：+1/-1/15kHz/AUTO。
//                3. SW9：ILA 演示模式开/关；退出后恢复原状态。
//=============================================================

module board_demo_competition_dac8_top #(
    parameter integer USE_PHASE7_LUTRAM_STAGE23 = 0,
    parameter integer USE_COMPACT_KEYPAD = 0,
    parameter integer COMPACT_KEYPAD_SCAN_DIV = 20000,
    parameter integer USE_SHARED_KEYPAD_SCAN_TICK = 0,
    parameter integer USE_PHASE7_BRAM_STAGE23_HISTORY = 0,
    parameter integer USE_PHASE7_BRAM_STAGE23_COEFF = 0,
    parameter integer USE_PHASE8_PACKED_BRAM_STAGE23 = 0,
    parameter integer USE_PHASE7_CIC_BURST_COUNTER_DSP = 0,
    parameter integer TONE_AUTO_STEP_CYCLES = 20000000
)(
    input  wire       clk,       // 板载 20MHz 系统时钟

    output wire [3:0] key_kr,    // 矩阵按键 KR0~KR3，扫描输出
    input  wire [3:0] key_kc,    // 矩阵按键 KC0~KC3，带外部上拉输入

    output wire       dac_clk,   // AD9708 DA_CLK
    output wire [7:0] dac_data,  // AD9708 DA_D0~DA_D7

    output wire [7:0] lcd_data,  // 12864T LCD_D0~LCD_D7
    output wire       lcd_rs,    // 12864T RS
    output wire       lcd_rw,    // 12864T R/W，当前控制器只写
    output wire       lcd_e,     // 12864T E

    output wire       beep_io    // 蜂鸣器控制，低电平响，高电平关闭
);

    //=========================================================
    // 1）系统时钟输入缓冲
    //
    // 这里恢复你原来验证通过的结构：
    //   外部 20MHz -> IBUF -> BUFG -> 两个 Clock Wizard
    //
    // 不再使用：
    //   clk_ibuf 直接进两个 MMCM
    //
    // 这样和你之前能跑通的版本保持一致。
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
    // 2）内部上电复位
    //
    // 当前赛方板没有明确外部 rst_n 管脚。
    // 所以这里用 20MHz 系统时钟产生一个上电复位。
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
    reg        pwr_rst_done = 1'b0;
    wire       rst_n_int;
    wire       compact_keypad_scan_tick;

    generate
        if (USE_SHARED_KEYPAD_SCAN_TICK != 0) begin : gen_shared_scan_counter
            always @(posedge clk_sys_bufg) begin
                pwr_rst_cnt <= pwr_rst_cnt + 16'd1;
                if (pwr_rst_cnt == 16'hFFFE)
                    pwr_rst_done <= 1'b1;
            end
            assign rst_n_int = pwr_rst_done;
        end
        else begin : gen_dedicated_power_reset
            always @(posedge clk_sys_bufg) begin
                if (pwr_rst_cnt != 16'hFFFF)
                    pwr_rst_cnt <= pwr_rst_cnt + 16'd1;
                else
                    pwr_rst_cnt <= pwr_rst_cnt;
            end
            assign rst_n_int = (pwr_rst_cnt == 16'hFFFF);
        end
    endgenerate

    assign compact_keypad_scan_tick = &pwr_rst_cnt[13:0];

    //=========================================================
    // 3）矩阵按键扫描与模式锁存
    //
    // KR 只在当前扫描列主动拉低，其他列保持高阻。
    // KC 由板上 10k 电阻上拉，按下时被当前 KR 拉低。
    //=========================================================
    wire [3:0] key_kr_drive_low;
    wire       key_family_sel_unused;
    wire [1:0] key_mode_sel;
    wire       key_strobe;
    wire [3:0] key_code;

    assign key_kr[0] = key_kr_drive_low[0] ? 1'b0 : 1'bz;
    assign key_kr[1] = key_kr_drive_low[1] ? 1'b0 : 1'bz;
    assign key_kr[2] = key_kr_drive_low[2] ? 1'b0 : 1'bz;
    assign key_kr[3] = key_kr_drive_low[3] ? 1'b0 : 1'bz;

    generate
        if (USE_COMPACT_KEYPAD != 0) begin : gen_compact_keypad
            matrix_keypad_mode_ctrl_compact #(
                .SCAN_DIV               (COMPACT_KEYPAD_SCAN_DIV),
                .USE_EXTERNAL_SCAN_TICK (USE_SHARED_KEYPAD_SCAN_TICK)
            ) u_matrix_keypad_mode_ctrl_compact (
                .clk          (clk_sys_bufg),
                .rst_n        (rst_n_int),
                .scan_tick    (compact_keypad_scan_tick),
                .kc           (key_kc),
                .kr_drive_low (key_kr_drive_low),
                .mode_sel     (key_mode_sel),
                .key_strobe   (key_strobe),
                .key_code     (key_code)
            );

            assign key_family_sel_unused = 1'b0;
        end
        else begin : gen_full_keypad
            matrix_keypad_mode_ctrl u_matrix_keypad_mode_ctrl (
                .clk          (clk_sys_bufg),
                .rst_n        (rst_n_int),
                .kc           (key_kc),
                .kr_drive_low (key_kr_drive_low),
                .family_sel   (key_family_sel_unused),
                .mode_sel     (key_mode_sel),
                .key_strobe   (key_strobe),
                .key_code     (key_code)
            );
        end
    endgenerate

    //=========================================================
    // 4）输入正弦波频率控制
    //=========================================================
    wire [4:0] tone_khz_control;
    wire       tone_auto_sweep;

    tone_frequency_control #(
        .AUTO_STEP_CYCLES(TONE_AUTO_STEP_CYCLES)
    ) u_tone_frequency_control (
        .clk        (clk_sys_bufg),
        .rst_n      (rst_n_int),
        .key_strobe (key_strobe),
        .key_code   (key_code),
        .tone_khz   (tone_khz_control),
        .auto_sweep (tone_auto_sweep)
    );

    // SW9 使用完整 4x4 键盘中原先未占用的键码 8。切换演示不会
    // 修改倍率、单音频率或 AUTO 状态，退出后原功能可直接继续。
    reg ila_demo_enable_control;

    always @(posedge clk_sys_bufg or negedge rst_n_int) begin
        if (!rst_n_int)
            ila_demo_enable_control <= 1'b0;
        else if (key_strobe && (key_code == 4'd8))
            ila_demo_enable_control <= ~ila_demo_enable_control;
    end

    wire [15:0] ila_magnitude_15k_pre_w;
    wire [15:0] ila_magnitude_15k_post_w;
    wire [15:0] ila_magnitude_40k_pre_w;
    wire [15:0] ila_magnitude_40k_post_w;
    wire [7:0]  ila_suppression_40k_db_w;
    wire        ila_measurement_valid_w;

    reg [15:0] lcd_magnitude_15k_pre_meta;
    reg [15:0] lcd_magnitude_15k_pre_sync;
    reg [15:0] lcd_magnitude_15k_post_meta;
    reg [15:0] lcd_magnitude_15k_post_sync;
    reg [15:0] lcd_magnitude_40k_pre_meta;
    reg [15:0] lcd_magnitude_40k_pre_sync;
    reg [15:0] lcd_magnitude_40k_post_meta;
    reg [15:0] lcd_magnitude_40k_post_sync;
    reg [7:0]  lcd_suppression_db_meta;
    reg [7:0]  lcd_suppression_db_sync;
    reg        lcd_measurement_valid_meta;
    reg        lcd_measurement_valid_sync;

    // 幅值结果每 10ms 才更新一次，两级采样后供慢速 LCD 帧锁存。
    always @(posedge clk_sys_bufg or negedge rst_n_int) begin
        if (!rst_n_int) begin
            lcd_magnitude_15k_pre_meta  <= 16'd0;
            lcd_magnitude_15k_pre_sync  <= 16'd0;
            lcd_magnitude_15k_post_meta <= 16'd0;
            lcd_magnitude_15k_post_sync <= 16'd0;
            lcd_magnitude_40k_pre_meta  <= 16'd0;
            lcd_magnitude_40k_pre_sync  <= 16'd0;
            lcd_magnitude_40k_post_meta <= 16'd0;
            lcd_magnitude_40k_post_sync <= 16'd0;
            lcd_suppression_db_meta     <= 8'd0;
            lcd_suppression_db_sync     <= 8'd0;
            lcd_measurement_valid_meta  <= 1'b0;
            lcd_measurement_valid_sync  <= 1'b0;
        end
        else begin
            lcd_magnitude_15k_pre_meta  <= ila_magnitude_15k_pre_w;
            lcd_magnitude_15k_pre_sync  <= lcd_magnitude_15k_pre_meta;
            lcd_magnitude_15k_post_meta <= ila_magnitude_15k_post_w;
            lcd_magnitude_15k_post_sync <= lcd_magnitude_15k_post_meta;
            lcd_magnitude_40k_pre_meta  <= ila_magnitude_40k_pre_w;
            lcd_magnitude_40k_pre_sync  <= lcd_magnitude_40k_pre_meta;
            lcd_magnitude_40k_post_meta <= ila_magnitude_40k_post_w;
            lcd_magnitude_40k_post_sync <= lcd_magnitude_40k_post_meta;
            lcd_suppression_db_meta     <= ila_suppression_40k_db_w;
            lcd_suppression_db_sync     <= lcd_suppression_db_meta;
            lcd_measurement_valid_meta  <= ila_measurement_valid_w;
            lcd_measurement_valid_sync  <= lcd_measurement_valid_meta;
        end
    end

    //=========================================================
    // 5）12864T 图形液晶
    //
    // 液晶在 20MHz 控制域运行，直接显示按键域中已经消抖并锁存的
    // key_mode_sel。显示刷新与音频时钟域相互独立，不进入 FIR/CIC
    // 数据路径。底板已把 PSB 拉高到 3.3V，选择 8bit 并行模式；
    // LCD RST 接 SYS_RST，背光可由底板 LCD_EN 跳线保持常亮。
    //=========================================================
    lcd12864_st7920_ui u_lcd12864_st7920_ui (
        .clk      (clk_sys_bufg),
        .rst_n    (rst_n_int),
        .mode_sel (key_mode_sel),
        .tone_khz (tone_khz_control),
        .auto_sweep(tone_auto_sweep),
        .ila_demo_enable(ila_demo_enable_control),
        .magnitude_15k_pre(lcd_magnitude_15k_pre_sync),
        .magnitude_15k_post(lcd_magnitude_15k_post_sync),
        .magnitude_40k_pre(lcd_magnitude_40k_pre_sync),
        .magnitude_40k_post(lcd_magnitude_40k_post_sync),
        .suppression_40k_db(lcd_suppression_db_sync),
        .measurement_valid(lcd_measurement_valid_sync),
        .lcd_data (lcd_data),
        .lcd_rs   (lcd_rs),
        .lcd_rw   (lcd_rw),
        .lcd_e    (lcd_e)
    );

    //=========================================================
    // 6）Clock Wizard：44.1kHz 家族
    //
    // 输入：
    //   clk_sys_bufg = 20MHz
    //
    // 输出：
    //   clk_audio_128x_44k1 = 5.6448MHz，原音频数据路径
    //   clk_debug_100m      = 100MHz，供Debug Hub和DAC_CLK测频使用
    //
    // 同样恢复原先已验证的反馈连接方式。
    //=========================================================
    wire clk_audio_128x_44k1;
    (* keep = "true" *) wire clk_debug_100m;
    wire mmcm_locked_44k1;
    wire clkfb_44k1;

    // Debug Hub 在实现阶段才由Vivado插入。保留一个最小心跳负载，
    // 防止100MHz网络在顶层综合时因暂时无普通RTL负载而被删除。
    (* dont_touch = "true" *) reg debug_clock_alive = 1'b0;

    always @(posedge clk_debug_100m) begin
        debug_clock_alive <= ~debug_clock_alive;
    end

    clk_wiz_audio_44k1 u_clk_wiz_audio_44k1 (
        .clk_out1  (clk_audio_128x_44k1),
        .clk_out2  (clk_debug_100m),
        .reset     (~rst_n_int),
        .locked    (mmcm_locked_44k1),
        .clk_in1   (clk_sys_bufg),
        .clkfb_in  (clkfb_44k1),
        .clkfb_out (clkfb_44k1)
    );

    //=========================================================
    // 7）音频时钟域复位同步
    //
    // rst_audio_sync：
    //   在当前选择的音频时钟域内释放复位。
    //
    // rst_audio_n：
    //   送给正式插值公共模块。
    //=========================================================
    (* ASYNC_REG = "TRUE" *) reg [2:0] rst_audio_sync = 3'b000;

    always @(posedge clk_audio_128x_44k1 or negedge rst_n_int) begin
        if (!rst_n_int) begin
            rst_audio_sync <= 3'b000;
        end
        else if (!mmcm_locked_44k1) begin
            rst_audio_sync <= 3'b000;
        end
        else begin
            rst_audio_sync <= {rst_audio_sync[1:0], 1'b1};
        end
    end

    wire rst_audio_n;

    assign rst_audio_n = rst_audio_sync[2];

    // 100MHz测频逻辑使用同域同步释放的复位，避免将音频域复位直接
    // 作为100MHz时序逻辑的异步释放信号。
    (* ASYNC_REG = "TRUE" *) reg [2:0] rst_debug_sync = 3'b000;

    always @(posedge clk_debug_100m or negedge rst_n_int) begin
        if (!rst_n_int)
            rst_debug_sync <= 3'b000;
        else if (!mmcm_locked_44k1)
            rst_debug_sync <= 3'b000;
        else
            rst_debug_sync <= {rst_debug_sync[1:0], 1'b1};
    end

    wire rst_debug_n;

    assign rst_debug_n = rst_debug_sync[2];

    //=========================================================
    // 8）模式与频率控制跨时钟域同步
    //
    // key_mode_sel 在 20MHz 按键扫描时钟域产生，送入 5.6448MHz
    // 音频域前使用两级同步器。按键模式在消抖后长时间保持稳定，
    // 因此逐位同步不会影响实际模式切换。
    //=========================================================
    (* ASYNC_REG = "TRUE" *) reg [1:0] mode_audio_meta = 2'b11;
    (* ASYNC_REG = "TRUE" *) reg [1:0] mode_audio_sync = 2'b11;
    (* ASYNC_REG = "TRUE" *) reg [4:0] tone_audio_meta = 5'd15;
    (* ASYNC_REG = "TRUE" *) reg [4:0] tone_audio_sync = 5'd15;
    (* ASYNC_REG = "TRUE" *) reg demo_audio_meta = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg demo_audio_sync = 1'b0;
    reg [4:0] tone_audio_previous = 5'd15;
    reg [4:0] tone_audio_state = 5'd15;

    always @(posedge clk_audio_128x_44k1 or negedge rst_audio_n) begin
        if (!rst_audio_n) begin
            mode_audio_meta <= 2'b11;
            mode_audio_sync <= 2'b11;
            tone_audio_meta     <= 5'd15;
            tone_audio_sync     <= 5'd15;
            tone_audio_previous <= 5'd15;
            tone_audio_state    <= 5'd15;
            demo_audio_meta     <= 1'b0;
            demo_audio_sync     <= 1'b0;
        end
        else begin
            mode_audio_meta <= key_mode_sel;
            mode_audio_sync <= mode_audio_meta;
            tone_audio_meta     <= tone_khz_control;
            tone_audio_sync     <= tone_audio_meta;
            tone_audio_previous <= tone_audio_sync;
            demo_audio_meta     <= ila_demo_enable_control;
            demo_audio_sync     <= demo_audio_meta;

            // 连续两拍采样一致后再提交多位频率值，避免中间码进入 NCO。
            if (tone_audio_sync == tone_audio_previous)
                tone_audio_state <= tone_audio_sync;
        end
    end

    //=========================================================
    // 9）实例化 44.1kHz 专用全 2x 插值 DAC 公共模块
    //=========================================================
    (* keep = "true" *) wire [1:0] ila_dac_mode_w;
    (* keep = "true" *) wire signed [23:0] ila_pre2_sample_w;
    (* keep = "true" *) wire signed [23:0] ila_post2_sample_w;
    (* keep = "true" *) wire signed [23:0] ila_final128_sample_w;
    (* keep = "true" *) wire ila_ce2_tick_w;
    (* keep = "true" *) wire [7:0] ila_rate_tick_w;
    (* keep = "true" *) wire [7:0] ila_dac_code_w;
    (* keep = "true" *) wire signed [8:0] ila_dac_signed_w;
    (* keep = "true" *) wire ila_dac_clk_w;
    (* keep = "true" *) wire ila_rate_1x_tick_w;
    (* keep = "true" *) wire ila_rate_2x_tick_w;
    (* keep = "true" *) wire ila_rate_4x_tick_w;
    (* keep = "true" *) wire ila_rate_8x_tick_w;
    (* keep = "true" *) wire ila_rate_16x_tick_w;
    (* keep = "true" *) wire ila_rate_32x_tick_w;
    (* keep = "true" *) wire ila_rate_64x_tick_w;
    (* keep = "true" *) wire ila_rate_128x_tick_w;

    demo_interp_dac8_audio_pcm_common #(
        .USE_PHASE7_FOLDED(1),
        .USE_PHASE7_LUTRAM_STAGE23(USE_PHASE7_LUTRAM_STAGE23),
        .USE_PHASE7_BRAM_STAGE23_HISTORY(USE_PHASE7_BRAM_STAGE23_HISTORY),
        .USE_PHASE7_BRAM_STAGE23_COEFF(USE_PHASE7_BRAM_STAGE23_COEFF),
        .USE_PHASE8_PACKED_BRAM_STAGE23(USE_PHASE8_PACKED_BRAM_STAGE23),
        .USE_PHASE7_CIC_BURST_COUNTER_DSP(
            USE_PHASE7_CIC_BURST_COUNTER_DSP)
    ) u_demo_interp_dac8_audio_pcm_common (
        .clk_audio_128x (clk_audio_128x_44k1),
        .rst_n          (rst_audio_n),
        .mode_sel       (mode_audio_sync),
        .tone_khz       (tone_audio_state),
        .ila_demo_enable(demo_audio_sync),

        .dac_clk        (dac_clk),
        .dac_data       (dac_data),
        .mode_led       (ila_dac_mode_w),
        .ila_pre2_sample(ila_pre2_sample_w),
        .ila_post2_sample(ila_post2_sample_w),
        .ila_final128_sample(ila_final128_sample_w),
        .ila_ce2_tick(ila_ce2_tick_w),
        .ila_magnitude_15k_pre(ila_magnitude_15k_pre_w),
        .ila_magnitude_15k_post(ila_magnitude_15k_post_w),
        .ila_magnitude_40k_pre(ila_magnitude_40k_pre_w),
        .ila_magnitude_40k_post(ila_magnitude_40k_post_w),
        .ila_suppression_40k_db(ila_suppression_40k_db_w),
        .ila_measurement_valid(ila_measurement_valid_w),
        .ila_rate_tick  (ila_rate_tick_w)
    );

    // AD9708 使用 8bit offset-binary。减去中点 128 后可在 ILA 中按
    // Signed Decimal + Analog 显示真正送往 DAC 的有符号数字波形。
    assign ila_dac_code_w   = dac_data;
    assign ila_dac_signed_w = $signed({1'b0, dac_data}) - 9'sd128;
    assign ila_dac_clk_w    = dac_clk;
    assign ila_rate_1x_tick_w   = ila_rate_tick_w[0];
    assign ila_rate_2x_tick_w   = ila_rate_tick_w[1];
    assign ila_rate_4x_tick_w   = ila_rate_tick_w[2];
    assign ila_rate_8x_tick_w   = ila_rate_tick_w[3];
    assign ila_rate_16x_tick_w  = ila_rate_tick_w[4];
    assign ila_rate_32x_tick_w  = ila_rate_tick_w[5];
    assign ila_rate_64x_tick_w  = ila_rate_tick_w[6];
    assign ila_rate_128x_tick_w = ila_rate_tick_w[7];

    //=========================================================
    // 10）独立100MHz DAC采样时钟测频
    //
    // 使用100ms闸门计数DAC_CLK上升沿。测量结果在100MHz域中每
    // 100ms更新一次，再通过“稳定数据总线 + 翻转标志”送回音频域，
    // ILA中可直接按Unsigned Decimal读取Hz值。
    //=========================================================
    wire [23:0] dac_frequency_hz_100m;
    wire [19:0] dac_frequency_edges_100m;
    wire dac_frequency_toggle_100m;

    dac_clock_frequency_meter #(
        .MEASUREMENT_WINDOW_CYCLES(10000000)
    ) u_dac_clock_frequency_meter (
        .clk_ref_100m       (clk_debug_100m),
        .rst_n              (rst_debug_n),
        .signal_in_async    (dac_clk),
        .frequency_hz       (dac_frequency_hz_100m),
        .edge_count_100ms   (dac_frequency_edges_100m),
        .measurement_toggle (dac_frequency_toggle_100m)
    );

    (* ASYNC_REG = "TRUE" *) reg [23:0] dac_frequency_hz_meta = 24'd0;
    (* ASYNC_REG = "TRUE" *) reg [23:0] dac_frequency_hz_sync = 24'd0;
    (* ASYNC_REG = "TRUE" *) reg [19:0] dac_frequency_edges_meta = 20'd0;
    (* ASYNC_REG = "TRUE" *) reg [19:0] dac_frequency_edges_sync = 20'd0;
    (* ASYNC_REG = "TRUE" *) reg [2:0] dac_frequency_toggle_sync = 3'b000;
    (* keep = "true" *) reg [23:0] ila_dac_freq_hz_w = 24'd0;
    (* keep = "true" *) reg [19:0] ila_dac_freq_edges_100ms_w = 20'd0;
    (* keep = "true" *) reg ila_dac_freq_valid_w = 1'b0;

    always @(posedge clk_audio_128x_44k1 or negedge rst_audio_n) begin
        if (!rst_audio_n) begin
            dac_frequency_hz_meta       <= 24'd0;
            dac_frequency_hz_sync       <= 24'd0;
            dac_frequency_edges_meta    <= 20'd0;
            dac_frequency_edges_sync    <= 20'd0;
            dac_frequency_toggle_sync   <= 3'b000;
            ila_dac_freq_hz_w           <= 24'd0;
            ila_dac_freq_edges_100ms_w  <= 20'd0;
            ila_dac_freq_valid_w        <= 1'b0;
        end
        else begin
            dac_frequency_hz_meta      <= dac_frequency_hz_100m;
            dac_frequency_hz_sync      <= dac_frequency_hz_meta;
            dac_frequency_edges_meta   <= dac_frequency_edges_100m;
            dac_frequency_edges_sync   <= dac_frequency_edges_meta;
            dac_frequency_toggle_sync  <= {dac_frequency_toggle_sync[1:0],
                                           dac_frequency_toggle_100m};
            ila_dac_freq_valid_w       <= dac_frequency_toggle_sync[1] ^
                                          dac_frequency_toggle_sync[2];

            if (dac_frequency_toggle_sync[1] ^
                dac_frequency_toggle_sync[2]) begin
                ila_dac_freq_hz_w          <= dac_frequency_hz_sync;
                ila_dac_freq_edges_100ms_w <= dac_frequency_edges_sync;
            end
        end
    end

    // 4096 深度、统一 5.6448MHz 时基。四个有符号波形探针在
    // Hardware Manager 中设置为 Signed Decimal + Analog；1x～128x
    // 更新脉冲用于显示各级采样率，probe23～probe25显示由独立
    // 100MHz参考时钟得到的DAC_CLK测频结果。
    ila_image_rejection u_ila_image_rejection (
        .clk    (clk_audio_128x_44k1),
        .probe0 (demo_audio_sync),
        .probe1 (ila_pre2_sample_w),
        .probe2 (ila_post2_sample_w),
        .probe3 (ila_final128_sample_w),
        .probe4 (ila_ce2_tick_w),
        .probe5 (ila_magnitude_15k_pre_w),
        .probe6 (ila_magnitude_15k_post_w),
        .probe7 (ila_magnitude_40k_pre_w),
        .probe8 (ila_magnitude_40k_post_w),
        .probe9 (ila_suppression_40k_db_w),
        .probe10(ila_measurement_valid_w),
        .probe11(ila_dac_signed_w),
        .probe12(ila_dac_code_w),
        .probe13(ila_dac_mode_w),
        .probe14(ila_dac_clk_w),
        .probe15(ila_rate_1x_tick_w),
        .probe16(ila_rate_2x_tick_w),
        .probe17(ila_rate_4x_tick_w),
        .probe18(ila_rate_8x_tick_w),
        .probe19(ila_rate_16x_tick_w),
        .probe20(ila_rate_32x_tick_w),
        .probe21(ila_rate_64x_tick_w),
        .probe22(ila_rate_128x_tick_w),
        .probe23(ila_dac_freq_hz_w),
        .probe24(ila_dac_freq_edges_100ms_w),
        .probe25(ila_dac_freq_valid_w)
    );

    // 板载蜂鸣器为 PNP 高边驱动，BEEP-IO 拉低导通。
    // 空闲固定拉高，避免下载后蜂鸣器持续鸣叫。
    assign beep_io = 1'b1;

endmodule


//=============================================================
// 模块名       : matrix_keypad_mode_ctrl
// 功能简述     : 4x4 矩阵按键扫描，并锁存为 DAC 演示模式选择。
//
// 硬件连接：
//   KR[3:0]：扫描输出，只在当前列主动拉低，其他列高阻。
//   KC[3:0]：列/行输入，板上已有 10k 上拉，按下时读到低电平。
//
// 按键映射：
//   SW1 = KC0 + KR0：44.1kHz，1x 原始 PCM
//   SW2 = KC0 + KR1：44.1kHz，4x
//   SW3 = KC0 + KR2：44.1kHz，8x
//   SW4 = KC0 + KR3：44.1kHz，128x
//   SW5 = KC1 + KR0：输入频率 +1kHz
//   SW6 = KC1 + KR1：输入频率 -1kHz
//   SW7 = KC1 + KR2：输入频率恢复 15kHz
//   SW8 = KC1 + KR3：自动扫频开启/关闭
//
// family_sel 为兼容原接口保留，当前板级顶层不再使用。
//=============================================================
module matrix_keypad_mode_ctrl #(
    parameter integer SCAN_DIV       = 20000,  // 20MHz 下每个 KR 扫描约 1ms
    parameter integer DEBOUNCE_SCANS = 5       // 完整 4x4 扫描稳定 5 次后生效
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire [3:0] kc,
    output reg  [3:0] kr_drive_low,

    output reg        family_sel,    // 兼容保留；当前板级顶层忽略
    output reg  [1:0] mode_sel,      // 00=1x，01=4x，10=8x，11=128x
    output reg        key_strobe,    // 消抖后的新按键脉冲，调试用
    output reg  [3:0] key_code       // 0=SW1, 1=SW2, ... 15=SW16
);

    reg [15:0] scan_cnt;
    reg [1:0]  scan_idx;

    reg [3:0] kc_meta;
    reg [3:0] kc_sync;

    wire [3:0] kc_pressed;
    assign kc_pressed = ~kc_sync;

    reg [15:0] scan_bitmap_accum;
    reg [15:0] sampled_bitmap_next;
    reg [15:0] raw_bitmap_prev;
    reg [15:0] debounced_bitmap;
    reg [3:0]  stable_cnt;

    function [3:0] first_key_code;
        input [15:0] bitmap;
        begin
            casez (bitmap)
                16'b???????????????1: first_key_code = 4'd0;
                16'b??????????????10: first_key_code = 4'd1;
                16'b?????????????100: first_key_code = 4'd2;
                16'b????????????1000: first_key_code = 4'd3;
                16'b???????????10000: first_key_code = 4'd4;
                16'b??????????100000: first_key_code = 4'd5;
                16'b?????????1000000: first_key_code = 4'd6;
                16'b????????10000000: first_key_code = 4'd7;
                16'b???????100000000: first_key_code = 4'd8;
                16'b??????1000000000: first_key_code = 4'd9;
                16'b?????10000000000: first_key_code = 4'd10;
                16'b????100000000000: first_key_code = 4'd11;
                16'b???1000000000000: first_key_code = 4'd12;
                16'b??10000000000000: first_key_code = 4'd13;
                16'b?100000000000000: first_key_code = 4'd14;
                16'b1000000000000000: first_key_code = 4'd15;
                default:              first_key_code = 4'd0;
            endcase
        end
    endfunction

    always @(*) begin
        sampled_bitmap_next = scan_bitmap_accum;

        sampled_bitmap_next[scan_idx]      = kc_pressed[0];
        sampled_bitmap_next[4 + scan_idx]  = kc_pressed[1];
        sampled_bitmap_next[8 + scan_idx]  = kc_pressed[2];
        sampled_bitmap_next[12 + scan_idx] = kc_pressed[3];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            kc_meta <= 4'hF;
            kc_sync <= 4'hF;
        end
        else begin
            kc_meta <= kc;
            kc_sync <= kc_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_cnt          <= 16'd0;
            scan_idx          <= 2'd0;
            kr_drive_low      <= 4'b0001;

            scan_bitmap_accum <= 16'd0;
            raw_bitmap_prev   <= 16'd0;
            debounced_bitmap  <= 16'd0;
            stable_cnt        <= 4'd0;

            family_sel        <= 1'b0;
            mode_sel          <= 2'b11;  // 上电默认 128x，DA_CLK=5.6448MHz
            key_strobe        <= 1'b0;
            key_code          <= 4'd0;
        end
        else begin
            key_strobe <= 1'b0;

            if (scan_cnt == SCAN_DIV - 1) begin
                scan_cnt <= 16'd0;

                if (scan_idx == 2'd3) begin
                    scan_idx          <= 2'd0;
                    kr_drive_low      <= 4'b0001;
                    scan_bitmap_accum <= 16'd0;

                    if (sampled_bitmap_next == raw_bitmap_prev) begin
                        if (stable_cnt < DEBOUNCE_SCANS) begin
                            stable_cnt <= stable_cnt + 4'd1;
                        end
                        else if (debounced_bitmap != sampled_bitmap_next) begin
                            debounced_bitmap <= sampled_bitmap_next;

                            if (|sampled_bitmap_next) begin
                                key_strobe <= 1'b1;
                                key_code   <= first_key_code(sampled_bitmap_next);

                                case (first_key_code(sampled_bitmap_next))
                                    4'd0: begin
                                        family_sel <= 1'b0;
                                        mode_sel   <= 2'b00;
                                    end

                                    4'd1: begin
                                        family_sel <= 1'b0;
                                        mode_sel   <= 2'b01;
                                    end

                                    4'd2, 4'd3: begin
                                        family_sel <= 1'b0;
                                        mode_sel   <= (first_key_code(sampled_bitmap_next) == 4'd2) ?
                                                      2'b10 : 2'b11;
                                    end

                                    4'd4, 4'd5, 4'd6, 4'd7: begin
                                        family_sel <= 1'b1;
                                        mode_sel   <= mode_sel;
                                    end

                                    default: begin
                                        family_sel <= family_sel;
                                        mode_sel   <= mode_sel;
                                    end
                                endcase
                            end
                        end
                    end
                    else begin
                        raw_bitmap_prev <= sampled_bitmap_next;
                        stable_cnt      <= 4'd0;
                    end
                end
                else begin
                    scan_idx          <= scan_idx + 2'd1;
                    kr_drive_low      <= (4'b0001 << (scan_idx + 2'd1));
                    scan_bitmap_accum <= sampled_bitmap_next;
                end
            end
            else begin
                scan_cnt <= scan_cnt + 16'd1;
            end
        end
    end

endmodule
