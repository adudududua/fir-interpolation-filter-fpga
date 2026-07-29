`timescale 1ns / 1ps
//=============================================================
// 文件名       : tb_lcd12864_st7920_ui.v
// 模块名       : tb_lcd12864_st7920_ui
// 功能简述     : 12864T 图形液晶控制器自动化验证平台。
//                逐字节检查初始化序列、64 行 GDRAM 上下半屏映射、
//                四页界面 ROM 数据和整帧边界模式切换。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-18
// 版本         : V2018.3
// 开发工具     : Vivado Simulator
// 修订记录     :
//                2026-07-18：新增液晶初始化、整帧刷新与切档验证。
//                2026-07-18：增加动态频率/AUTO 像素和帧边界同步验证。
//                2026-07-19：接口补充 ILA 演示页输入，正常四页回归
//                            继续固定演示关闭。
//=============================================================

module tb_lcd12864_st7920_ui;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [1:0] mode_sel = 2'b01;
    reg [4:0] tone_khz = 5'd15;
    reg auto_sweep = 1'b0;
    reg ila_demo_enable = 1'b0;
    reg [15:0] magnitude_15k_pre = 16'd12618;
    reg [15:0] magnitude_15k_post = 16'd12552;
    reg [15:0] magnitude_40k_pre = 16'd12636;
    reg [15:0] magnitude_40k_post = 16'd18;
    reg [7:0] suppression_40k_db = 8'd54;
    reg measurement_valid = 1'b1;

    wire [7:0] lcd_data;
    wire lcd_rs;
    wire lcd_rw;
    wire lcd_e;

    reg [7:0] golden [0:5119];
    integer errors = 0;
    integer init_index = 0;
    integer refresh_phase = 0;
    integer expected_row = 0;
    integer expected_column = 0;
    integer expected_page = 1;
    integer expected_tone = 15;
    integer expected_auto = 0;
    integer expected_demo = 0;
    integer frame_count = 0;
    reg initialization_done = 1'b0;
    reg [7:0] expected_value;

    always #25 clk = ~clk; // 20 MHz

    lcd12864_st7920_ui #(
        .MEM_FILE("lcd12864_ui.mem"),
        .POWERUP_CYCLES(4),
        .INIT_DELAY_CYCLES(2),
        .CLEAR_DELAY_CYCLES(3),
        .IO_SETUP_CYCLES(2),
        .IO_HIGH_CYCLES(2),
        .IO_HOLD_CYCLES(2)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .mode_sel(mode_sel),
        .tone_khz(tone_khz),
        .auto_sweep(auto_sweep),
        .ila_demo_enable(ila_demo_enable),
        .magnitude_15k_pre(magnitude_15k_pre),
        .magnitude_15k_post(magnitude_15k_post),
        .magnitude_40k_pre(magnitude_40k_pre),
        .magnitude_40k_post(magnitude_40k_post),
        .suppression_40k_db(suppression_40k_db),
        .measurement_valid(measurement_valid),
        .lcd_data(lcd_data),
        .lcd_rs(lcd_rs),
        .lcd_rw(lcd_rw),
        .lcd_e(lcd_e)
    );

    function [7:0] expected_init_command;
        input integer index;
        begin
            case (index)
                0, 1, 2: expected_init_command = 8'h30;
                3:       expected_init_command = 8'h0C;
                4:       expected_init_command = 8'h01;
                5:       expected_init_command = 8'h06;
                6:       expected_init_command = 8'h34;
                7:       expected_init_command = 8'h36;
                default: expected_init_command = 8'h00;
            endcase
        end
    endfunction

    function integer expected_bar_units;
        input integer magnitude;
        begin
            expected_bar_units = magnitude >> 10;
            if (expected_bar_units > 15)
                expected_bar_units = 15;
        end
    endfunction

    function [7:0] expected_demo_overlay;
        input integer row;
        input integer column;
        integer pixel_index;
        integer source_x;
        integer source_y;
        integer bar_end_x;
        integer tens;
        integer ones;
        reg pixel_on;
        reg [3:0] glyph;
        reg [4:0] pixels;
        begin
            expected_demo_overlay = 8'h00;
            tens = suppression_40k_db / 10;
            ones = suppression_40k_db % 10;

            for (pixel_index = 0; pixel_index < 8;
                 pixel_index = pixel_index + 1) begin
                source_x = 127 - ((column * 8) + pixel_index);
                source_y = 63 - row;
                pixel_on = 1'b0;

                if (measurement_valid && source_x >= 29) begin
                    if (source_y >= 23 && source_y <= 25) begin
                        bar_end_x = 29 + expected_bar_units(
                            magnitude_15k_pre) * 6;
                        if (source_x < bar_end_x) pixel_on = 1'b1;
                    end
                    else if (source_y >= 31 && source_y <= 33) begin
                        bar_end_x = 29 + expected_bar_units(
                            magnitude_15k_post) * 6;
                        if (source_x < bar_end_x) pixel_on = 1'b1;
                    end
                    else if (source_y >= 39 && source_y <= 41) begin
                        bar_end_x = 29 + expected_bar_units(
                            magnitude_40k_pre) * 6;
                        if (source_x < bar_end_x) pixel_on = 1'b1;
                    end
                    else if (source_y >= 47 && source_y <= 49) begin
                        bar_end_x = 29 + expected_bar_units(
                            magnitude_40k_post) * 6;
                        if (source_x < bar_end_x) pixel_on = 1'b1;
                    end
                end

                if (source_y >= 54 && source_y <= 60) begin
                    if (source_x >= 34 && source_x <= 38) begin
                        glyph = tens;
                        pixels = expected_glyph_row(glyph, source_y - 54);
                        if (pixels[4-(source_x-34)]) pixel_on = 1'b1;
                    end
                    else if (source_x >= 42 && source_x <= 46) begin
                        glyph = ones;
                        pixels = expected_glyph_row(glyph, source_y - 54);
                        if (pixels[4-(source_x-42)]) pixel_on = 1'b1;
                    end
                end
                expected_demo_overlay[7-pixel_index] = pixel_on;
            end
        end
    endfunction

    function [4:0] expected_glyph_row;
        input [3:0] glyph;
        input [2:0] row;
        reg [34:0] bitmap;
        begin
            case (glyph)
                4'd0: bitmap = {5'b01110,5'b10001,5'b10011,5'b10101,
                                 5'b11001,5'b10001,5'b01110};
                4'd1: bitmap = {5'b00100,5'b01100,5'b00100,5'b00100,
                                 5'b00100,5'b00100,5'b01110};
                4'd2: bitmap = {5'b01110,5'b10001,5'b00001,5'b00010,
                                 5'b00100,5'b01000,5'b11111};
                4'd3: bitmap = {5'b11110,5'b00001,5'b00001,5'b01110,
                                 5'b00001,5'b00001,5'b11110};
                4'd4: bitmap = {5'b00010,5'b00110,5'b01010,5'b10010,
                                 5'b11111,5'b00010,5'b00010};
                4'd5: bitmap = {5'b11111,5'b10000,5'b10000,5'b11110,
                                 5'b00001,5'b00001,5'b11110};
                4'd6: bitmap = {5'b01110,5'b10000,5'b10000,5'b11110,
                                 5'b10001,5'b10001,5'b01110};
                4'd7: bitmap = {5'b11111,5'b00001,5'b00010,5'b00100,
                                 5'b01000,5'b01000,5'b01000};
                4'd8: bitmap = {5'b01110,5'b10001,5'b10001,5'b01110,
                                 5'b10001,5'b10001,5'b01110};
                4'd9: bitmap = {5'b01110,5'b10001,5'b10001,5'b01111,
                                 5'b00001,5'b00001,5'b01110};
                4'd10: bitmap = {5'b01110,5'b10001,5'b10001,5'b11111,
                                  5'b10001,5'b10001,5'b10001};
                default: bitmap = 35'd0;
            endcase
            case (row)
                0: expected_glyph_row = bitmap[34:30];
                1: expected_glyph_row = bitmap[29:25];
                2: expected_glyph_row = bitmap[24:20];
                3: expected_glyph_row = bitmap[19:15];
                4: expected_glyph_row = bitmap[14:10];
                5: expected_glyph_row = bitmap[9:5];
                6: expected_glyph_row = bitmap[4:0];
                default: expected_glyph_row = 5'd0;
            endcase
        end
    endfunction

    function [7:0] expected_overlay;
        input integer frequency;
        input integer auto_enabled;
        input integer row;
        input integer column;
        integer tens;
        integer ones;
        reg [3:0] glyph;
        reg [4:0] pixels;
        begin
            expected_overlay = 8'h00;
            tens = (frequency >= 20) ? 2 : ((frequency >= 10) ? 1 : 0);
            ones = (frequency >= 20) ? 0 :
                   ((frequency >= 10) ? frequency - 10 : frequency);

            if ((row >= 32) && (row <= 38)) begin
                if (column == 6)
                    glyph = tens;
                else if (column == 5)
                    glyph = ones;
                else if ((column == 0) && auto_enabled)
                    glyph = 4'd10;
                else
                    glyph = 4'd15;

                pixels = expected_glyph_row(glyph, 38 - row);
                expected_overlay = {3'b000, pixels[0], pixels[1], pixels[2],
                                     pixels[3], pixels[4]};
            end
        end
    endfunction

    initial begin
        $readmemh("lcd12864_ui.mem", golden);
        repeat (4) @(posedge clk);
        rst_n <= 1'b1;
    end

    // 每笔液晶传输在 LCD_E 下降沿提交。
    always @(negedge lcd_e) begin
        if (rst_n) begin
            if (lcd_rw !== 1'b0) begin
                $display("ERROR: LCD_R/W was not low at %0t", $time);
                errors = errors + 1;
            end

            if (!initialization_done) begin
                expected_value = expected_init_command(init_index);
                if (lcd_rs !== 1'b0 || lcd_data !== expected_value) begin
                    $display("ERROR init[%0d]: rs=%b data=%02x expected=%02x",
                             init_index, lcd_rs, lcd_data, expected_value);
                    errors = errors + 1;
                end
                if (init_index == 7) begin
                    initialization_done = 1'b1;
                    refresh_phase = 0;
                end
                else begin
                    init_index = init_index + 1;
                end
            end
            else begin
                case (refresh_phase)
                    0: begin
                        expected_value = 8'h80 | expected_row[4:0];
                        if (lcd_rs !== 1'b0 || lcd_data !== expected_value) begin
                            $display("ERROR row %0d Y command: got rs=%b data=%02x expected=%02x",
                                     expected_row, lcd_rs, lcd_data, expected_value);
                            errors = errors + 1;
                        end
                        refresh_phase = 1;
                    end

                    1: begin
                        expected_value = (expected_row >= 32) ? 8'h88 : 8'h80;
                        if (lcd_rs !== 1'b0 || lcd_data !== expected_value) begin
                            $display("ERROR row %0d X command: got rs=%b data=%02x expected=%02x",
                                     expected_row, lcd_rs, lcd_data, expected_value);
                            errors = errors + 1;
                        end
                        expected_column = 0;
                        refresh_phase = 2;
                    end

                    2: begin
                        expected_value = golden[(expected_demo ? 4 : expected_page) * 1024 +
                                                expected_row * 16 +
                                                expected_column] |
                                         (expected_demo ?
                                          expected_demo_overlay(expected_row,
                                                                expected_column) :
                                          expected_overlay(expected_tone,
                                                           expected_auto,
                                                           expected_row,
                                                           expected_column));
                        if (lcd_rs !== 1'b1 || lcd_data !== expected_value) begin
                            $display("ERROR frame %0d row %0d col %0d: got rs=%b data=%02x expected=%02x",
                                     frame_count, expected_row, expected_column,
                                     lcd_rs, lcd_data, expected_value);
                            errors = errors + 1;
                        end

                        // 在第0帧刷新途中同时切档、调频并开启 AUTO；
                        // 三项状态都只能从下一帧边界开始输出。
                        if (frame_count == 0 && expected_row == 0 && expected_column == 0) begin
                            mode_sel <= 2'b10;
                            tone_khz <= 5'd20;
                            auto_sweep <= 1'b1;
                        end
                        if (frame_count == 1 && expected_row == 0 && expected_column == 0)
                            ila_demo_enable <= 1'b1;

                        if (expected_column == 15) begin
                            expected_column = 0;
                            refresh_phase = 0;
                            if (expected_row == 63) begin
                                expected_row = 0;
                                frame_count = frame_count + 1;
                                if (frame_count == 1) begin
                                    expected_page = 2;
                                    expected_tone = 20;
                                    expected_auto = 1;
                                end
                                else if (frame_count == 2) begin
                                    expected_demo = 1;
                                end
                                else begin
                                    if (errors == 0)
                                        $display("PASS: LCD normal pages and dynamic ILA demo page verified");
                                    else
                                        $display("FAIL: %0d LCD verification errors", errors);
                                    $finish;
                                end
                            end
                            else begin
                                expected_row = expected_row + 1;
                            end
                        end
                        else begin
                            expected_column = expected_column + 1;
                        end
                    end

                    default: begin
                        $display("ERROR: invalid refresh phase");
                        errors = errors + 1;
                    end
                endcase
            end
        end
    end

    initial begin
        #20000000;
        $display("FAIL: timeout with %0d errors", errors);
        $finish;
    end

endmodule
