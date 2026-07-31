`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_board_phase7_shared_keypad_scan.v
// 模块名       : tb_board_phase7_shared_keypad_scan
// 功能简述     : Phase 7 板级共享键盘扫描计数器验证平台。
//                使用轻量时钟与 DAC 公共模块桩模型，完整验证：
//                  1. 20MHz 上电计数器在预期周期释放复位；
//                  2. 共享扫描使能严格每 16384 拍出现一次；
//                  3. 音频时钟域复位同步释放；
//                  4. SW2 经整轮扫描与消抖后切换到 4x。
//
// 当前默认配置：
//                  上电复位周期：65535 个 20MHz 时钟
//                  扫描使能周期：16384 个 20MHz 时钟
//                  按键去抖轮数：5
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-18
// 版本         : V2018.3
// 开发工具     : Vivado Simulator
// 修订记录     :
//                2026-07-18：新增共享扫描与板级复位验证平台。
//=============================================================

module tb_board_phase7_shared_keypad_scan;

    localparam integer EXPECTED_RESET_CYCLES = 65535;
    localparam integer EXPECTED_SCAN_CYCLES = 16384;
    localparam integer MODE_TIMEOUT_CYCLES = 500000;

    reg clk;
    reg [3:0] key_kc;
    reg press_sw2;
    reg press_sw6;
    integer cycle_count;
    integer reset_release_cycle;
    integer last_scan_cycle;
    integer scan_interval_count;
    integer mode_wait_count;
    integer family_wait_count;

    wire [3:0] key_kr;
    wire dac_clk;
    wire [7:0] dac_data;
    wire beep_io;

    board_demo_competition_dac8_top #(
        .USE_PHASE7_LUTRAM_STAGE23(1),
        .USE_COMPACT_KEYPAD(1),
        .COMPACT_KEYPAD_SCAN_DIV(20000),
        .USE_SHARED_KEYPAD_SCAN_TICK(1),
        .USE_PHASE7_BRAM_STAGE23_HISTORY(1),
        .USE_PHASE7_BRAM_STAGE23_COEFF(1)
    ) u_dut (
        .clk(clk),
        .key_kr(key_kr),
        .key_kc(key_kc),
        .dac_clk(dac_clk),
        .dac_data(dac_data),
        .beep_io(beep_io)
    );

    initial begin
        clk = 1'b0;
        forever #25 clk = ~clk;
    end

    always @(*) begin
        key_kc = 4'hF;
        if (press_sw2 && key_kr[1] === 1'b0)
            key_kc[0] = 1'b0;
        if (press_sw6 && key_kr[1] === 1'b0)
            key_kc[1] = 1'b0;
    end

    always @(posedge clk) begin
        cycle_count = cycle_count + 1;

        if (u_dut.rst_n_int && u_dut.compact_keypad_scan_tick) begin
            if (last_scan_cycle >= 0) begin
                if (cycle_count - last_scan_cycle != EXPECTED_SCAN_CYCLES)
                    $fatal(1, "Shared scan interval mismatch: got=%0d expected=%0d",
                           cycle_count - last_scan_cycle, EXPECTED_SCAN_CYCLES);
                scan_interval_count = scan_interval_count + 1;
            end
            last_scan_cycle = cycle_count;
        end
    end

    initial begin
        cycle_count = 0;
        reset_release_cycle = -1;
        last_scan_cycle = -1;
        scan_interval_count = 0;
        mode_wait_count = 0;
        family_wait_count = 0;
        press_sw2 = 1'b0;
        press_sw6 = 1'b0;

        wait (u_dut.rst_n_int === 1'b1);
        reset_release_cycle = cycle_count;
        if (reset_release_cycle != EXPECTED_RESET_CYCLES)
            $fatal(1, "Power reset release mismatch: got=%0d expected=%0d",
                   reset_release_cycle, EXPECTED_RESET_CYCLES);

        wait (u_dut.rst_audio_n === 1'b1);
        if (u_dut.key_mode_sel !== 2'b11)
            $fatal(1, "Default keypad mode is not 128x");
        if (beep_io !== 1'b1)
            $fatal(1, "Buzzer idle level is not high");

        press_sw2 = 1'b1;
        while (u_dut.key_mode_sel !== 2'b01 &&
               mode_wait_count < MODE_TIMEOUT_CYCLES) begin
            @(posedge clk);
            mode_wait_count = mode_wait_count + 1;
        end

        if (u_dut.key_mode_sel !== 2'b01)
            $fatal(1, "SW2 did not select 4x before timeout");
        if (scan_interval_count < 8)
            $fatal(1, "Too few shared scan intervals were observed");

        press_sw2 = 1'b0;
        press_sw6 = 1'b1;
        while (u_dut.key_family_sel !== 1'b1 &&
               family_wait_count < MODE_TIMEOUT_CYCLES) begin
            @(posedge clk);
            family_wait_count = family_wait_count + 1;
        end

        if (u_dut.key_family_sel !== 1'b1)
            $fatal(1, "SW6 did not select the 48 kHz family before timeout");
        wait (u_dut.family_switch_busy === 1'b1);
        wait (u_dut.rst_audio_n === 1'b0);
        wait (u_dut.family_active === 1'b1);
        if (!u_dut.family_switch_busy)
            $fatal(1, "Family clock changed outside the protected reset window");
        wait (u_dut.family_switch_busy === 1'b0);
        wait (u_dut.rst_audio_n === 1'b1);
        if (u_dut.key_mode_sel !== 2'b01)
            $fatal(1, "SW6 did not retain 4x mode");

        press_sw6 = 1'b0;
        $display("NATIONAL FINALS BOARD INTEGRATION PASS: reset=%0d scan=%0d mode_wait=%0d family_wait=%0d",
                 reset_release_cycle, EXPECTED_SCAN_CYCLES,
                 mode_wait_count, family_wait_count);
        $finish;
    end

endmodule

module IBUF(
    input  wire I,
    output wire O
);
    assign O = I;
endmodule

module BUFG(
    input  wire I,
    output wire O
);
    assign O = I;
endmodule

module clk_wiz_audio_44k1(
    output wire clk_out1,
    input  wire reset,
    output wire locked,
    input  wire clk_in1,
    input  wire clkfb_in,
    output wire clkfb_out
);
    assign clk_out1 = clk_in1;
    assign locked = ~reset;
    assign clkfb_out = clkfb_in;
endmodule

module dual_family_audio_clock(
    input  wire clk_20m,
    input  wire reset,
    input  wire family_48k,
    output wire clk_audio_128x,
    output wire locked_selected,
    output wire locked_44k1,
    output wire locked_48k
);
    assign clk_audio_128x = clk_20m;
    assign locked_selected = ~reset;
    assign locked_44k1 = ~reset;
    assign locked_48k = ~reset;
endmodule

module demo_interp_dac8_audio_pcm_common #(
    parameter integer USE_PHASE7_FOLDED = 1,
    parameter integer USE_PHASE7_LUTRAM_STAGE23 = 0,
    parameter integer USE_PHASE7_BRAM_STAGE23_HISTORY = 0,
    parameter integer USE_PHASE7_BRAM_STAGE23_COEFF = 0,
    parameter integer USE_PHASE8_PACKED_BRAM_STAGE23 = 0,
    parameter integer USE_PHASE7_CIC_BURST_COUNTER_DSP = 0,
    parameter integer USE_NATIONAL_FINALS_DATAPATH = 1,
    parameter integer USE_NATIONAL_FINALS_SERIAL_CIC_COMB = 0,
    parameter integer USE_NATIONAL_FINALS_CIC_COMB_DSP = 0,
    parameter integer USE_NATIONAL_FINALS_STAGE1_DSP48_PREADDER = 0,
    parameter integer USE_NATIONAL_FINALS_NARROW_STAGE23 = 0
)(
    input  wire       clk_audio_128x,
    input  wire       rst_n,
    input  wire       family_48k,
    input  wire [1:0] mode_sel,
    input  wire       force_mute,
    output wire       dac_clk,
    output wire [7:0] dac_data,
    output wire [1:0] mode_led
);
    assign dac_clk = clk_audio_128x & rst_n;
    assign dac_data = 8'h80;
    assign mode_led = mode_sel;
endmodule
