`timescale 1ns / 1ps

// ============================================================
// DAC 正弦波测试模块
//
// 作用：
// 1. 生成较低速的 DAC 时钟
// 2. 在每个 DAC 采样时刻输出一个 8bit 正弦 LUT 数据
// 3. 让外接 DA9708 输出稳定正弦波
// 4. mode_led 用来指示当前模块在运行
// ============================================================
module demo_dac8_sine_common (
    input  wire        clk,
    input  wire        rst_n,
    output wire        dac_clk,
    output wire [7:0]  dac_data,
    output wire [1:0]  mode_led
);

    // ========================================================
    // 50MHz -> 1MHz DAC 时钟
    //
    // 每 25 个系统时钟翻转一次 dac_clk
    // 所以完整周期 = 50 个系统时钟 = 1us
    // 输出频率 = 1MHz
    // ========================================================
    localparam integer DAC_HALF_DIV = 25;

    reg        dac_clk_r;
    reg [5:0]  div_cnt;

    // ========================================================
    // 32 点正弦查找表
    //
    // 这里输出的是 unsigned 8bit：
    // 128 附近是中点
    // 越接近 255 越高
    // 越接近 0 越低
    //
    // 这样可以直接送给 8bit DAC
    // ========================================================
    reg [7:0] sine_rom [0:31];
    reg [4:0] rom_addr;
    reg [7:0] dac_data_r;

    // LED 慢闪计数器
    reg [25:0] led_cnt;

    initial begin
        sine_rom[ 0] = 8'd128;
        sine_rom[ 1] = 8'd152;
        sine_rom[ 2] = 8'd176;
        sine_rom[ 3] = 8'd198;
        sine_rom[ 4] = 8'd218;
        sine_rom[ 5] = 8'd234;
        sine_rom[ 6] = 8'd245;
        sine_rom[ 7] = 8'd253;
        sine_rom[ 8] = 8'd255;
        sine_rom[ 9] = 8'd253;
        sine_rom[10] = 8'd245;
        sine_rom[11] = 8'd234;
        sine_rom[12] = 8'd218;
        sine_rom[13] = 8'd198;
        sine_rom[14] = 8'd176;
        sine_rom[15] = 8'd152;
        sine_rom[16] = 8'd128;
        sine_rom[17] = 8'd104;
        sine_rom[18] = 8'd80;
        sine_rom[19] = 8'd58;
        sine_rom[20] = 8'd38;
        sine_rom[21] = 8'd22;
        sine_rom[22] = 8'd11;
        sine_rom[23] = 8'd3;
        sine_rom[24] = 8'd0;
        sine_rom[25] = 8'd3;
        sine_rom[26] = 8'd11;
        sine_rom[27] = 8'd22;
        sine_rom[28] = 8'd38;
        sine_rom[29] = 8'd58;
        sine_rom[30] = 8'd80;
        sine_rom[31] = 8'd104;
    end

    // ========================================================
    // 生成 DAC 时钟，并在合适时机更新正弦采样值
    //
    // 这里仍然沿用之前的策略：
    // 在 dac_clk 即将从高翻到低时更新数据，
    // 让下一次上升沿到来前数据已经稳定。
    // ========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt    <= 6'd0;
            dac_clk_r  <= 1'b0;
            rom_addr   <= 5'd0;
            dac_data_r <= 8'd128;
        end
        else begin
            if (div_cnt == DAC_HALF_DIV - 1) begin
                div_cnt <= 6'd0;

                if (dac_clk_r == 1'b1) begin
                    dac_data_r <= sine_rom[rom_addr];

                    if (rom_addr == 5'd31)
                        rom_addr <= 5'd0;
                    else
                        rom_addr <= rom_addr + 5'd1;
                end

                dac_clk_r <= ~dac_clk_r;
            end
            else begin
                div_cnt <= div_cnt + 6'd1;
            end
        end
    end

    // ========================================================
    // LED 慢闪
    // ========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            led_cnt <= 26'd0;
        else
            led_cnt <= led_cnt + 26'd1;
    end

    // ========================================================
    // 输出连接
    // ========================================================
    assign dac_clk  = dac_clk_r;
    assign dac_data = dac_data_r;

    // 表示当前是“正弦测试模式”
    assign mode_led[0] = 1'b0;
    assign mode_led[1] = led_cnt[25];

endmodule
