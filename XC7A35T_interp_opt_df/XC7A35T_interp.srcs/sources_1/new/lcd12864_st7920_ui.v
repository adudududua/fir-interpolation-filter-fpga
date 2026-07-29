`timescale 1ns / 1ps
//=============================================================
// 文件名       : lcd12864_st7920_ui.v
// 模块名       : lcd12864_st7920_ui
// 功能简述     : 12864T 图形液晶显示控制器。
//                按 ST7920 兼容 8bit 并口完成上电初始化、基本/扩展
//                指令切换和 128x64 GDRAM 连续刷新，并根据四档
//                mode_sel 选择对应的图形界面 ROM 页面。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-18
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-18：新增 8bit 并口写时序和保守固定延时。
//                2026-07-18：新增四页同步 Block ROM 与上下半屏
//                            GDRAM 地址映射。
//                2026-07-18：切档只在整帧边界提交，避免界面混帧。
//                2026-07-18：GDRAM 地址路径改为同步复位，消除
//                            液晶 ROM 的 RAMB36 异步控制告警。
//                2026-07-18：增加输入频率和 AUTO 动态叠加显示；
//                            模式、频率和扫频状态均在帧边界提交。
//                2026-07-19：增加第五页 ILA 镜像抑制界面，动态
//                            显示 15k/40k PRE/POST 柱和衰减值。
//
// 其他描述     :
//                1. LCD_R/W 固定为写，不读取忙标志。
//                2. ROM 为普通逐行、MSB first 的 5 x 1024 byte 图像。
//                3. 本模块仅位于 20MHz 控制域，不进入 FIR/CIC 通路。
//=============================================================

module lcd12864_st7920_ui #(
    parameter MEM_FILE             = "lcd12864_ui.mem",
    parameter integer POWERUP_CYCLES    = 1200000, // 20MHz 下等待 60ms
    parameter integer INIT_DELAY_CYCLES =   40000, //  2 ms
    parameter integer CLEAR_DELAY_CYCLES = 200000, // 10 ms
    parameter integer IO_SETUP_CYCLES   =      20, //  1 us
    parameter integer IO_HIGH_CYCLES    =      40, // E 高电平保持 2 us
    parameter integer IO_HOLD_CYCLES    =    2000  // 命令/数据后等待 100 us
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [1:0] mode_sel,
    input  wire [4:0] tone_khz,
    input  wire       auto_sweep,
    input  wire       ila_demo_enable,
    input  wire [15:0] magnitude_15k_pre,
    input  wire [15:0] magnitude_15k_post,
    input  wire [15:0] magnitude_40k_pre,
    input  wire [15:0] magnitude_40k_post,
    input  wire [7:0]  suppression_40k_db,
    input  wire        measurement_valid,

    output reg  [7:0] lcd_data,
    output reg        lcd_rs,
    output reg        lcd_rw,
    output reg        lcd_e
);

    // 五个 1024 byte 页面：1x、4x、8x、128x 和 ILA 演示。
    (* rom_style = "block" *) reg [7:0] ui_rom [0:5119];
    reg [12:0] rom_address;
    reg [7:0]  rom_data;

    initial begin
        $readmemh(MEM_FILE, ui_rom);
    end

    always @(posedge clk) begin
        rom_data <= ui_rom[rom_address];
    end

    //=========================================================
    // 底层并口写时序引擎
    //=========================================================
    localparam [1:0] IO_IDLE  = 2'd0;
    localparam [1:0] IO_SETUP = 2'd1;
    localparam [1:0] IO_HIGH  = 2'd2;
    localparam [1:0] IO_HOLD  = 2'd3;

    reg [1:0]  io_state;
    reg [31:0] io_counter;
    reg        io_busy;
    reg        io_done;

    reg        write_request;
    reg        write_rs;
    reg [7:0]  write_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lcd_data  <= 8'h00;
            lcd_rs    <= 1'b0;
            lcd_rw    <= 1'b0;
            lcd_e     <= 1'b0;
            io_state  <= IO_IDLE;
            io_counter <= 32'd0;
            io_busy   <= 1'b0;
            io_done   <= 1'b0;
        end
        else begin
            io_done <= 1'b0;

            case (io_state)
                IO_IDLE: begin
                    lcd_e <= 1'b0;
                    if (write_request) begin
                        lcd_data   <= write_data;
                        lcd_rs     <= write_rs;
                        lcd_rw     <= 1'b0;
                        io_counter <= 32'd0;
                        io_busy    <= 1'b1;
                        io_state   <= IO_SETUP;
                    end
                    else begin
                        io_busy <= 1'b0;
                    end
                end

                IO_SETUP: begin
                    if (io_counter >= IO_SETUP_CYCLES - 1) begin
                        io_counter <= 32'd0;
                        lcd_e      <= 1'b1;
                        io_state   <= IO_HIGH;
                    end
                    else begin
                        io_counter <= io_counter + 32'd1;
                    end
                end

                IO_HIGH: begin
                    if (io_counter >= IO_HIGH_CYCLES - 1) begin
                        io_counter <= 32'd0;
                        lcd_e      <= 1'b0;
                        io_state   <= IO_HOLD;
                    end
                    else begin
                        io_counter <= io_counter + 32'd1;
                    end
                end

                IO_HOLD: begin
                    if (io_counter >= IO_HOLD_CYCLES - 1) begin
                        io_counter <= 32'd0;
                        io_busy    <= 1'b0;
                        io_done    <= 1'b1;
                        io_state   <= IO_IDLE;
                    end
                    else begin
                        io_counter <= io_counter + 32'd1;
                    end
                end

                default: begin
                    lcd_e   <= 1'b0;
                    io_busy <= 1'b0;
                    io_state <= IO_IDLE;
                end
            endcase
        end
    end

    //=========================================================
    // ST7920 初始化与 GDRAM 刷新状态机
    //=========================================================
    localparam [4:0] ST_POWER_WAIT = 5'd0;
    localparam [4:0] ST_INIT_REQ   = 5'd1;
    localparam [4:0] ST_INIT_WAIT  = 5'd2;
    localparam [4:0] ST_INIT_DELAY = 5'd3;
    localparam [4:0] ST_ROW_Y_REQ  = 5'd4;
    localparam [4:0] ST_ROW_Y_WAIT = 5'd5;
    localparam [4:0] ST_ROW_X_REQ  = 5'd6;
    localparam [4:0] ST_ROW_X_WAIT = 5'd7;
    localparam [4:0] ST_DATA_ADDR  = 5'd8;
    localparam [4:0] ST_DATA_READY = 5'd9;
    localparam [4:0] ST_DATA_REQ   = 5'd10;
    localparam [4:0] ST_DATA_WAIT  = 5'd11;

    reg [4:0]  state;
    reg [31:0] delay_counter;
    reg [2:0]  init_index;
    reg [5:0]  logical_row;
    reg [3:0]  byte_column;
    reg [1:0]  frame_mode;
    reg [4:0]  frame_tone_khz;
    reg        frame_auto_sweep;
    reg        frame_ila_demo_enable;
    reg [15:0] frame_magnitude_15k_pre;
    reg [15:0] frame_magnitude_15k_post;
    reg [15:0] frame_magnitude_40k_pre;
    reg [15:0] frame_magnitude_40k_post;
    reg [7:0]  frame_suppression_40k_db;
    reg        frame_measurement_valid;

    // BRAM 地址不能由异步复位寄存器驱动；这里使用同步复位，
    // 避免推断出的 RAMB36 产生 REQP-1839 告警。
    always @(posedge clk) begin
        if (!rst_n)
            rom_address <= 13'd0;
        else if (state == ST_DATA_ADDR)
            rom_address <= frame_ila_demo_enable ?
                           {1'b1, 2'b00, logical_row, byte_column} :
                           {1'b0, frame_mode, logical_row, byte_column};
    end

    function [7:0] init_command;
        input [2:0] index;
        begin
            case (index)
                3'd0: init_command = 8'h30; // 8bit 基本指令集
                3'd1: init_command = 8'h30;
                3'd2: init_command = 8'h30;
                3'd3: init_command = 8'h0C; // 开显示，关闭光标
                3'd4: init_command = 8'h01; // 清除 DDRAM
                3'd5: init_command = 8'h06; // 进入模式设置
                3'd6: init_command = 8'h34; // 扩展指令集
                3'd7: init_command = 8'h36; // 扩展指令集并打开图形显示
                default: init_command = 8'h30;
            endcase
        end
    endfunction

    //=========================================================
    // 动态 5x7 字符叠加
    //
    // ROM 已为倒装液晶旋转 180°。源界面中的两个数字位于
    // x=72/80、y=25～31，AUTO 标记位于 x=120、y=25～31；
    // 因此在旋转后的 ROM 坐标中分别对应 byte 6/5/0、row 32～38。
    //=========================================================
    function [4:0] glyph_row_5x7;
        input [3:0] glyph;
        input [2:0] row;
        reg [34:0] bitmap;
        begin
            case (glyph)
                4'd0: bitmap = {5'b01110, 5'b10001, 5'b10011, 5'b10101,
                                 5'b11001, 5'b10001, 5'b01110};
                4'd1: bitmap = {5'b00100, 5'b01100, 5'b00100, 5'b00100,
                                 5'b00100, 5'b00100, 5'b01110};
                4'd2: bitmap = {5'b01110, 5'b10001, 5'b00001, 5'b00010,
                                 5'b00100, 5'b01000, 5'b11111};
                4'd3: bitmap = {5'b11110, 5'b00001, 5'b00001, 5'b01110,
                                 5'b00001, 5'b00001, 5'b11110};
                4'd4: bitmap = {5'b00010, 5'b00110, 5'b01010, 5'b10010,
                                 5'b11111, 5'b00010, 5'b00010};
                4'd5: bitmap = {5'b11111, 5'b10000, 5'b10000, 5'b11110,
                                 5'b00001, 5'b00001, 5'b11110};
                4'd6: bitmap = {5'b01110, 5'b10000, 5'b10000, 5'b11110,
                                 5'b10001, 5'b10001, 5'b01110};
                4'd7: bitmap = {5'b11111, 5'b00001, 5'b00010, 5'b00100,
                                 5'b01000, 5'b01000, 5'b01000};
                4'd8: bitmap = {5'b01110, 5'b10001, 5'b10001, 5'b01110,
                                 5'b10001, 5'b10001, 5'b01110};
                4'd9: bitmap = {5'b01110, 5'b10001, 5'b10001, 5'b01111,
                                 5'b00001, 5'b00001, 5'b01110};
                4'd10: bitmap = {5'b01110, 5'b10001, 5'b10001, 5'b11111,
                                  5'b10001, 5'b10001, 5'b10001};
                4'd11: bitmap = {5'b00000, 5'b00000, 5'b00000, 5'b11111,
                                  5'b00000, 5'b00000, 5'b00000};
                default: bitmap = 35'd0;
            endcase

            case (row)
                3'd0: glyph_row_5x7 = bitmap[34:30];
                3'd1: glyph_row_5x7 = bitmap[29:25];
                3'd2: glyph_row_5x7 = bitmap[24:20];
                3'd3: glyph_row_5x7 = bitmap[19:15];
                3'd4: glyph_row_5x7 = bitmap[14:10];
                3'd5: glyph_row_5x7 = bitmap[9:5];
                3'd6: glyph_row_5x7 = bitmap[4:0];
                default: glyph_row_5x7 = 5'd0;
            endcase
        end
    endfunction

    function [7:0] tone_overlay_byte;
        input [4:0] frequency_khz;
        input       auto_enabled;
        input [5:0] row;
        input [3:0] column;
        reg [4:0] effective_frequency;
        reg [3:0] tens_digit;
        reg [3:0] ones_digit;
        reg [3:0] selected_glyph;
        reg [4:0] glyph_pixels;
        reg [2:0] source_row;
        begin
            tone_overlay_byte = 8'h00;
            effective_frequency = ((frequency_khz >= 5'd1) &&
                                   (frequency_khz <= 5'd20)) ?
                                  frequency_khz : 5'd15;

            if (effective_frequency >= 5'd20) begin
                tens_digit = 4'd2;
                ones_digit = 4'd0;
            end
            else if (effective_frequency >= 5'd10) begin
                tens_digit = 4'd1;
                ones_digit = effective_frequency - 5'd10;
            end
            else begin
                tens_digit = 4'd0;
                ones_digit = effective_frequency[3:0];
            end

            if ((row >= 6'd32) && (row <= 6'd38)) begin
                // 垂直方向同样需要反转回源界面的 0～6 行。
                source_row = 6'd38 - row;

                if (column == 4'd6)
                    selected_glyph = tens_digit;
                else if (column == 4'd5)
                    selected_glyph = ones_digit;
                else if ((column == 4'd0) && auto_enabled)
                    selected_glyph = 4'd10;
                else
                    selected_glyph = 4'd15;

                glyph_pixels = glyph_row_5x7(selected_glyph, source_row);

                // 180° 旋转还要求 5 个横向像素逆序。
                tone_overlay_byte = {3'b000, glyph_pixels[0], glyph_pixels[1],
                                      glyph_pixels[2], glyph_pixels[3],
                                      glyph_pixels[4]};
            end
        end
    endfunction

    function [4:0] demo_bar_units;
        input [15:0] magnitude;
        begin
            // 每格 6 像素；0.20FS 相干分量通常达到 12～15 格。
            if (|magnitude[15:14] || (magnitude[13:10] >= 4'd15))
                demo_bar_units = 5'd15;
            else
                demo_bar_units = {1'b0, magnitude[13:10]};
        end
    endfunction

    function [7:0] demo_overlay_byte;
        input [15:0] mag_15k_pre;
        input [15:0] mag_15k_post;
        input [15:0] mag_40k_pre;
        input [15:0] mag_40k_post;
        input [7:0]  suppression_db;
        input        valid;
        input [5:0]  row;
        input [3:0]  column;
        integer pixel_index;
        integer source_x;
        integer source_y;
        integer bar_end_x;
        reg pixel_on;
        reg [3:0] tens_digit;
        reg [3:0] ones_digit;
        reg [3:0] selected_glyph;
        reg [4:0] glyph_pixels;
        begin
            demo_overlay_byte = 8'h00;
            tens_digit = (suppression_db >= 8'd99) ? 4'd9 :
                         (suppression_db / 8'd10);
            ones_digit = (suppression_db >= 8'd99) ? 4'd9 :
                         (suppression_db % 8'd10);

            // ROM 页面已经旋转 180°，这里先映射回正向源坐标，
            // 再绘制柱状条和两个 5x7 衰减数字。
            for (pixel_index = 0; pixel_index < 8;
                 pixel_index = pixel_index + 1) begin
                source_x = 127 - ((column * 8) + pixel_index);
                source_y = 63 - row;
                pixel_on = 1'b0;

                if (valid && (source_x >= 29)) begin
                    if ((source_y >= 23) && (source_y <= 25)) begin
                        bar_end_x = 29 + demo_bar_units(mag_15k_pre) * 6;
                        if (source_x < bar_end_x)
                            pixel_on = 1'b1;
                    end
                    else if ((source_y >= 31) && (source_y <= 33)) begin
                        bar_end_x = 29 + demo_bar_units(mag_15k_post) * 6;
                        if (source_x < bar_end_x)
                            pixel_on = 1'b1;
                    end
                    else if ((source_y >= 39) && (source_y <= 41)) begin
                        bar_end_x = 29 + demo_bar_units(mag_40k_pre) * 6;
                        if (source_x < bar_end_x)
                            pixel_on = 1'b1;
                    end
                    else if ((source_y >= 47) && (source_y <= 49)) begin
                        bar_end_x = 29 + demo_bar_units(mag_40k_post) * 6;
                        if (source_x < bar_end_x)
                            pixel_on = 1'b1;
                    end
                end

                if ((source_y >= 54) && (source_y <= 60)) begin
                    if ((source_x >= 34) && (source_x <= 38)) begin
                        selected_glyph = valid ? tens_digit : 4'd11;
                        glyph_pixels = glyph_row_5x7(
                            selected_glyph, source_y - 54);
                        if (glyph_pixels[4-(source_x-34)])
                            pixel_on = 1'b1;
                    end
                    else if ((source_x >= 42) && (source_x <= 46)) begin
                        selected_glyph = valid ? ones_digit : 4'd11;
                        glyph_pixels = glyph_row_5x7(
                            selected_glyph, source_y - 54);
                        if (glyph_pixels[4-(source_x-42)])
                            pixel_on = 1'b1;
                    end
                end

                demo_overlay_byte[7-pixel_index] = pixel_on;
            end
        end
    endfunction

    // 写请求多路选择；请求保持有效，直到并口引擎接收。
    always @(*) begin
        write_request = 1'b0;
        write_rs      = 1'b0;
        write_data    = 8'h00;

        case (state)
            ST_INIT_REQ: begin
                write_request = !io_busy;
                write_rs      = 1'b0;
                write_data    = init_command(init_index);
            end

            ST_ROW_Y_REQ: begin
                write_request = !io_busy;
                write_rs      = 1'b0;
                write_data    = 8'h80 | {3'b000, logical_row[4:0]};
            end

            ST_ROW_X_REQ: begin
                write_request = !io_busy;
                write_rs      = 1'b0;
                // ST7920 的 0～31 行从水平字地址 0 开始，
                // 32～63 行从水平字地址 8 开始。
                write_data    = logical_row[5] ? 8'h88 : 8'h80;
            end

            ST_DATA_REQ: begin
                write_request = !io_busy;
                write_rs      = 1'b1;
                if (frame_ila_demo_enable)
                    write_data = rom_data |
                        demo_overlay_byte(
                            frame_magnitude_15k_pre,
                            frame_magnitude_15k_post,
                            frame_magnitude_40k_pre,
                            frame_magnitude_40k_post,
                            frame_suppression_40k_db,
                            frame_measurement_valid,
                            logical_row,
                            byte_column);
                else
                    write_data = rom_data |
                        tone_overlay_byte(frame_tone_khz,
                                          frame_auto_sweep,
                                          logical_row,
                                          byte_column);
            end

            default: begin
                write_request = 1'b0;
            end
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state         <= ST_POWER_WAIT;
            delay_counter <= 32'd0;
            init_index    <= 3'd0;
            logical_row   <= 6'd0;
            byte_column   <= 4'd0;
            frame_mode    <= 2'b11;
            frame_tone_khz <= 5'd15;
            frame_auto_sweep <= 1'b0;
            frame_ila_demo_enable <= 1'b0;
            frame_magnitude_15k_pre  <= 16'd0;
            frame_magnitude_15k_post <= 16'd0;
            frame_magnitude_40k_pre  <= 16'd0;
            frame_magnitude_40k_post <= 16'd0;
            frame_suppression_40k_db <= 8'd0;
            frame_measurement_valid  <= 1'b0;
        end
        else begin
            case (state)
                ST_POWER_WAIT: begin
                    if (delay_counter >= POWERUP_CYCLES - 1) begin
                        delay_counter <= 32'd0;
                        init_index    <= 3'd0;
                        state         <= ST_INIT_REQ;
                    end
                    else begin
                        delay_counter <= delay_counter + 32'd1;
                    end
                end

                ST_INIT_REQ: begin
                    if (!io_busy)
                        state <= ST_INIT_WAIT;
                end

                ST_INIT_WAIT: begin
                    if (io_done) begin
                        delay_counter <= 32'd0;
                        state <= ST_INIT_DELAY;
                    end
                end

                ST_INIT_DELAY: begin
                    if ((init_index == 3'd4 &&
                         delay_counter >= CLEAR_DELAY_CYCLES - 1) ||
                        (init_index != 3'd4 &&
                         delay_counter >= INIT_DELAY_CYCLES - 1)) begin
                        delay_counter <= 32'd0;
                        if (init_index == 3'd7) begin
                            frame_mode       <= mode_sel;
                            frame_tone_khz   <= tone_khz;
                            frame_auto_sweep <= auto_sweep;
                            frame_ila_demo_enable <= ila_demo_enable;
                            frame_magnitude_15k_pre  <= magnitude_15k_pre;
                            frame_magnitude_15k_post <= magnitude_15k_post;
                            frame_magnitude_40k_pre  <= magnitude_40k_pre;
                            frame_magnitude_40k_post <= magnitude_40k_post;
                            frame_suppression_40k_db <= suppression_40k_db;
                            frame_measurement_valid  <= measurement_valid;
                            logical_row      <= 6'd0;
                            byte_column      <= 4'd0;
                            state            <= ST_ROW_Y_REQ;
                        end
                        else begin
                            init_index <= init_index + 3'd1;
                            state      <= ST_INIT_REQ;
                        end
                    end
                    else begin
                        delay_counter <= delay_counter + 32'd1;
                    end
                end

                ST_ROW_Y_REQ: begin
                    if (!io_busy)
                        state <= ST_ROW_Y_WAIT;
                end

                ST_ROW_Y_WAIT: begin
                    if (io_done)
                        state <= ST_ROW_X_REQ;
                end

                ST_ROW_X_REQ: begin
                    if (!io_busy)
                        state <= ST_ROW_X_WAIT;
                end

                ST_ROW_X_WAIT: begin
                    if (io_done) begin
                        byte_column <= 4'd0;
                        state <= ST_DATA_ADDR;
                    end
                end

                ST_DATA_ADDR: begin
                    state <= ST_DATA_READY;
                end

                ST_DATA_READY: begin
                    // 同步 Block ROM 读取等待一个时钟周期。
                    state <= ST_DATA_REQ;
                end

                ST_DATA_REQ: begin
                    if (!io_busy)
                        state <= ST_DATA_WAIT;
                end

                ST_DATA_WAIT: begin
                    if (io_done) begin
                        if (byte_column == 4'd15) begin
                            byte_column <= 4'd0;
                            if (logical_row == 6'd63) begin
                                logical_row      <= 6'd0;
                                frame_mode       <= mode_sel;
                                frame_tone_khz   <= tone_khz;
                                frame_auto_sweep <= auto_sweep;
                                frame_ila_demo_enable <= ila_demo_enable;
                                frame_magnitude_15k_pre  <= magnitude_15k_pre;
                                frame_magnitude_15k_post <= magnitude_15k_post;
                                frame_magnitude_40k_pre  <= magnitude_40k_pre;
                                frame_magnitude_40k_post <= magnitude_40k_post;
                                frame_suppression_40k_db <= suppression_40k_db;
                                frame_measurement_valid  <= measurement_valid;
                            end
                            else begin
                                logical_row <= logical_row + 6'd1;
                            end
                            state <= ST_ROW_Y_REQ;
                        end
                        else begin
                            byte_column <= byte_column + 4'd1;
                            state <= ST_DATA_ADDR;
                        end
                    end
                end

                default: begin
                    state <= ST_POWER_WAIT;
                    delay_counter <= 32'd0;
                end
            endcase
        end
    end

endmodule
