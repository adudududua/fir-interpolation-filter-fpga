`timescale 1ns / 1ps

module board_demo_top_final_mode(
    input  wire        clk,         // 板载系统时钟
    input  wire        rst_n,       // 低有效复位
    input  wire [1:0]  mode_sel,    // 00=4x, 01=8x, 10=128x, 11=保留

    output wire        scope_data_out, // 给示波器看的数据输出（1bit）
    output wire        scope_ref_out   // 给示波器看的参考节拍输出（1bit）
);

    //====================================================
    // 1) 产生 128x 链路所需的 6 级 CE
    //====================================================
    reg [4:0] ce_cnt;

    wire ce128_out;
    wire ce64_out;
    wire ce32_out;
    wire ce16_out;
    wire ce8_out;
    wire ce4_out;

    assign ce128_out = 1'b1;
    assign ce64_out  = (ce_cnt[0]   == 1'b0);
    assign ce32_out  = (ce_cnt[1:0] == 2'b00);
    assign ce16_out  = (ce_cnt[2:0] == 3'b000);
    assign ce8_out   = (ce_cnt[3:0] == 4'b000);
    assign ce4_out   = (ce_cnt[4:0] == 5'b000);

    // 用 negedge 更新计数器，保证下一次 posedge 时 DUT 看到稳定好的 CE
    always @(negedge clk or negedge rst_n) begin
        if (!rst_n)
            ce_cnt <= 5'd0;
        else
            ce_cnt <= ce_cnt + 5'd1;
    end

    //====================================================
    // 2) 内部测试输入 ROM
    //
    // 每 128 个最终输出时钟更新一次原始输入样本
    //====================================================
    reg signed [23:0] x_in;
    reg               x_in_valid;
    reg [6:0]         hold_cnt;   // 0~127
    reg [3:0]         rom_addr;

    reg signed [23:0] test_rom [0:15];

    initial begin
        test_rom[0]  =  24'sd0;
        test_rom[1]  =  24'sd2296100;
        test_rom[2]  =  24'sd4242641;
        test_rom[3]  =  24'sd5543277;
        test_rom[4]  =  24'sd6000000;
        test_rom[5]  =  24'sd5543277;
        test_rom[6]  =  24'sd4242641;
        test_rom[7]  =  24'sd2296100;
        test_rom[8]  =  24'sd0;
        test_rom[9]  = -24'sd2296100;
        test_rom[10] = -24'sd4242641;
        test_rom[11] = -24'sd5543277;
        test_rom[12] = -24'sd6000000;
        test_rom[13] = -24'sd5543277;
        test_rom[14] = -24'sd4242641;
        test_rom[15] = -24'sd2296100;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_in       <= 24'sd0;
            x_in_valid <= 1'b0;
            hold_cnt   <= 7'd0;
            rom_addr   <= 4'd0;
        end
        else begin
            x_in_valid <= 1'b1;

            if (hold_cnt == 7'd0) begin
                x_in <= test_rom[rom_addr];

                if (rom_addr == 4'd15)
                    rom_addr <= 4'd0;
                else
                    rom_addr <= rom_addr + 4'd1;

                hold_cnt <= 7'd1;
            end
            else if (hold_cnt == 7'd127) begin
                hold_cnt <= 7'd0;
            end
            else begin
                hold_cnt <= hold_cnt + 7'd1;
            end
        end
    end

    //====================================================
    // 3) 例化统一的 128x 链路
    //
    // 然后从内部各级输出中“选模式”
    //====================================================
    wire signed [23:0] y_out_w;
    wire               y_out_valid_w;

    wire signed [23:0] dbg_y4_w;
    wire               dbg_y4_valid_w;
    wire signed [23:0] dbg_y8_w;
    wire               dbg_y8_valid_w;
    wire signed [23:0] dbg_y32_w;
    wire               dbg_y32_valid_w;
    wire signed [23:0] dbg_y64_w;
    wire               dbg_y64_valid_w;

    (* dont_touch = "true" *) interp128_top_ce #(
        .DATA_W   (24),
        .COEFF_W  (18),
        .ACC_W    (56),
        .NTAPS4X  (155),
        .NTAPS2X  (11)
    ) u_interp128_top_ce (
        .clk         (clk),
        .rst_n       (rst_n),

        .ce4_out     (ce4_out),
        .ce8_out     (ce8_out),
        .ce16_out    (ce16_out),
        .ce32_out    (ce32_out),
        .ce64_out    (ce64_out),
        .ce128_out   (ce128_out),

        .x_in        (x_in),
        .x_in_valid  (x_in_valid),

        .y_out       (y_out_w),
        .y_out_valid (y_out_valid_w),

        .dbg_y4      (dbg_y4_w),
        .dbg_y4_valid(dbg_y4_valid_w),
        .dbg_y8      (dbg_y8_w),
        .dbg_y8_valid(dbg_y8_valid_w),
        .dbg_y32     (dbg_y32_w),
        .dbg_y32_valid(dbg_y32_valid_w),
        .dbg_y64     (dbg_y64_w),
        .dbg_y64_valid(dbg_y64_valid_w)
    );

    //====================================================
    // 4) 模式选择输出
    //====================================================
    reg signed [23:0] y_selected;
    reg               y_selected_valid;
    reg               ref_selected;

    always @(*) begin
        case (mode_sel)
            2'b00: begin
                y_selected       = dbg_y4_w;
                y_selected_valid = dbg_y4_valid_w;
                ref_selected     = ce4_out;
            end

            2'b01: begin
                y_selected       = dbg_y8_w;
                y_selected_valid = dbg_y8_valid_w;
                ref_selected     = ce8_out;
            end

            2'b10: begin
                y_selected       = y_out_w;
                y_selected_valid = y_out_valid_w;
                // 128x 模式下 ce128_out 恒为 1，不适合示波器看节拍
                // 这里改为输出系统时钟作为参考
                ref_selected     = clk;
            end

            default: begin
                y_selected       = dbg_y32_w;
                y_selected_valid = dbg_y32_valid_w;
                ref_selected     = ce32_out;
            end
        endcase
    end

    //====================================================
    // 5) 给示波器的简化输出
    //
    // scope_data_out:
    //   当前模式选中数据的符号位（或最高位）
    //
    // scope_ref_out:
    //   当前模式的参考节拍
    //====================================================
    assign scope_data_out = y_selected[23];
    assign scope_ref_out  = ref_selected;

    //====================================================
    // 6) 保留关键结果，避免综合优化
    //====================================================
    (* dont_touch = "true" *) reg signed [23:0] hold_y_selected;
    (* dont_touch = "true" *) reg               hold_y_selected_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hold_y_selected       <= 24'sd0;
            hold_y_selected_valid <= 1'b0;
        end
        else begin
            hold_y_selected       <= y_selected;
            hold_y_selected_valid <= y_selected_valid;
        end
    end

endmodule