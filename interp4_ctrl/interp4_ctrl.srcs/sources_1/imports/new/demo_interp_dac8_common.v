`timescale 1ns / 1ps

// ============================================================
// 插值链 DAC 演示模块
//
// 作用：
// 1. 生成 1MHz DAC 时钟
// 2. 生成 128x 链路所需的 CE 脉冲
// 3. 用板内 64 点正弦 ROM 作为输入源
// 4. 实例化 interp128_top_ce
// 5. 自动轮播显示 4x / 8x / 128x 三种模式
// 6. 把选中的 24bit 输出映射成 8bit DAC 数据
// ============================================================
module demo_interp_dac8_common (
    input  wire        clk,
    input  wire        rst_n,
    output wire        dac_clk,
    output wire [7:0]  dac_data,
    output wire [1:0]  mode_led
);

    // ========================================================
    // 模式定义
    // ========================================================
    localparam [1:0] MODE_4X   = 2'b01;
    localparam [1:0] MODE_8X   = 2'b10;
    localparam [1:0] MODE_128X = 2'b11;

    // 50MHz -> 1MHz DAC 时钟
    localparam integer DAC_HALF_DIV = 25;

    // 每个输入样本保持多少个 sample_tick
    // 128 -> 约 122Hz
    // 4   -> 约 3.906kHz，更容易看出 4x/8x/128x 的差别
    localparam integer INPUT_HOLD_TICKS = 128;
    localparam [5:0] ROM_ADDR_STEP = 6'd12;



    // 每个模式保持 3 秒
    localparam integer MODE_HOLD_CYCLES = 150_000_000;

    // ========================================================
    // 1) 生成 1MHz DAC 时钟，同时给系统一个 sample_tick
    //
    // dac_clk_r 每 25 个系统时钟翻转一次：
    // 50MHz / 50 = 1MHz
    //
    // sample_tick：
    // 每一个完整 DAC 周期来一次脉冲
    // 用来作为“128x 链的基础节拍”
    // ========================================================
    reg       dac_clk_r;
    reg [5:0] div_cnt;
    reg       sample_tick_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dac_clk_r     <= 1'b0;
            div_cnt       <= 6'd0;
            sample_tick_r <= 1'b0;
        end
        else begin
            sample_tick_r <= 1'b0;

            if (div_cnt == DAC_HALF_DIV - 1) begin
                div_cnt <= 6'd0;

                // 如果当前 dac_clk 是高电平，
                // 这次翻转后会变成低电平，
                // 同时打一拍 sample_tick
                if (dac_clk_r == 1'b1)
                    sample_tick_r <= 1'b1;

                dac_clk_r <= ~dac_clk_r;
            end
            else begin
                div_cnt <= div_cnt + 6'd1;
            end
        end
    end

    assign dac_clk = dac_clk_r;

    // ========================================================
    // 2) 生成 128x 链路的 CE 脉冲
    //
    // 注意这里和最早的“每拍都跑 CE”不同：
    // 我们现在以 sample_tick 作为最基础的“128x 输出节拍”
    //
    // 也就是说：
    // ce128_out : 每个 sample_tick 有效一次 -> 1MHz
    // ce64_out  : 每 2 个 sample_tick 有效一次 -> 500kHz
    // ce32_out  : 每 4 个 sample_tick 有效一次 -> 250kHz
    // ce16_out  : 每 8 个 sample_tick 有效一次 -> 125kHz
    // ce8_out   : 每 16 个 sample_tick 有效一次 -> 62.5kHz
    // ce4_out   : 每 32 个 sample_tick 有效一次 -> 31.25kHz
    //
    // 这样既保留了 4x / 8x / 128x 的倍率关系，
    // 又让 DAC 演示频率处在一个更容易观测的范围。
    // ========================================================
    reg [4:0] ce_cnt;

    wire ce128_out;
    wire ce64_out;
    wire ce32_out;
    wire ce16_out;
    wire ce8_out;
    wire ce4_out;

    assign ce128_out = sample_tick_r;
    assign ce64_out  = sample_tick_r && (ce_cnt[0]   == 1'b0);
    assign ce32_out  = sample_tick_r && (ce_cnt[1:0] == 2'b00);
    assign ce16_out  = sample_tick_r && (ce_cnt[2:0] == 3'b000);
    assign ce8_out   = sample_tick_r && (ce_cnt[3:0] == 4'b0000);
    assign ce4_out   = sample_tick_r && (ce_cnt[4:0] == 5'b00000);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ce_cnt <= 5'd0;
        else if (sample_tick_r)
            ce_cnt <= ce_cnt + 5'd1;
    end

    // ========================================================
    // 3) 板内输入波形发生器
    //
    // 这里仍然使用 64 点正弦 LUT，24bit signed。
    // 但注意：
    // 输入样本不是每个 sample_tick 都换，
    // 而是每 128 个 sample_tick 才换一次。
    //
    // 这对应“输入采样率 = 128x 输出采样率 / 128”
    // 也就是：
    // 1MHz / 128 = 7.8125kHz
    //
    // 所以 64 点正弦的模拟频率约为：
    // 7812.5 / 64 = 122.07 Hz
    // ========================================================
    reg signed [23:0] x_in;
    reg               x_in_valid;
    reg [6:0]         hold_cnt;
    reg [5:0]         rom_addr;

    reg signed [23:0] wave_rom [0:63];

    initial begin
        wave_rom[ 0] =  24'sd0;
        wave_rom[ 1] =  24'sd575559;
        wave_rom[ 2] =  24'sd1145575;
        wave_rom[ 3] =  24'sd1704559;
        wave_rom[ 4] =  24'sd2247127;
        wave_rom[ 5] =  24'sd2768053;
        wave_rom[ 6] =  24'sd3262322;
        wave_rom[ 7] =  24'sd3725173;
        wave_rom[ 8] =  24'sd4152149;
        wave_rom[ 9] =  24'sd4539137;
        wave_rom[10] =  24'sd4882410;
        wave_rom[11] =  24'sd5178664;
        wave_rom[12] =  24'sd5425044;
        wave_rom[13] =  24'sd5619178;
        wave_rom[14] =  24'sd5759196;
        wave_rom[15] =  24'sd5843750;
        wave_rom[16] =  24'sd5872025;
        wave_rom[17] =  24'sd5843750;
        wave_rom[18] =  24'sd5759196;
        wave_rom[19] =  24'sd5619178;
        wave_rom[20] =  24'sd5425044;
        wave_rom[21] =  24'sd5178664;
        wave_rom[22] =  24'sd4882410;
        wave_rom[23] =  24'sd4539137;
        wave_rom[24] =  24'sd4152149;
        wave_rom[25] =  24'sd3725173;
        wave_rom[26] =  24'sd3262322;
        wave_rom[27] =  24'sd2768053;
        wave_rom[28] =  24'sd2247127;
        wave_rom[29] =  24'sd1704559;
        wave_rom[30] =  24'sd1145575;
        wave_rom[31] =  24'sd575559;
        wave_rom[32] =  24'sd0;
        wave_rom[33] = -24'sd575559;
        wave_rom[34] = -24'sd1145575;
        wave_rom[35] = -24'sd1704559;
        wave_rom[36] = -24'sd2247127;
        wave_rom[37] = -24'sd2768053;
        wave_rom[38] = -24'sd3262322;
        wave_rom[39] = -24'sd3725173;
        wave_rom[40] = -24'sd4152149;
        wave_rom[41] = -24'sd4539137;
        wave_rom[42] = -24'sd4882410;
        wave_rom[43] = -24'sd5178664;
        wave_rom[44] = -24'sd5425044;
        wave_rom[45] = -24'sd5619178;
        wave_rom[46] = -24'sd5759196;
        wave_rom[47] = -24'sd5843750;
        wave_rom[48] = -24'sd5872025;
        wave_rom[49] = -24'sd5843750;
        wave_rom[50] = -24'sd5759196;
        wave_rom[51] = -24'sd5619178;
        wave_rom[52] = -24'sd5425044;
        wave_rom[53] = -24'sd5178664;
        wave_rom[54] = -24'sd4882410;
        wave_rom[55] = -24'sd4539137;
        wave_rom[56] = -24'sd4152149;
        wave_rom[57] = -24'sd3725173;
        wave_rom[58] = -24'sd3262322;
        wave_rom[59] = -24'sd2768053;
        wave_rom[60] = -24'sd2247127;
        wave_rom[61] = -24'sd1704559;
        wave_rom[62] = -24'sd1145575;
        wave_rom[63] = -24'sd575559;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_in       <= 24'sd0;
            x_in_valid <= 1'b0;
            hold_cnt   <= 7'd0;
            rom_addr   <= 6'd0;
        end
        else begin
            x_in_valid <= 1'b1;

            if (sample_tick_r) begin
                if (hold_cnt == 7'd0) begin
                    x_in <= wave_rom[rom_addr];

                    rom_addr <= rom_addr + ROM_ADDR_STEP;

                    hold_cnt <= 7'd1;
                end
                else if (hold_cnt == INPUT_HOLD_TICKS - 1) begin
                    hold_cnt <= 7'd0;
                end
                else begin
                    hold_cnt <= hold_cnt + 7'd1;
                end
            end
        end
    end

    // ========================================================
    // 4) 实例化统一 128x 插值链
    // ========================================================
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

    interp128_top_ce #(
        .DATA_W   (24),
        .COEFF_W  (18),
        .ACC_W    (56),
        .NTAPS4X  (155),
        .NTAPS2X  (11)
    ) u_interp128_top_ce (
        .clk            (clk),
        .rst_n          (rst_n),

        .ce4_out        (ce4_out),
        .ce8_out        (ce8_out),
        .ce16_out       (ce16_out),
        .ce32_out       (ce32_out),
        .ce64_out       (ce64_out),
        .ce128_out      (ce128_out),

        .x_in           (x_in),
        .x_in_valid     (x_in_valid),

        .y_out          (y_out_w),
        .y_out_valid    (y_out_valid_w),

        .dbg_y4         (dbg_y4_w),
        .dbg_y4_valid   (dbg_y4_valid_w),
        .dbg_y8         (dbg_y8_w),
        .dbg_y8_valid   (dbg_y8_valid_w),
        .dbg_y32        (dbg_y32_w),
        .dbg_y32_valid  (dbg_y32_valid_w),
        .dbg_y64        (dbg_y64_w),
        .dbg_y64_valid  (dbg_y64_valid_w)
    );

    // ========================================================
    // 5) 固定模式选择
    //
    // 当前先固定为 4x，便于单独观察和拍图。
    // 后面如果要测 8x / 128x，只需要改 FIXED_MODE。
    // ========================================================
    localparam [1:0] FIXED_MODE = MODE_4X;

    wire [1:0] mode_state;
    assign mode_state = FIXED_MODE;

    assign mode_led = mode_state;


    // ========================================================
    // 6) 节点选择
    //
    // 根据当前模式，从统一链路里挑一个节点出来：
    // 4x   -> dbg_y4
    // 8x   -> dbg_y8
    // 128x -> y_out
    //
    // current_sample 用来做“保持”，
    // 这样在某个节点没有新样本时，DAC 还能继续输出最近一个值。
    // ========================================================
    reg signed [23:0] selected_sample;
    reg               selected_valid;
    reg signed [23:0] current_sample;

    always @(*) begin
        case (mode_state)
            MODE_4X: begin
                selected_sample = dbg_y4_w;
                selected_valid  = dbg_y4_valid_w;
            end

            MODE_8X: begin
                selected_sample = dbg_y8_w;
                selected_valid  = dbg_y8_valid_w;
            end

            default: begin
                selected_sample = y_out_w;
                selected_valid  = y_out_valid_w;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_sample <= 24'sd0;
        else if (selected_valid)
            current_sample <= selected_sample;
    end

    // ========================================================
    // 7) 按模式做显示补偿，再映射到 8bit DAC
    //
    // 这里只是为了板级示波器展示，不改变插值核心本身。
    // 目的是让 4x / 8x / 128x 三种模式在 DAC 上的显示幅度更接近：
    //
    // 4x   -> 不补偿
    // 8x   -> 放大 2 倍
    // 128x -> 放大 32 倍
    //
    // 注意：
    // 这里的补偿只用于 DAC 显示，不用于算法正确性判断。
    // ========================================================
    reg  signed [31:0] display_sample_ext;
    reg  signed [23:0] display_sample_sat;

    wire signed [7:0] sample_s8_w;
    wire signed [8:0] sample_bias_w;
    reg        [7:0]  sample_u8_w;
    reg        [7:0]  dac_data_r;

    // 先按模式把当前样本做显示补偿
    always @(*) begin
        case (mode_state)
            MODE_4X: begin
                display_sample_ext = {{8{current_sample[23]}}, current_sample};
            end

            MODE_8X: begin
                display_sample_ext = ({{8{current_sample[23]}}, current_sample} <<< 1);
            end

            default: begin
                display_sample_ext = ({{8{current_sample[23]}}, current_sample} <<< 5);
            end
        endcase
    end

    // 再做 24bit 饱和，避免补偿后溢出
    always @(*) begin
        if (display_sample_ext > 32'sd8388607)
            display_sample_sat = 24'sd8388607;
        else if (display_sample_ext < -32'sd8388608)
            display_sample_sat = -24'sd8388608;
        else
            display_sample_sat = display_sample_ext[23:0];
    end

    // 最后再走原来的 24bit -> 8bit DAC 映射
    assign sample_s8_w   = display_sample_sat[23:16];
    assign sample_bias_w = $signed({sample_s8_w[7], sample_s8_w}) + 9'sd128;

    always @(*) begin
        if (sample_bias_w < 9'sd0)
            sample_u8_w = 8'd0;
        else if (sample_bias_w > 9'sd255)
            sample_u8_w = 8'hFF;
        else
            sample_u8_w = sample_bias_w[7:0];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            dac_data_r <= 8'd128;
        else if (sample_tick_r)
            dac_data_r <= sample_u8_w;
    end

    assign dac_data = dac_data_r;


endmodule
