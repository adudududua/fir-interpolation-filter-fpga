`timescale 1ns / 1ps
//=============================================================
// 文件名       : board_demo_competition_dac8_top.v
// 模块名       : board_demo_competition_dac8_top
// 功能简述     : Artix-7 XC7A35T 全国总决赛双采样率、三倍率
//                AD9708 DAC 板级演示顶层。
//                20 MHz -> 双 MMCM -> 5.6448/6.144 MHz
//                矩阵按键选择 44.1/48 kHz 与 1x/4x/8x/128x。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-06-20
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
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
// 其他描述     :
//                1. SW1/SW2/SW3/SW4：1x/4x/8x/128x。
//                2. SW5/SW6/SW7/SW8：重复映射 1x/4x/8x/128x。
//=============================================================
//=============================================================
// 1）模块名称：board_demo_competition_dac8_top
// 功能说明：板级演示顶层：连接时钟、按键、插值滤波链与 DAC 输出接口。
// 工程版本：Vivado 2025.2。
//=============================================================

module board_demo_competition_dac8_top #(
    parameter integer USE_PHASE7_LUTRAM_STAGE23 = 1,
    parameter integer USE_COMPACT_KEYPAD = 1,
    parameter integer USE_ULTRACOMPACT_KEYPAD = 1,
    parameter integer COMPACT_KEYPAD_SCAN_DIV = 20000,
    parameter integer USE_SHARED_KEYPAD_SCAN_TICK = 1,
    parameter integer USE_PHASE7_BRAM_STAGE23_HISTORY = 1,
    parameter integer USE_PHASE7_UNIFIED_BRAM_STAGE23_HISTORY = 1,
    parameter integer USE_NATIONAL_FINALS_SINGLE_BRAM_STAGE1 = 1,
    parameter integer USE_PHASE7_BRAM_STAGE23_COEFF = 1,
    parameter integer USE_PHASE8_PACKED_BRAM_STAGE23 = 0,
    parameter integer USE_PHASE7_CIC_BURST_COUNTER_DSP = 0,
    parameter integer USE_NATIONAL_FINALS_DATAPATH = 1,
    // 板级GUI的默认结构必须与全国赛签核配置一致；历史或区域赛包装层
    // 仍可通过自身参数选择其它候选结构，不影响本顶层的正式发布默认值。
    parameter integer USE_NATIONAL_FINALS_SERIAL_CIC_COMB = 1,
    parameter integer USE_NATIONAL_FINALS_N3_HOLD_EQUIV = 1,
    parameter integer USE_NATIONAL_FINALS_CIC_COMB_DSP = 0,
    parameter integer USE_NATIONAL_FINALS_STAGE1_DSP48_PREADDER = 1,
    parameter integer USE_NATIONAL_FINALS_NARROW_STAGE23 = 1,
    parameter integer USE_NATIONAL_FINALS_P3_JOINT_STAGE3 = 1,
    parameter integer USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE = 1,
    parameter integer USE_NATIONAL_FINALS_STAGE2_DATA_W = 20
)(
    input  wire       clk,       // 板载 20MHz 系统时钟

    output wire [3:0] key_kr,    // 矩阵按键 KR0~KR3，扫描输出
    input  wire [3:0] key_kc,    // 矩阵按键 KC0~KC3，带外部上拉输入

    output wire       dac_clk,   // AD9708 DA_CLK
    output wire [7:0] dac_data,  // AD9708 DA_D0~DA_D7

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

    // 例化说明：调用输入缓冲原语，把板级引脚信号可靠接入 FPGA 内部逻辑。
    IBUF u_ibuf_sys_clk (
        .I(clk),
        .O(clk_ibuf)
    );

    // 例化说明：调用全局时钟缓冲原语，把选定时钟接入 FPGA 低偏斜全局时钟网络。
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
    wire       key_family_sel;
    wire [1:0] key_mode_sel;
    wire       key_strobe_unused;
    wire [3:0] key_code_unused;

    assign key_kr[0] = key_kr_drive_low[0] ? 1'b0 : 1'bz;
    assign key_kr[1] = key_kr_drive_low[1] ? 1'b0 : 1'bz;
    assign key_kr[2] = key_kr_drive_low[2] ? 1'b0 : 1'bz;
    assign key_kr[3] = key_kr_drive_low[3] ? 1'b0 : 1'bz;

    generate
        if (USE_COMPACT_KEYPAD != 0) begin : gen_compact_keypad
            if (USE_ULTRACOMPACT_KEYPAD != 0) begin : gen_ultracompact
                // 例化说明：调用 matrix_keypad_mode_ctrl_ultracompact 键盘控制模块，完成扫描、消抖、译码和模式更新。
                matrix_keypad_mode_ctrl_ultracompact #(
                    .SCAN_DIV               (COMPACT_KEYPAD_SCAN_DIV),
                    .USE_EXTERNAL_SCAN_TICK (USE_SHARED_KEYPAD_SCAN_TICK)
                ) u_matrix_keypad_mode_ctrl_ultracompact (
                    .clk          (clk_sys_bufg),
                    .rst_n        (rst_n_int),
                    .scan_tick    (compact_keypad_scan_tick),
                    .kc           (key_kc),
                    .kr_drive_low (key_kr_drive_low),
                    .family_sel   (key_family_sel),
                    .mode_sel     (key_mode_sel)
                );
            end
            else begin : gen_original_compact
                // 例化说明：调用 matrix_keypad_mode_ctrl_compact 键盘控制模块，完成扫描、消抖、译码和模式更新。
                matrix_keypad_mode_ctrl_compact #(
                    .SCAN_DIV               (COMPACT_KEYPAD_SCAN_DIV),
                    .USE_EXTERNAL_SCAN_TICK (USE_SHARED_KEYPAD_SCAN_TICK)
                ) u_matrix_keypad_mode_ctrl_compact (
                    .clk          (clk_sys_bufg),
                    .rst_n        (rst_n_int),
                    .scan_tick    (compact_keypad_scan_tick),
                    .kc           (key_kc),
                    .kr_drive_low (key_kr_drive_low),
                    .family_sel   (key_family_sel),
                    .mode_sel     (key_mode_sel)
                );
            end

            assign key_strobe_unused = 1'b0;
            assign key_code_unused = 4'd0;
        end
        else begin : gen_full_keypad
            // 例化说明：调用 matrix_keypad_mode_ctrl 键盘控制模块，完成扫描、消抖、译码和模式更新。
            matrix_keypad_mode_ctrl u_matrix_keypad_mode_ctrl (
                .clk          (clk_sys_bufg),
                .rst_n        (rst_n_int),
                .kc           (key_kc),
                .kr_drive_low (key_kr_drive_low),
                .family_sel   (key_family_sel),
                .mode_sel     (key_mode_sel),
                .key_strobe   (key_strobe_unused),
                .key_code     (key_code_unused)
            );
        end
    endgenerate

    //=========================================================
    // 4）全国赛双采样率时钟与受控家族切换
    //
    // 输入：
    //   clk_sys_bufg = 20MHz
    //
    //   family=0 -> 5.6448 MHz -> 44.1 kHz 输入家族
    //   family=1 -> 6.1440 MHz -> 48.0 kHz 输入家族
    //
    // 家族改变时先把音频数据通路保持复位，再切 BUFGMUX_CTRL，
    // 最后在新时钟域同步释放复位，防止跨采样率遗留滤波状态。
    //=========================================================
    // 签核构建已让pwr_rst_cnt自由运行，以提供紧凑键盘扫描节拍；这里复用
    // 其低10位形成1024周期的采样率家族切换时基，避免再建一个宽计数器。
    // 状态1在下一节拍提交新家族，状态2～4在切钟后准确保持复位/静音
    // 3072个时钟。非共享参数分支仍保留独立保护计数器，使pwr_rst_cnt
    // 饱和停止的历史配置仍然可用。
    wire       family_switch_busy;
    wire       family_active;
    wire       clk_audio_128x;
    wire       mmcm_locked_selected_unused;
    wire       mmcm_locked_44k1;
    wire       mmcm_locked_48k;

    generate
        if (USE_SHARED_KEYPAD_SCAN_TICK != 0) begin : gen_shared_family_guard
        // 独热移位状态替代原3位加法器及state==1/state==4比较。首个节拍
        // 提交新家族，之后3个节拍继续保持复位/静音，再返回空闲；多用1个
        // FF换取更小的控制组合锥和更明确的时序行为。
            reg [3:0] family_switch_state = 4'd0;
            reg       family_active_r = 1'b0;
            wire      family_switch_tick;

            assign family_switch_tick = &pwr_rst_cnt[9:0];
            assign family_switch_busy = |family_switch_state;
            assign family_active = family_active_r;

            always @(posedge clk_sys_bufg) begin
                if (!rst_n_int) begin
                    family_switch_state <= 4'd0;
                    family_active_r <= 1'b0;
                end
                else if (family_switch_state != 4'd0) begin
                    if (family_switch_tick) begin
                        if (family_switch_state[0])
                            family_active_r <= key_family_sel;
                        family_switch_state <=
                            {family_switch_state[2:0], 1'b0};
                    end
                end
                else if (key_family_sel != family_active_r) begin
                    family_switch_state <= 4'b0001;
                end
            end
        end
        else begin : gen_dedicated_family_guard
            reg [11:0] family_switch_count = 12'd0;
            reg        family_switch_busy_r = 1'b0;
            reg        family_active_r = 1'b0;

            assign family_switch_busy = family_switch_busy_r;
            assign family_active = family_active_r;

            always @(posedge clk_sys_bufg) begin
                if (!rst_n_int) begin
                    family_switch_count <= 12'd0;
                    family_switch_busy_r <= 1'b0;
                    family_active_r <= 1'b0;
                end
                else if (family_switch_busy_r) begin
                    if (family_switch_count == 12'd1023)
                        family_active_r <= key_family_sel;

                    if (family_switch_count == 12'd4095) begin
                        family_switch_count <= 12'd0;
                        family_switch_busy_r <= 1'b0;
                    end
                    else begin
                        family_switch_count <= family_switch_count + 12'd1;
                    end
                end
                else if (key_family_sel != family_active_r) begin
                    family_switch_count <= 12'd0;
                    family_switch_busy_r <= 1'b1;
                end
            end
        end
    endgenerate

    // 例化说明：调用 dual_family_audio_clock 双采样率族模块，完成时钟或测试数据的族别选择。
    dual_family_audio_clock u_dual_family_audio_clock (
        .clk_20m(clk_sys_bufg),
        .reset(~rst_n_int),
        .family_48k(family_active),
        .clk_audio_128x(clk_audio_128x),
        .locked_selected(mmcm_locked_selected_unused),
        .locked_44k1(mmcm_locked_44k1),
        .locked_48k(mmcm_locked_48k)
    );

    //=========================================================
    // 5）音频时钟域复位同步
    //
    // rst_audio_sync：
    //   在当前选择的音频时钟域内释放复位。
    //
    // rst_audio_n：
    //   送给正式插值公共模块。
    //=========================================================
    (* ASYNC_REG = "TRUE" *) reg [1:0] locked_44k1_sync = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] locked_48k_sync = 2'b00;
    reg rst_audio_request_n_sys = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg [1:0] rst_request_sync = 2'b00;
    reg [2:0] rst_audio_sync = 3'b000;

    wire rst_audio_async_n;
    assign rst_audio_async_n = rst_audio_request_n_sys;

    always @(posedge clk_sys_bufg) begin
        locked_44k1_sync <= {locked_44k1_sync[0], mmcm_locked_44k1};
        locked_48k_sync <= {locked_48k_sync[0], mmcm_locked_48k};

        if (!rst_n_int)
            rst_audio_request_n_sys <= 1'b0;
        else
            rst_audio_request_n_sys <= !family_switch_busy &&
                (family_active ? locked_48k_sync[1] : locked_44k1_sync[1]);
    end

    always @(posedge clk_audio_128x) begin
        rst_request_sync <= {rst_request_sync[0], rst_audio_async_n};
        rst_audio_sync <= {rst_audio_sync[1:0], rst_request_sync[1]};
    end

    // 将异步断言限制在上方复位同步器内部；本级寄存器仅在音频时钟沿变化，
    // 因而所有FIR/CIC/DSP/BRAM控制看到的都是纯同步复位源。
    reg rst_audio_datapath_n = 1'b0;

    always @(posedge clk_audio_128x) begin
        if (!rst_audio_sync[2])
            rst_audio_datapath_n <= 1'b0;
        else
            rst_audio_datapath_n <= 1'b1;
    end

    wire rst_audio_n;
    assign rst_audio_n = rst_audio_datapath_n;

    //=========================================================
    // 6）模式控制跨时钟域同步
    //
    // key_mode_sel 在 20MHz 按键扫描时钟域产生，送入 5.6448MHz
    // 音频域前使用两级同步器。按键模式在消抖后长时间保持稳定，
    // 因此逐位同步不会影响实际模式切换。
    //=========================================================
    wire [1:0] mode_audio_atomic;
    wire       mode_audio_mute;
    wire       mode_ctrl_busy_unused;

    // 例化说明：调用 nf_mode_cdc_handshake 全国赛签核子模块，完成正式数据通路中的存储、运算或控制任务。
    nf_mode_cdc_handshake u_nf_mode_cdc_handshake (
        .ctrl_clk    (clk_sys_bufg),
        .ctrl_rst_n  (rst_n_int),
        .ctrl_mode   (key_mode_sel),
        .ctrl_busy   (mode_ctrl_busy_unused),
        .audio_clk   (clk_audio_128x),
        .audio_rst_n (rst_audio_n),
        .audio_mode  (mode_audio_atomic),
        .audio_mute  (mode_audio_mute)
    );

    (* ASYNC_REG = "TRUE" *) reg family_audio_meta = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg family_audio_sync = 1'b0;

    // 数据通路处于复位时仍持续跟踪所选采样率家族。双速率ROM在复位分支
    // 采样该值，以选择地址0（44.1 kHz）或147（48 kHz）；若该同步器也随
    // 数据通路复位清零，48 kHz模式的首个样本就会错误地来自地址0。
    always @(posedge clk_audio_128x) begin
        family_audio_meta <= family_active;
        family_audio_sync <= family_audio_meta;
    end

    //=========================================================
    // 7）实例化 44.1kHz 专用全 2x 插值 DAC 公共模块
    //=========================================================
    wire [1:0] mode_led_unused;

    // 例化说明：调用 demo_interp_dac8_audio_pcm_common 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    demo_interp_dac8_audio_pcm_common #(
        .USE_PHASE7_FOLDED(1),
        .USE_PHASE7_LUTRAM_STAGE23(USE_PHASE7_LUTRAM_STAGE23),
        .USE_PHASE7_BRAM_STAGE23_HISTORY(USE_PHASE7_BRAM_STAGE23_HISTORY),
        .USE_PHASE7_UNIFIED_BRAM_STAGE23_HISTORY(
            USE_PHASE7_UNIFIED_BRAM_STAGE23_HISTORY),
        .USE_NATIONAL_FINALS_SINGLE_BRAM_STAGE1(
            USE_NATIONAL_FINALS_SINGLE_BRAM_STAGE1),
        .USE_PHASE7_BRAM_STAGE23_COEFF(USE_PHASE7_BRAM_STAGE23_COEFF),
        .USE_PHASE8_PACKED_BRAM_STAGE23(USE_PHASE8_PACKED_BRAM_STAGE23),
        .USE_PHASE7_CIC_BURST_COUNTER_DSP(
            USE_PHASE7_CIC_BURST_COUNTER_DSP),
        .USE_NATIONAL_FINALS_DATAPATH(USE_NATIONAL_FINALS_DATAPATH),
        .USE_NATIONAL_FINALS_SERIAL_CIC_COMB(
            USE_NATIONAL_FINALS_SERIAL_CIC_COMB),
        .USE_NATIONAL_FINALS_N3_HOLD_EQUIV(
            USE_NATIONAL_FINALS_N3_HOLD_EQUIV),
        .USE_NATIONAL_FINALS_CIC_COMB_DSP(
            USE_NATIONAL_FINALS_CIC_COMB_DSP),
        .USE_NATIONAL_FINALS_STAGE1_DSP48_PREADDER(
            USE_NATIONAL_FINALS_STAGE1_DSP48_PREADDER),
        .USE_NATIONAL_FINALS_NARROW_STAGE23(
            USE_NATIONAL_FINALS_NARROW_STAGE23),
        .USE_NATIONAL_FINALS_P3_JOINT_STAGE3(
            USE_NATIONAL_FINALS_P3_JOINT_STAGE3),
        .USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE(
            USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE),
        .USE_NATIONAL_FINALS_STAGE2_DATA_W(
            USE_NATIONAL_FINALS_STAGE2_DATA_W)
    ) u_demo_interp_dac8_audio_pcm_common (
        .clk_audio_128x (clk_audio_128x),
        .rst_n          (rst_audio_n),
        .family_48k     (family_audio_sync),
        .mode_sel       (mode_audio_atomic),
        .force_mute     (mode_audio_mute),

        .dac_clk        (dac_clk),
        .dac_data       (dac_data),
        .mode_led       (mode_led_unused)
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
//   SW5 = KC1 + KR0：44.1kHz，1x 原始 PCM
//   SW6 = KC1 + KR1：44.1kHz，4x
//   SW7 = KC1 + KR2：44.1kHz，8x
//   SW8 = KC1 + KR3：44.1kHz，128x
//
// family_sel 为兼容原接口保留，当前板级顶层不再使用。
//=============================================================
//=============================================================
// 2）模块名称：matrix_keypad_mode_ctrl
// 功能说明：矩阵键盘控制器：完成行列扫描、消抖、按键译码与模式更新。
// 工程版本：Vivado 2025.2。
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

                                    4'd4: begin
                                        family_sel <= 1'b1;
                                        mode_sel   <= 2'b00;
                                    end

                                    4'd5: begin
                                        family_sel <= 1'b1;
                                        mode_sel   <= 2'b01;
                                    end

                                    4'd6, 4'd7: begin
                                        family_sel <= 1'b1;
                                        mode_sel   <= (first_key_code(sampled_bitmap_next) == 4'd6) ?
                                                      2'b10 : 2'b11;
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
