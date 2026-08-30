`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_keypad_mode_chain.v
// 模块名       : tb_keypad_mode_chain
// 功能简述     : 矩阵按键到板级模式提交链测试。覆盖 SW1～SW8 消抖、44.1/48 kHz 家族选择及 1x/4x/8x/128x 模式切换。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
// 矩阵按键到音频模式的专项回归。覆盖用户实际遇到的：
// 48 kHz/4x -> 48 kHz/128x，以及跨 family 后再回到 SW8。
module tb_keypad_mode_chain;
    reg ctrl_clk = 1'b0;
    reg audio_clk = 1'b0;
    reg ctrl_rst_n = 1'b0;
    reg audio_rst_n = 1'b0;
    always #5 ctrl_clk = ~ctrl_clk;
    always #7 audio_clk = ~audio_clk;

    reg       pressed = 1'b0;
    reg       pressed_family = 1'b0;
    reg [1:0] pressed_mode = 2'd0;
    wire [3:0] kr_drive_low;
    reg  [3:0] kc;
    wire       key_family;
    wire [1:0] key_mode;
    wire [1:0] audio_mode;
    wire       audio_mute;
    wire       ctrl_busy;

    always @(*) begin
        kc = 4'b1111;
        if (pressed && kr_drive_low[pressed_mode]) begin
            if (pressed_family)
                kc[1] = 1'b0;
            else
                kc[0] = 1'b0;
        end
    end

    matrix_keypad_mode_ctrl_ultracompact #(
        .SCAN_DIV(8),
        .DEBOUNCE_SCANS(5),
        .USE_EXTERNAL_SCAN_TICK(0)
    ) u_keypad (
        .clk(ctrl_clk),
        .rst_n(ctrl_rst_n),
        .scan_tick(1'b0),
        .kc(kc),
        .kr_drive_low(kr_drive_low),
        .family_sel(key_family),
        .mode_sel(key_mode)
    );

    nf_mode_cdc_handshake u_mode_cdc (
        .ctrl_clk(ctrl_clk),
        .ctrl_rst_n(ctrl_rst_n),
        .ctrl_mode(key_mode),
        .ctrl_busy(ctrl_busy),
        .audio_clk(audio_clk),
        .audio_rst_n(audio_rst_n),
        .audio_mode(audio_mode),
        .audio_mute(audio_mute)
    );

    task press_and_expect_key;
        input family;
        input [1:0] mode;
        integer guard;
        begin
            pressed_family = family;
            pressed_mode = mode;
            pressed = 1'b1;
            guard = 0;
            while ((key_family !== family || key_mode !== mode) && guard < 3000) begin
                @(posedge ctrl_clk);
                guard = guard + 1;
            end
            if (guard >= 3000)
                $fatal(1, "keypad failed family=%0d mode=%0d", family, mode);
            pressed = 1'b0;
            repeat (300) @(posedge ctrl_clk);
        end
    endtask

    task wait_audio_mode;
        input [1:0] mode;
        integer guard;
        begin
            guard = 0;
            while ((audio_mode !== mode || audio_mute !== 1'b0) && guard < 500) begin
                @(posedge audio_clk);
                guard = guard + 1;
            end
            if (guard >= 500)
                $fatal(1, "audio mode failed expected=%0d actual=%0d mute=%0d",
                       mode, audio_mode, audio_mute);
        end
    endtask

    task family_clock_reset;
        begin
            audio_rst_n = 1'b0;
            repeat (8) @(posedge audio_clk);
            audio_rst_n = 1'b1;
        end
    endtask

    initial begin
        repeat (8) @(posedge ctrl_clk);
        ctrl_rst_n = 1'b1;
        repeat (4) @(posedge audio_clk);
        audio_rst_n = 1'b1;
        wait_audio_mode(2'd3);

        // SW6: 48 kHz / 4x，跨family会复位音频域。
        press_and_expect_key(1'b1, 2'd1);
        family_clock_reset();
        wait_audio_mode(2'd1);

        // SW8: 同一48 kHz family内从4x切回128x；这是本次重点故障场景。
        press_and_expect_key(1'b1, 2'd3);
        wait_audio_mode(2'd3);

        // 再回4x，确认同family切换可重复。
        press_and_expect_key(1'b1, 2'd1);
        wait_audio_mode(2'd1);

        // SW4后再SW8，覆盖两次family时钟切换和复位恢复捕获。
        press_and_expect_key(1'b0, 2'd3);
        family_clock_reset();
        wait_audio_mode(2'd3);
        press_and_expect_key(1'b1, 2'd3);
        family_clock_reset();
        wait_audio_mode(2'd3);

        $display("KEYPAD_MODE_CHAIN_PASS: SW6->SW8 and SW4->SW8 accepted");
        $finish;
    end
endmodule
