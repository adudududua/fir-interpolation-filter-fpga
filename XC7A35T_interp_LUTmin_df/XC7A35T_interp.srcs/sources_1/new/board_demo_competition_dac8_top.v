`timescale 1ns / 1ps

//=============================================================
// 文件名       : board_demo_competition_dac8_top.v
// 模块名       : board_demo_competition_dac8_top
// 功能简述     : XC7A35T 全国总决赛完整板级验证顶层。集成双采样率四倍率插值链、AD9708 接口、矩阵按键、固定 100BASE-TX RGMII、ARP、UDP 波形上传与 DAC 前 24 位数字节点回传。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
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
    // 板级图形界面的默认参数必须与已签核的全国总决赛构建一致。
    // 旧版及区域赛封装仍可选择各自的参数值。
    parameter integer USE_NATIONAL_FINALS_SERIAL_CIC_COMB = 1,
    parameter integer USE_NATIONAL_FINALS_N3_HOLD_EQUIV = 1,
    parameter integer USE_NATIONAL_FINALS_CIC_COMB_DSP = 0,
    parameter integer USE_NATIONAL_FINALS_STAGE1_DSP48_PREADDER = 1,
    parameter integer USE_NATIONAL_FINALS_NARROW_STAGE23 = 1,
    parameter integer USE_NATIONAL_FINALS_P3_JOINT_STAGE3 = 1,
    parameter integer USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE = 2,
    parameter integer USE_NATIONAL_FINALS_STAGE2_DATA_W = 20
)(
    input  wire       clk,       // 板载 20MHz 系统时钟

    output wire [3:0] key_kr,    // 矩阵按键 KR0~KR3，扫描输出
    input  wire [3:0] key_kc,    // 矩阵按键 KC0~KC3，带外部上拉输入

    output wire       dac_clk,   // AD9708 DA_CLK
    output wire [7:0] dac_data,  // AD9708 DA_D0~DA_D7

    output wire       beep_io,   // 蜂鸣器控制，低电平响，高电平关闭

    // RTL8211E RGMII 接口。首版仅发送 100BASE-TX 广播 UDP；
    // RX/MDIO 接口保留，供后续扩展使用。
    output wire       mac_rst,
    input  wire       mac_intb,
    input  wire       mac_rxclk,
    input  wire       mac_rxctl,
    input  wire [3:0] mac_rxd,
    output wire       mac_txclk,
    output wire       mac_txctl,
    output wire [3:0] mac_txd,
    output wire       eth_mdc,
    inout  wire       eth_mdio
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
    wire clk_net_25m;
    wire clk_net_25m_unbuf;
    wire clk_net_txc_25m;
    wire clk_net_txc_25m_unbuf;
    wire clk_net_fb;
    wire clk_net_locked;

    IBUF u_ibuf_sys_clk (
        .I(clk),
        .O(clk_ibuf)
    );

    BUFG u_bufg_sys_clk (
        .I(clk_ibuf),
        .O(clk_sys_bufg)
    );

    // 网络专用 MMCM：将 20 MHz 转换为 100BASE-TX RGMII 所需的 25 MHz。
    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(50.0),
        .CLKIN1_PERIOD(50.0),
        .CLKOUT0_DIVIDE_F(40.0),
        .CLKOUT1_DIVIDE(40),
        .CLKOUT1_PHASE(18.0),
        .DIVCLK_DIVIDE(1),
        .STARTUP_WAIT("FALSE")
    ) u_net_mmcm (
        .CLKIN1   (clk_sys_bufg),
        .CLKFBIN  (clk_net_fb),
        .RST      (1'b0),
        .PWRDWN   (1'b0),
        .CLKFBOUT (clk_net_fb),
        .CLKOUT0  (clk_net_25m_unbuf),
        .CLKOUT1  (clk_net_txc_25m_unbuf),
        .LOCKED   (clk_net_locked),
        .CLKOUT2  (), .CLKOUT3(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .CLKFBOUTB(), .CLKOUT0B(), .CLKOUT1B(), .CLKOUT2B(), .CLKOUT3B()
    );

    BUFG u_bufg_net_25m (
        .I(clk_net_25m_unbuf),
        .O(clk_net_25m)
    );

    // 原理图将 RTL8211E 的 TXDLY 配置为低电平（“TX/RX 无延时”）。
    // 在 25 MHz 下，将转发 TXC 移相 18 度可产生 2.0 ns 延时，
    // 使 PHY 在 100 Mb/s 发送半字节窗口的中心附近采样。
    BUFG u_bufg_net_txc_25m (
        .I(clk_net_txc_25m_unbuf),
        .O(clk_net_txc_25m)
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

    // RTL8211E 启动时序：系统上电复位完成且网络 MMCM 锁定后，
    // 将 RST_N 保持低电平 20 ms；随后再等待 30 ms 才允许发送首个
    // 以太网帧。该计数器工作在 20 MHz 时钟域。
    reg [19:0] phy_seq_count = 20'd0;
    wire phy_reset_released;
    wire net_start_request;
    (* ASYNC_REG = "TRUE" *) reg [1:0] net_rst_sync = 2'b00;
    wire net_rst_n;

    always @(posedge clk_sys_bufg) begin
        if (!rst_n_int || !clk_net_locked)
            phy_seq_count <= 20'd0;
        else if (phy_seq_count < 20'd1000000)
            phy_seq_count <= phy_seq_count + 20'd1;
    end

    assign phy_reset_released = (phy_seq_count >= 20'd400000);
    assign net_start_request  = (phy_seq_count >= 20'd1000000);
    assign mac_rst            = phy_reset_released;

    // net_start_request 与 clk_net_25m 异步。复位立即置位，
    // 经过两个网络时钟边沿后再同步释放。
    always @(posedge clk_net_25m or negedge net_start_request) begin
        if (!net_start_request)
            net_rst_sync <= 2'b00;
        else
            net_rst_sync <= {net_rst_sync[0], 1'b1};
    end

    assign net_rst_n = net_rst_sync[1];

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
    // 已签核构建中的 pwr_rst_cnt 会为紧凑按键扫描节拍持续运行。这里复用
    // 它的低 10 位作为 1024 周期的采样率家族切换时基，避免再建立一个宽
    // 计数器。状态 1 在下一节拍提交新家族；状态 2～4 在时钟切换后精确保持
    // 数据通路静音/复位 3072 个时钟。未复用计数器的参数分支保留独立保护
    // 计数器，使 pwr_rst_cnt 会饱和的旧配置仍能正常工作。
    wire       family_switch_busy;
    wire       family_active;
    wire       clk_audio_128x;
    wire       mmcm_locked_selected_unused;
    wire       mmcm_locked_44k1;
    wire       mmcm_locked_48k;

    generate
        if (USE_SHARED_KEYPAD_SCAN_TICK != 0) begin : gen_shared_family_guard
            // 用独热移位状态替代原来的 3 位递增器以及 state==1/state==4
            // 比较。第一拍提交新家族，随后三拍继续保持复位/静音再返回空闲；
            // 该结构多用一个触发器，但可缩小控制逻辑锥。
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

    // 将异步复位置位限制在上面的同步器内。这个附加寄存器只在音频时钟
    // 边沿变化，使所有 FIR/CIC/DSP/BRAM 控制逻辑只看到纯同步复位源。
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

    // 数据通路保持复位时仍跟踪所选采样率家族。双速率 ROM 会在复位分支
    // 采样此值，从而选择地址 0（44.1 kHz）或 147（48 kHz）。若该同步器
    // 随数据通路一起清零，48 kHz 的首个样本就会错误地来自地址 0。
    always @(posedge clk_audio_128x) begin
        family_audio_meta <= family_active;
        family_audio_sync <= family_audio_meta;
    end

    //=========================================================
    // 7）实例化 44.1kHz 专用全 2x 插值 DAC 公共模块
    //=========================================================
    wire [1:0] mode_led_unused;
    wire signed [23:0] monitor_sample;
    wire               monitor_valid;
    wire [31:0]        monitor_sample_index;
    wire signed [23:0] upload_sample;
    wire               upload_sample_update;
    wire               upload_source_active;
    wire               upload_pipeline_reset_pulse;
    wire               upload_family_48k;
    wire [1:0]         upload_mode;
    wire [31:0]        upload_transaction_id;
    wire               input_sample_ce;
    wire               upload_family_match =
                       (upload_family_48k == family_audio_sync);
    // 上传 RAM 只替换 1x 输入样本，不拥有输出倍率控制权。
    // 输出倍率始终由实体矩阵按键决定（SW1~SW4 对应 44.1 kHz，
    // SW5~SW8 对应 48 kHz）。否则一旦上传事务在 4x 模式提交，
    // upload_mode 会持续覆盖按键，使用户之后按 SW8 也无法切回 128x。
    // upload_mode 仍保留为事务描述符，供协议校验和状态回显使用。
    wire [1:0]         effective_mode_sel = mode_audio_atomic;
    // 上传采样率族与当前物理音频时钟不一致时，不让它复位当前数据通路。
    wire               common_rst_n = rst_audio_n &&
                                      !(upload_pipeline_reset_pulse &&
                                        upload_family_match);

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
        .rst_n          (common_rst_n),
        .family_48k     (family_audio_sync),
        .mode_sel       (effective_mode_sel),
        .force_mute     (mode_audio_mute),
        .external_source_enable(upload_source_active && upload_family_match),
        .external_sample(upload_sample),
        .external_sample_update(upload_sample_update && upload_family_match),
        .input_sample_ce(input_sample_ce),

        .dac_clk        (dac_clk),
        .dac_data       (dac_data),
        .mode_led       (mode_led_unused),
        .monitor_sample (monitor_sample),
        .monitor_valid  (monitor_valid),
        .monitor_sample_index(monitor_sample_index)
    );

    // 首版仅发送广播，不需要 RX 或 MDIO 事务；RTL8211E 根据板上
    // 上下拉配置完成自动协商。
    assign eth_mdc  = 1'b0;
    assign eth_mdio = 1'bz;

    dac24_udp_network_top u_dac24_udp_network (
        .audio_clk          (clk_audio_128x),
        .monitor_sample     (monitor_sample),
        .monitor_valid      (monitor_valid),
        .monitor_sample_index(monitor_sample_index),
        .monitor_mode       (mode_led_unused),
        .monitor_family_48k (family_audio_sync),
        .net_clk_25m        (clk_net_25m),
        .net_txc_clk_25m    (clk_net_txc_25m),
        .net_rst_n          (net_rst_n),
        .mac_rxc            (mac_rxclk),
        .mac_rxctl          (mac_rxctl),
        .mac_rxd            (mac_rxd),
        .upload_sample      (upload_sample),
        .upload_sample_update(upload_sample_update),
        .upload_source_active(upload_source_active),
        .upload_pipeline_reset_pulse(upload_pipeline_reset_pulse),
        .upload_family_48k  (upload_family_48k),
        .upload_mode        (upload_mode),
        .upload_transaction_id(upload_transaction_id),
        .input_sample_ce    (input_sample_ce),
        .mac_txc            (mac_txclk),
        .mac_txctl          (mac_txctl),
        .mac_txd            (mac_txd)
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
