`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_matrix_keypad_four_mode.v
// 模块名       : tb_matrix_keypad_four_mode
// 功能简述     : 四档矩阵按键映射单元测试平台。
//                模拟 SW1～SW8 的矩阵连接和消抖过程，验证两组
//                按键均按 1x、4x、8x、128x 顺序锁存 mode_sel。
//
// 当前默认配置：
//                  SW1/SW5：1x
//                  SW2/SW6：4x
//                  SW3/SW7：8x
//                  SW4/SW8：128x
//                  上电默认：128x
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-12
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-12：新增四档矩阵按键映射验证。
//=============================================================
//=============================================================
// 1）模块名称：tb_matrix_keypad_four_mode
// 功能说明：仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 工程版本：Vivado 2025.2。
//=============================================================

module tb_matrix_keypad_four_mode;

    reg clk;
    reg rst_n;
    reg press_en;
    reg [3:0] pressed_code;
    reg [3:0] kc;

    wire [3:0] kr_drive_low;
    wire family_sel;
    wire [1:0] mode_sel;
    wire key_strobe;
    wire [3:0] key_code;

    integer row_index;
    integer column_index;

    // 例化说明：调用 matrix_keypad_mode_ctrl 键盘控制模块，完成扫描、消抖、译码和模式更新。
    matrix_keypad_mode_ctrl #(
        .SCAN_DIV       (4),
        .DEBOUNCE_SCANS (1)
    ) u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .kc           (kc),
        .kr_drive_low (kr_drive_low),
        .family_sel   (family_sel),
        .mode_sel     (mode_sel),
        .key_strobe   (key_strobe),
        .key_code     (key_code)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(*) begin
        kc = 4'hF;
        row_index = pressed_code / 4;
        column_index = pressed_code % 4;
        if (press_en && kr_drive_low[column_index])
            kc[row_index] = 1'b0;
    end

    task check_key;
        input [3:0] test_code;
        input [1:0] expected_mode;
        begin
            pressed_code = test_code;
            press_en = 1'b1;
            repeat (160) @(posedge clk);
            if (mode_sel !== expected_mode)
                $fatal(1, "Key mapping mismatch: key=%0d mode=%0d expected=%0d",
                       test_code + 1, mode_sel, expected_mode);
            if (key_code !== test_code)
                $fatal(1, "Key code mismatch: got=%0d expected=%0d",
                       key_code, test_code);

            press_en = 1'b0;
            repeat (160) @(posedge clk);
            $display("SW%0d -> mode=%0d PASS", test_code + 1, mode_sel);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        press_en = 1'b0;
        pressed_code = 4'd0;
        repeat (10) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        if (mode_sel !== 2'b11)
            $fatal(1, "Power-up mode is not 128x: mode=%0d", mode_sel);

        check_key(4'd0, 2'b00);
        check_key(4'd1, 2'b01);
        check_key(4'd2, 2'b10);
        check_key(4'd3, 2'b11);
        check_key(4'd4, 2'b00);
        check_key(4'd5, 2'b01);
        check_key(4'd6, 2'b10);
        check_key(4'd7, 2'b11);

        $display("PASS: SW1-SW8 four-mode mapping verified.");
        $finish;
    end

endmodule
