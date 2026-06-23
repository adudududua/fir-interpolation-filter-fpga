`timescale 1ns / 1ps

module board_demo_top_128x(
    input  wire clk,      // 板载系统时钟
    input  wire rst_n     // 低有效复位
);

    //====================================================
    // 1) 产生 128x 链路所需的 6 级 CE
    //
    // 说明：
    // 这里的最终输出时钟视为“当前系统时钟”。
    // 各级 CE 只负责表达 4x/8x/16x/32x/64x/128x 之间的节拍关系。
    //
    // 当前实现主要用于：
    // - 最高倍率结构综合/实现
    // - 资源/时序/功耗评估
    // - 板级功能验证
    //
    // 后续如果你要严格跑 5.6448MHz / 6.144MHz，
    // 只需要把 clk 换成 Clocking Wizard 生成的模式时钟，
    // 本文件其余逻辑基本不用变。
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

    // 用 negedge 更新计数器，保证下一次 posedge 时，
    // DUT 看到稳定好的 CE
    always @(negedge clk or negedge rst_n) begin
        if (!rst_n)
            ce_cnt <= 5'd0;
        else
            ce_cnt <= ce_cnt + 5'd1;
    end

    //====================================================
    // 2) 内部测试输入
    //
    // 思路：
    // - 4x 级每 32 个最终输出时钟推进一次
    // - 4x 一共有 4 个相位
    // - 因此一个原始输入样本保持 128 个最终输出时钟，
    //   就能完整覆盖一轮 phase=0/1/2/3
    //
    // 这里让 x_in_valid 始终为 1（复位后），
    // x_in 每 128 个最终输出时钟更新一次。
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
    // 3) 例化 128x 顶层
    //====================================================
    wire signed [23:0] y_out_w;
    wire               y_out_valid_w;

    // 注意：这里的 y_out_w 和 y_out_valid_w 是直接从 DUT 输出的原始信号，
    // 没有经过任何后续处理。
    // 你可以直接观察它们，或者在后续的 always 块中对它们进行寄存以观察时序关系。
    // 调试引出
    wire signed [23:0] dbg_y4_w;
    wire               dbg_y4_valid_w;
    wire signed [23:0] dbg_y8_w;
    wire               dbg_y8_valid_w;
    wire signed [23:0] dbg_y32_w;
    wire               dbg_y32_valid_w;
    wire signed [23:0] dbg_y64_w;
    wire               dbg_y64_valid_w;

    // 这里的 interp128_top_ce 模块是你需要实现的 DUT。
    // 通过观察它的输入输出和调试信号，你可以验证你的设计是否正确，
    // 以及各级之间的时序关系是否符合预期。
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
    // 4) 保留关键结果，防止综合器优化掉整条链路
    //====================================================
    (* dont_touch = "true" *) reg signed [23:0] hold_y_out;
    (* dont_touch = "true" *) reg               hold_y_out_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hold_y_out       <= 24'sd0;
            hold_y_out_valid <= 1'b0;
        end
        else begin
            hold_y_out       <= y_out_w;
            hold_y_out_valid <= y_out_valid_w;
        end
    end

    //====================================================
    // 5) 128x 板级调试 ILA
    //====================================================
    ila_128x_0 u_ila_128x_0 (
        .clk     (clk),

        .probe0  (ce_cnt),            // [4:0]
        .probe1  (ce64_out),          // 1
        .probe2  (ce32_out),          // 1
        .probe3  (ce16_out),          // 1
        .probe4  (ce8_out),           // 1
        .probe5  (ce4_out),           // 1
        .probe6  (x_in_valid),        // 1
        .probe7  (x_in),              // [23:0]
        .probe8  (dbg_y4_valid_w),    // 1
        .probe9  (dbg_y4_w),          // [23:0]
        .probe10 (dbg_y8_valid_w),    // 1
        .probe11 (dbg_y8_w),          // [23:0]
        .probe12 (dbg_y32_valid_w),   // 1
        .probe13 (dbg_y32_w),         // [23:0]
        .probe14 (dbg_y64_valid_w),   // 1
        .probe15 (dbg_y64_w),         // [23:0]
        .probe16 (y_out_valid_w),     // 1
        .probe17 (y_out_w)            // [23:0]
    );

endmodule