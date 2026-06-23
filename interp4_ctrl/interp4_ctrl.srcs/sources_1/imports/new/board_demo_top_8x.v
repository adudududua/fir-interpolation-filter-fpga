`timescale 1ns / 1ps

module board_demo_top_8x(
    input  wire clk,      // 板载时钟，例如 50MHz
    input  wire rst_n     // 低有效复位
);

    //====================================================
    // 1) 生成 8x CE 链路所需的两个使能
    //
    // 关键点：
    // - ce8_tick：每个系统时钟都有效
    // - ce4_tick：每隔 1 拍有效一次
    //
    // 这与前面已经对拍通过的 8x CE 仿真结构保持一致。
    //
    // 注意：
    // 这里做的是“比例关系正确的板级验证时序”，
    // 不是去精确合成 352.8k / 384k 的真实音频采样时钟。
    //====================================================
    wire ce8_tick;
    reg  ce4_tick;

    assign ce8_tick = 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ce4_tick <= 1'b0;
        else
            ce4_tick <= ~ce4_tick;
    end

    //====================================================
    // 2) 产生原始输入样本
    //
    // 采用和 testbench 一样的思想：
    // - 每个原始输入样本保持 8 个系统时钟周期
    // - 这样在 4x 级的 4 个相位（0/1/2/3）中，
    //   恰好只有一次 phase=0 会把该样本真正吃进去
    //
    // 这比“猜某一拍精确对齐”更稳，也和你前面仿真
    // 跑通 8x CE 链路时的逻辑一致。
    //====================================================
    reg signed [23:0] x_in;
    reg               x_in_valid;
    reg [2:0]         hold_cnt;   // 0~7
    reg [3:0]         rom_addr;

    // 16点近似正弦 ROM
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
            hold_cnt   <= 3'd0;
            rom_addr   <= 4'd0;
        end
        else begin
            if (hold_cnt == 3'd0) begin
                // 开始一个新的“8拍保持窗口”
                x_in       <= test_rom[rom_addr];
                x_in_valid <= 1'b1;
                hold_cnt   <= 3'd1;

                if (rom_addr == 4'd15)
                    rom_addr <= 4'd0;
                else
                    rom_addr <= rom_addr + 4'd1;
            end
            else if (hold_cnt == 3'd7) begin
                // 第8拍结束，撤掉 valid，下一拍重新开始
                x_in_valid <= 1'b0;
                hold_cnt   <= 3'd0;
            end
            else begin
                // 中间持续保持
                x_in_valid <= 1'b1;
                hold_cnt   <= hold_cnt + 3'd1;
            end
        end
    end

    //====================================================
    // 3) 例化已验证通过的 8x CE 链路
    //====================================================
    wire [1:0]         phase4_dbg_w;
    wire signed [23:0] y4_dbg_w;
    wire               y4_valid_dbg_w;

    wire               phase2_dbg_w;
    wire signed [23:0] fir2_in_dbg_w;
    wire               fir2_in_valid_dbg_w;

    wire signed [23:0] y_out_w;
    wire               y_out_valid_w;

    (* dont_touch = "true" *) interp8_top_ce #(
        .DATA_W   (24),
        .COEFF_W  (18),
        .ACC_W    (56),
        .NTAPS4X  (155),
        .NTAPS2X  (11)
    ) u_interp8_top_ce (
        .clk               (clk),
        .rst_n             (rst_n),

        .ce4_out           (ce4_tick),
        .ce8_out           (ce8_tick),

        .x_in              (x_in),
        .x_in_valid        (x_in_valid),

        .y_out             (y_out_w),
        .y_out_valid       (y_out_valid_w),

        .phase4_dbg        (phase4_dbg_w),
        .y4_dbg            (y4_dbg_w),
        .y4_valid_dbg      (y4_valid_dbg_w),

        .phase2_dbg        (phase2_dbg_w),
        .fir2_in_dbg       (fir2_in_dbg_w),
        .fir2_in_valid_dbg (fir2_in_valid_dbg_w)
    );

    //====================================================
    // 4) 保留关键内部信号，避免被综合优化掉
    //====================================================
    (* dont_touch = "true" *) reg signed [23:0] hold_y_out;
    (* dont_touch = "true" *) reg               hold_y_out_valid;

    (* dont_touch = "true" *) reg signed [23:0] hold_y4;
    (* dont_touch = "true" *) reg               hold_y4_valid;

    (* dont_touch = "true" *) reg signed [23:0] hold_fir2_in;
    (* dont_touch = "true" *) reg               hold_fir2_in_valid;

    (* dont_touch = "true" *) reg [1:0]         hold_phase4;
    (* dont_touch = "true" *) reg               hold_phase2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hold_y_out         <= 24'sd0;
            hold_y_out_valid   <= 1'b0;
            hold_y4            <= 24'sd0;
            hold_y4_valid      <= 1'b0;
            hold_fir2_in       <= 24'sd0;
            hold_fir2_in_valid <= 1'b0;
            hold_phase4        <= 2'd0;
            hold_phase2        <= 1'b0;
        end
        else begin
            hold_y_out         <= y_out_w;
            hold_y_out_valid   <= y_out_valid_w;
            hold_y4            <= y4_dbg_w;
            hold_y4_valid      <= y4_valid_dbg_w;
            hold_fir2_in       <= fir2_in_dbg_w;
            hold_fir2_in_valid <= fir2_in_valid_dbg_w;
            hold_phase4        <= phase4_dbg_w;
            hold_phase2        <= phase2_dbg_w;
        end
    end

    //====================================================
    // 5) 8x 调试 ILA
    //====================================================
    ila_8x_0 u_ila_8x_0 (
        .clk    (clk),

        .probe0  (ce8_tick),            // 1 bit
        .probe1  (ce4_tick),            // 1 bit
        .probe2  (x_in_valid),          // 1 bit
        .probe3  (x_in),                // 24 bit
        .probe4  (phase4_dbg_w),        // 2 bit
        .probe5  (y4_dbg_w),            // 24 bit
        .probe6  (y4_valid_dbg_w),      // 1 bit
        .probe7  (phase2_dbg_w),        // 1 bit
        .probe8  (fir2_in_dbg_w),       // 24 bit
        .probe9  (fir2_in_valid_dbg_w), // 1 bit
        .probe10 (y_out_w),             // 24 bit
        .probe11 (y_out_valid_w)        // 1 bit
    );

endmodule