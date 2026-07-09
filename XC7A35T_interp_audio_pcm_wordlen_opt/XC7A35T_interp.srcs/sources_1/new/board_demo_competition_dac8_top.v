`timescale 1ns / 1ps
//=============================================================
// 文件名       : board_demo_competition_dac8_top.v
// 模块名       : board_demo_competition_dac8_top
// 功能简述     : Artix-7 XC7A35T 赛方板 AD9708 DAC 双频率家族
//                插值演示顶层。
//                本版本恢复原先已验证可运行的双 MMCM + BUFGMUX
//                结构：
//                20MHz -> clk_wiz_audio_44k1 -> 5.6448MHz
//                20MHz -> clk_wiz_audio_48k  -> 6.144MHz
//                矩阵按键选择当前音频 128x 时钟家族和插值倍率。
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
// 其他描述     :
//                1. SW1/SW2/SW3：44.1kHz 家族 4x/8x/128x。
//                2. SW5/SW6/SW7：48kHz 家族 4x/8x/128x。
//=============================================================

module board_demo_competition_dac8_top (
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
    wire       rst_n_int;

    always @(posedge clk_sys_bufg) begin
        if (pwr_rst_cnt != 16'hFFFF)
            pwr_rst_cnt <= pwr_rst_cnt + 16'd1;
        else
            pwr_rst_cnt <= pwr_rst_cnt;
    end

    assign rst_n_int = (pwr_rst_cnt == 16'hFFFF);

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

    //=========================================================
    // 4）Clock Wizard：48kHz 家族
    //
    // 输入：
    //   clk_sys_bufg = 20MHz
    //
    // 输出：
    //   clk_audio_128x_48k = 6.144MHz
    //
    // 注意：
    //   这里恢复你原来已验证的写法：
    //   clkfb_in 和 clkfb_out 直接通过同一个 wire 相连。
    //   不再额外插入外部 BUFG。
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
    // 5）Clock Wizard：44.1kHz 家族
    //
    // 输入：
    //   clk_sys_bufg = 20MHz
    //
    // 输出：
    //   clk_audio_128x_44k1 = 5.6448MHz
    //
    // 同样恢复原先已验证的反馈连接方式。
    //=========================================================
    wire clk_audio_128x_44k1;
    wire mmcm_locked_44k1;
    wire clkfb_44k1;

    clk_wiz_audio_44k1 u_clk_wiz_audio_44k1 (
        .clk_out1  (clk_audio_128x_44k1),
        .reset     (~rst_n_int),
        .locked    (mmcm_locked_44k1),
        .clk_in1   (clk_sys_bufg),
        .clkfb_in  (clkfb_44k1),
        .clkfb_out (clkfb_44k1)
    );

    //=========================================================
    // 6）BUFGMUX 选择两个频率家族
    //
    // key_family_sel = 0：
    //   选择 I0，即 44.1kHz 家族 5.6448MHz。
    //
    // key_family_sel = 1：
    //   选择 I1，即 48kHz 家族 6.144MHz。
    //
    // 建议：
    //   切换频率家族时，BUFGMUX 会异步切换到另一只 MMCM。
    //   板级测试时建议先按目标频率家族，再测 DA_CLK。
    //=========================================================
    wire clk_audio_128x_sel;

    BUFGMUX #(
        .CLK_SEL_TYPE("ASYNC")
    ) u_bufgmux_audio_clk (
        .O  (clk_audio_128x_sel),
        .I0 (clk_audio_128x_44k1),
        .I1 (clk_audio_128x_48k),
        .S  (key_family_sel)
    );

    // 当前被选择的 MMCM locked 信号
    wire mmcm_locked_sel;

    assign mmcm_locked_sel = key_family_sel ? mmcm_locked_48k : mmcm_locked_44k1;

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

    always @(posedge clk_audio_128x_sel or negedge rst_n_int) begin
        if (!rst_n_int) begin
            rst_audio_sync <= 3'b000;
        end
        else if (!mmcm_locked_sel) begin
            rst_audio_sync <= 3'b000;
        end
        else begin
            rst_audio_sync <= {rst_audio_sync[1:0], 1'b1};
        end
    end

    wire rst_audio_n;

    assign rst_audio_n = rst_audio_sync[2];

    //=========================================================
    // 8）实例化正式插值 DAC 公共模块
    //
    // 注意：
    //   如果你当前正式公共模块名字是：
    //     demo_interp_dac8_mmcm48_common
    //   就使用下面这个实例。
    //
    //   如果你的工程里模块名仍然叫：
    //     demo_interp_dac8_mmcm_common
    //   那只需要把实例化模块名改成 demo_interp_dac8_mmcm_common。
    //=========================================================
    wire [1:0] mode_led_unused;

    // demo_interp_dac8_mmcm48_common u_demo_interp_dac8_mmcm48_common (
    demo_interp_dac8_audio_pcm_common u_demo_interp_dac8_audio_pcm_common (
        .clk_audio_128x (clk_audio_128x_sel),
        .rst_n          (rst_audio_n),
        .mode_sel       (key_mode_sel),

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
//   SW1  = KC0 + KR0：44.1kHz，4x
//   SW2  = KC0 + KR1：44.1kHz，8x
//   SW3/4= KC0 + KR2/3：44.1kHz，128x
//   SW5  = KC1 + KR0：48kHz，4x
//   SW6  = KC1 + KR1：48kHz，8x
//   SW7/8= KC1 + KR2/3：48kHz，128x
//=============================================================
module matrix_keypad_mode_ctrl #(
    parameter integer SCAN_DIV       = 20000,  // 20MHz 下每个 KR 扫描约 1ms
    parameter integer DEBOUNCE_SCANS = 5       // 完整 4x4 扫描稳定 5 次后生效
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire [3:0] kc,
    output reg  [3:0] kr_drive_low,

    output reg        family_sel,    // 0=44.1kHz 家族，1=48kHz 家族
    output reg  [1:0] mode_sel,      // 00=4x，01=8x，10/11=128x
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
            mode_sel          <= 2'b00;
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
                                        mode_sel   <= 2'b10;
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
                                        mode_sel   <= 2'b10;
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
