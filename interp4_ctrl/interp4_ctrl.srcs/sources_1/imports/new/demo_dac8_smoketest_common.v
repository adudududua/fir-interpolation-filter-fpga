`timescale 1ns / 1ps

// ============================================================
// 最小 DAC 冒烟测试模块
//
// 作用：
// 1. 把 50MHz 系统时钟分频成较低速的 dac_clk
// 2. 在每个 DAC 时钟周期，输出一个递增的 8bit 数据
// 3. 这样 DAC 模拟端应该能看到一个“锯齿/台阶波”
// 4. mode_led 用来告诉我们模块确实在运行
// ============================================================
module demo_dac8_smoketest_common (
    input  wire        clk,
    input  wire        rst_n,
    output wire        dac_clk,
    output wire [7:0]  dac_data,
    output wire [1:0]  mode_led
);

    // ========================================================
    // 50MHz -> 1MHz DAC 时钟
    //
    // 思路：
    // 50MHz 的周期是 20ns
    // 如果每 25 个 clk 翻转一次 dac_clk，
    // 那么 dac_clk 的完整周期就是 50 个 clk：
    //
    // 50 * 20ns = 1000ns = 1us
    //
    // 所以输出频率就是 1MHz
    // ========================================================
    localparam integer DAC_HALF_DIV = 25;

    reg [7:0] dac_data_r;
    reg       dac_clk_r;
    reg [5:0] div_cnt;

    // 用于 LED 慢闪，方便肉眼确认模块在运行
    reg [25:0] led_cnt;

    // ========================================================
    // DAC 时钟与 DAC 数据生成
    //
    // 这里有一个小技巧：
    // 我们不在 dac_clk 上升沿那一刻改数据，
    // 而是在 dac_clk 即将翻到低电平时改数据。
    //
    // 这样到下一次 dac_clk 上升沿时，
    // 数据已经稳定了半个周期，更利于 DAC 采样。
    // ========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt    <= 6'd0;
            dac_clk_r  <= 1'b0;
            dac_data_r <= 8'd0;
        end
        else begin
            if (div_cnt == DAC_HALF_DIV - 1) begin
                div_cnt <= 6'd0;

                // 如果当前 DAC 时钟是高电平，
                // 说明这一次翻转后会变成低电平。
                // 我们就在这里更新数据。
                if (dac_clk_r == 1'b1)
                    dac_data_r <= dac_data_r + 8'd1;

                dac_clk_r <= ~dac_clk_r;
            end
            else begin
                div_cnt <= div_cnt + 6'd1;
            end
        end
    end

    // ========================================================
    // LED 慢闪计数器
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

    // mode_led[0] 常亮，表示当前是 smoke test 模式
    // mode_led[1] 慢闪，表示时钟和逻辑在运行
    assign mode_led[0] = 1'b1;
    assign mode_led[1] = led_cnt[25];

endmodule
