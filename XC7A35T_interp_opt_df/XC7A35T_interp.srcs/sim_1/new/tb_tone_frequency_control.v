`timescale 1ns / 1ps
//=============================================================
// 文件名       : tb_tone_frequency_control.v
// 模块名       : tb_tone_frequency_control
// 功能简述     : 验证 SW5～SW8 的 1kHz 步进、边界回绕、15kHz
//                复位、自动扫频开关以及手动操作退出扫频。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-18
// 版本         : V2018.3
// 开发工具     : Vivado Simulator
// 修订记录     :
//                2026-07-18：新增频率控制自动化验证平台。
//=============================================================

module tb_tone_frequency_control;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg key_strobe = 1'b0;
    reg [3:0] key_code = 4'd0;

    wire [4:0] tone_khz;
    wire auto_sweep;

    tone_frequency_control #(
        .AUTO_STEP_CYCLES(4)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .key_strobe (key_strobe),
        .key_code   (key_code),
        .tone_khz   (tone_khz),
        .auto_sweep (auto_sweep)
    );

    always #5 clk = ~clk;

    task press_key;
        input [3:0] code;
        begin
            @(negedge clk);
            key_code = code;
            key_strobe = 1'b1;
            @(negedge clk);
            key_strobe = 1'b0;
            @(negedge clk);
        end
    endtask

    task check_state;
        input [4:0] expected_tone;
        input expected_auto;
        input [127:0] label_text;
        begin
            if ((tone_khz !== expected_tone) ||
                (auto_sweep !== expected_auto)) begin
                $display("FAIL %0s: tone=%0d auto=%b expected=%0d/%b",
                         label_text, tone_khz, auto_sweep,
                         expected_tone, expected_auto);
                $fatal(1);
            end
        end
    endtask

    integer index;

    initial begin
        repeat (4) @(posedge clk);
        rst_n <= 1'b1;
        repeat (2) @(posedge clk);
        check_state(5'd15, 1'b0, "reset default");

        press_key(4'd4);
        check_state(5'd16, 1'b0, "SW5 increments");

        repeat (4)
            press_key(4'd4);
        check_state(5'd20, 1'b0, "increment reaches 20");
        press_key(4'd4);
        check_state(5'd1, 1'b0, "increment wraps to 1");

        press_key(4'd5);
        check_state(5'd20, 1'b0, "decrement wraps to 20");
        press_key(4'd6);
        check_state(5'd15, 1'b0, "SW7 restores 15");

        press_key(4'd7);
        check_state(5'd15, 1'b1, "SW8 enables auto");
        repeat (4) @(posedge clk);
        @(negedge clk);
        check_state(5'd16, 1'b1, "auto step");

        press_key(4'd5);
        check_state(5'd15, 1'b0, "manual key exits auto");

        // SW1～SW4 只改变模式，不应影响频率控制状态。
        for (index = 0; index < 4; index = index + 1)
            press_key(index[3:0]);
        check_state(5'd15, 1'b0, "mode keys ignored");

        $display("PASS: SW5-SW8 frequency control and automatic sweep verified");
        $finish;
    end

endmodule
