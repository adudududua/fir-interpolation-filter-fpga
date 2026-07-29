`timescale 1ns / 1ps
//=============================================================
// 文件名       : tb_matrix_keypad_mode_ctrl_compact.v
// 模块名       : tb_matrix_keypad_mode_ctrl_compact
// 功能简述     : 紧凑矩阵按键控制器与原 16 键扫描器的行为验证。
//                同一按键矩阵分别根据两个扫描器的 KR 输出反馈 KC，
//                检查 SW1～SW9、按键抖动、跨行多键优先级以及
//                SW10～SW16 不改变演示模式的行为。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-18
// 版本         : V2018.3
// 开发工具     : Vivado Simulator
// 修订记录     :
//                2026-07-18：新增紧凑矩阵按键控制器验证平台。
//                2026-07-18：增加外部扫描使能路径等价验证。
//                2026-07-18：增加单次键码脉冲验证；SW5～SW8 改为
//                            频率控制键，不再改变插值模式。
//                2026-07-19：增加 SW9 ILA 演示键码验证。
//=============================================================

module tb_matrix_keypad_mode_ctrl_compact;

    localparam integer SCAN_DIV = 3;
    localparam integer DEBOUNCE_SCANS = 2;

    reg clk;
    reg rst_n;
    reg [1:0] external_scan_cnt;
    reg [15:0] pressed_bitmap;

    reg [3:0] kc_full;
    reg [3:0] kc_compact;
    wire [3:0] kr_full;
    wire [3:0] kr_compact;
    wire [1:0] mode_full;
    wire [1:0] mode_compact;
    wire external_scan_tick = (external_scan_cnt == SCAN_DIV - 1);
    wire family_unused;
    wire strobe_full;
    wire [3:0] code_full;
    wire strobe_compact;
    wire [3:0] code_compact;

    integer full_event_count;
    integer compact_event_count;
    reg [3:0] last_full_code;
    reg [3:0] last_compact_code;

    integer row_idx;
    integer col_idx;
    integer test_idx;

    matrix_keypad_mode_ctrl #(
        .SCAN_DIV(SCAN_DIV),
        .DEBOUNCE_SCANS(DEBOUNCE_SCANS)
    ) u_full (
        .clk          (clk),
        .rst_n        (rst_n),
        .kc           (kc_full),
        .kr_drive_low (kr_full),
        .family_sel   (family_unused),
        .mode_sel     (mode_full),
        .key_strobe   (strobe_full),
        .key_code     (code_full)
    );

    matrix_keypad_mode_ctrl_compact #(
        .SCAN_DIV(SCAN_DIV),
        .DEBOUNCE_SCANS(DEBOUNCE_SCANS),
        .USE_EXTERNAL_SCAN_TICK(1)
    ) u_compact (
        .clk          (clk),
        .rst_n        (rst_n),
        .scan_tick    (external_scan_tick),
        .kc           (kc_compact),
        .kr_drive_low (kr_compact),
        .mode_sel     (mode_compact),
        .key_strobe   (strobe_compact),
        .key_code     (code_compact)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (strobe_full) begin
            full_event_count = full_event_count + 1;
            last_full_code = code_full;
        end
        if (strobe_compact) begin
            compact_event_count = compact_event_count + 1;
            last_compact_code = code_compact;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            external_scan_cnt <= 0;
        else if (external_scan_tick)
            external_scan_cnt <= 0;
        else
            external_scan_cnt <= external_scan_cnt + 1'b1;
    end

    always @(*) begin
        kc_full = 4'hF;
        kc_compact = 4'hF;

        for (col_idx = 0; col_idx < 4; col_idx = col_idx + 1) begin
            if (kr_full[col_idx]) begin
                for (row_idx = 0; row_idx < 4; row_idx = row_idx + 1) begin
                    if (pressed_bitmap[row_idx * 4 + col_idx])
                        kc_full[row_idx] = 1'b0;
                end
            end

            if (kr_compact[col_idx]) begin
                for (row_idx = 0; row_idx < 4; row_idx = row_idx + 1) begin
                    if (pressed_bitmap[row_idx * 4 + col_idx])
                        kc_compact[row_idx] = 1'b0;
                end
            end
        end
    end

    task wait_full_scans;
        input integer count;
        integer cycle_count;
        begin
            cycle_count = count * 4 * SCAN_DIV;
            repeat (cycle_count) @(posedge clk);
        end
    endtask

    task check_modes;
        input [1:0] expected;
        input [127:0] label_text;
        begin
            if (mode_full !== expected) begin
                $display("FAIL full keypad %0s expected=%0d actual=%0d",
                         label_text, expected, mode_full);
                $fatal(1);
            end
            if (mode_compact !== expected) begin
                $display("FAIL compact keypad %0s expected=%0d actual=%0d",
                         label_text, expected, mode_compact);
                $fatal(1);
            end
            if (mode_compact !== mode_full) begin
                $display("FAIL keypad mismatch %0s full=%0d compact=%0d",
                         label_text, mode_full, mode_compact);
                $fatal(1);
            end
        end
    endtask

    task press_and_check;
        input integer key_index;
        input [1:0] expected;
        integer full_events_before;
        integer compact_events_before;
        begin
            full_events_before = full_event_count;
            compact_events_before = compact_event_count;
            pressed_bitmap = (16'b1 << key_index);
            wait_full_scans(DEBOUNCE_SCANS + 5);
            check_modes(expected, "stable single key");

            if ((full_event_count - full_events_before) != 1 ||
                last_full_code !== key_index[3:0]) begin
                $display("FAIL full keypad event key=%0d count=%0d code=%0d",
                         key_index, full_event_count - full_events_before,
                         last_full_code);
                $fatal(1);
            end
            if ((compact_event_count - compact_events_before) != 1 ||
                last_compact_code !== key_index[3:0]) begin
                $display("FAIL compact keypad event key=%0d count=%0d code=%0d",
                         key_index, compact_event_count - compact_events_before,
                         last_compact_code);
                $fatal(1);
            end

            pressed_bitmap = 16'd0;
            wait_full_scans(DEBOUNCE_SCANS + 4);
            check_modes(expected, "released key holds mode");
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        pressed_bitmap = 16'd0;
        full_event_count = 0;
        compact_event_count = 0;
        last_full_code = 4'd0;
        last_compact_code = 4'd0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        wait_full_scans(2);
        check_modes(2'b11, "reset default");

        for (test_idx = 0; test_idx < 4; test_idx = test_idx + 1)
            press_and_check(test_idx, test_idx[1:0]);

        // SW5～SW8 只输出频率控制键码，模式保持 SW4 选中的 128x。
        for (test_idx = 4; test_idx < 8; test_idx = test_idx + 1)
            press_and_check(test_idx, 2'b11);

        // SW9 产生 ILA 演示键码但不改变倍率；SW10～SW16 忽略。
        press_and_check(1, 2'b01);
        press_and_check(8, 2'b01);
        for (test_idx = 9; test_idx < 16; test_idx = test_idx + 1) begin
            pressed_bitmap = (16'b1 << test_idx);
            wait_full_scans(DEBOUNCE_SCANS + 5);
            check_modes(2'b01, "unused key ignored");
            pressed_bitmap = 16'd0;
            wait_full_scans(DEBOUNCE_SCANS + 4);
        end

        // 短于整轮稳定门限的抖动不得改变模式。
        repeat (5) begin
            pressed_bitmap = 16'b1 << 2;
            repeat (SCAN_DIV) @(posedge clk);
            pressed_bitmap = 16'd0;
            repeat (SCAN_DIV) @(posedge clk);
        end
        wait_full_scans(DEBOUNCE_SCANS + 3);
        check_modes(2'b01, "bounce rejected");

        // 同时按 SW2 与 SW5，原扫描器优先 SW2；紧凑版保持相同优先级。
        pressed_bitmap = (16'b1 << 1) | (16'b1 << 4);
        wait_full_scans(DEBOUNCE_SCANS + 5);
        check_modes(2'b01, "row priority");
        pressed_bitmap = 16'd0;
        wait_full_scans(DEBOUNCE_SCANS + 4);

        $display("PASS: compact keypad matches required SW1-SW9 behavior");
        $finish;
    end

endmodule
