`timescale 1ns / 1ps

// ============================================================
// 模块名：demo_interp_dac8_common
//
// 这个模块是“板无关”的公共演示层。
// 它不关心是 Zynq 板还是后面的赛方板，只做 5 件事：
//
// 1. 生成 CE 节拍（给 4x/8x/16x/.../128x 链路用）
// 2. 生成板内测试输入波形 x_in
// 3. 实例化 interp128_top_ce 这条统一插值链
// 4. 自动轮播 4x / 8x / 128x 三种显示模式
// 5. 把选中的 24bit 输出缩成 8bit，送给并行 DAC
// ============================================================
module demo_interp_dac8_common (
    input  wire        clk,       // 系统时钟
    input  wire        rst_n,     // 低有效复位
    output wire        dac_clk,   // 给 DAC 的时钟，当前直接等于系统时钟
    output wire [7:0]  dac_data,  // 给 DAC 的 8bit 数据
    output wire [1:0]  mode_led   // 当前模式显示：01=4x, 10=8x, 11=128x
);

    // ========================================================
    // 模式编码定义
    // ========================================================
    localparam [1:0] MODE_4X   = 2'b01;
    localparam [1:0] MODE_8X   = 2'b10;
    localparam [1:0] MODE_128X = 2'b11;

    // 每个模式保持多久
    // 如果 clk = 50MHz，那么 150_000_000 个时钟周期就是 3 秒
    localparam integer MODE_HOLD_CYCLES = 150_000_000;

    // ========================================================
    // 1) CE 发生器
    //
    // 这里的 CE 不是“真实采样时钟”，而是“使能节拍”。
    // 目的是在同一个系统时钟下，模拟出不同倍率链路的工作节奏。
    //
    // ce128_out：每拍都有效
    // ce64_out ：每 2 拍有效一次
    // ce32_out ：每 4 拍有效一次
    // ce16_out ：每 8 拍有效一次
    // ce8_out  ：每 16 拍有效一次
    // ce4_out  ：每 32 拍有效一次
    //
    // 这样就和当前 interp128_top_ce 的用法一致。
    // ========================================================
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
    assign ce8_out   = (ce_cnt[3:0] == 4'b0000);
    assign ce4_out   = (ce_cnt[4:0] == 5'b00000);

    // 为什么在 negedge 更新 ce_cnt：
    // 因为这样可以让 DUT 在 posedge 用到的是“已经稳定好”的 CE，
    // 这是你当前工程原来就在用的做法，避免重新引入对拍风险。
    always @(negedge clk or negedge rst_n) begin
        if (!rst_n)
            ce_cnt <= 5'd0;
        else
            ce_cnt <= ce_cnt + 5'd1;
    end

    // ========================================================
    // 2) 板内波形发生器
    //
    // 这里不用外部输入，不用原来的文件输入，也不用旧版 16 点 ROM。
    // 我们自己在板内放一个 64 点正弦表 wave_rom。
    //
    // x_in 是送给插值链的“原始输入采样”。
    // x_in_valid 在复位后一直拉高，表示输入有效。
    //
    // hold_cnt 的作用：
    // 让每个输入样本保持 128 个最终输出时钟周期。
    // 这样就对应“128x 链路”输入更新一次、输出跑 128 个点的节奏。
    // ========================================================
    reg signed [23:0] x_in;
    reg               x_in_valid;
    reg [6:0]         hold_cnt;   // 0~127
    reg [5:0]         rom_addr;   // 0~63，对应 64 点正弦 ROM 地址

    // 64 点正弦波 ROM
    // 幅度约 0.7FS，最大值约 5,872,025
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

    // 输入更新逻辑：
    // 只有当 hold_cnt == 0 时，才从 ROM 里取下一个样本。
    // 其余时间 x_in 保持不变。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_in       <= 24'sd0;
            x_in_valid <= 1'b0;
            hold_cnt   <= 7'd0;
            rom_addr   <= 6'd0;
        end
        else begin
            x_in_valid <= 1'b1;

            // 到了更新输入的时刻
            if (hold_cnt == 7'd0) begin
                x_in <= wave_rom[rom_addr];

                // ROM 地址循环前进
                if (rom_addr == 6'd63)
                    rom_addr <= 6'd0;
                else
                    rom_addr <= rom_addr + 6'd1;

                // 从 1 开始继续计数，直到 127
                hold_cnt <= 7'd1;
            end
            else if (hold_cnt == 7'd127) begin
                // 计满 128 个周期后，下一拍回到 0，准备装下一个样本
                hold_cnt <= 7'd0;
            end
            else begin
                hold_cnt <= hold_cnt + 7'd1;
            end
        end
    end

    // ========================================================
    // 3) 统一 128x 插值链
    //
    // 这里不改任何核心算法模块，
    // 只是把现有的 interp128_top_ce 拿来直接用。
    //
    // 它会输出：
    // y_out      : 最终 128x 输出
    // dbg_y4     : 第一级 4x 输出
    // dbg_y8     : 第二级 8x 输出
    // dbg_y32/64 : 现在先不用来展示，但保留接线
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
        .clk           (clk),
        .rst_n         (rst_n),
        .ce4_out       (ce4_out),
        .ce8_out       (ce8_out),
        .ce16_out      (ce16_out),
        .ce32_out      (ce32_out),
        .ce64_out      (ce64_out),
        .ce128_out     (ce128_out),
        .x_in          (x_in),
        .x_in_valid    (x_in_valid),
        .y_out         (y_out_w),
        .y_out_valid   (y_out_valid_w),
        .dbg_y4        (dbg_y4_w),
        .dbg_y4_valid  (dbg_y4_valid_w),
        .dbg_y8        (dbg_y8_w),
        .dbg_y8_valid  (dbg_y8_valid_w),
        .dbg_y32       (dbg_y32_w),
        .dbg_y32_valid (dbg_y32_valid_w),
        .dbg_y64       (dbg_y64_w),
        .dbg_y64_valid (dbg_y64_valid_w)
    );

    // ========================================================
    // 4) 模式自动轮播
    //
    // mode_state 表示当前展示哪个倍率：
    // 01 = 4x
    // 10 = 8x
    // 11 = 128x
    //
    // mode_cnt 用来计时，每过 3 秒切一次模式。
    // ========================================================
    reg [1:0]  mode_state;
    reg [27:0] mode_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mode_state <= MODE_4X;
            mode_cnt   <= 28'd0;
        end
        else if (mode_cnt == MODE_HOLD_CYCLES - 1) begin
            mode_cnt <= 28'd0;

            case (mode_state)
                MODE_4X:   mode_state <= MODE_8X;
                MODE_8X:   mode_state <= MODE_128X;
                default:   mode_state <= MODE_4X;
            endcase
        end
        else begin
            mode_cnt <= mode_cnt + 28'd1;
        end
    end

    // LED 直接显示当前模式编码
    assign mode_led = mode_state;

    // ========================================================
    // 5) 节点选择 + 零阶保持
    //
    // selected_sample / selected_valid：
    // 根据当前模式，从 4x / 8x / 128x 三个节点里挑一路出来
    //
    // current_sample：
    // 只在 selected_valid = 1 时更新
    // 其余时间保持上一个值不变
    //
    // 这一步很重要，因为不同倍率节点不是每个系统时钟都有新数据。
    // 如果不保持，DAC 会看到很多“空周期”，波形就会不稳定。
    // ========================================================
    reg signed [23:0] selected_sample;
    reg               selected_valid;
    reg signed [23:0] current_sample;

    always @(*) begin
        case (mode_state)
            // 4x 模式：显示第一级 4x 输出
            MODE_4X: begin
                selected_sample = dbg_y4_w;
                selected_valid  = dbg_y4_valid_w;
            end

            // 8x 模式：显示第二级 8x 输出
            MODE_8X: begin
                selected_sample = dbg_y8_w;
                selected_valid  = dbg_y8_valid_w;
            end

            // 默认显示最终 128x 输出
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
    // 6) 24bit -> 8bit DAC 映射
    //
    // current_sample 是 signed 24bit。
    // 现在为了演示，直接取它的高 8 位，得到一个 signed 8bit。
    //
    // 然后给它加 128：
    // - 原来的负数会落到 0~127
    // - 原来的正数会落到 128~255
    //
    // 这样就变成了 DAC 常见的 unsigned 8bit 编码。
    //
    // 最后做一次饱和保护，避免超出 0~255。
    // ========================================================
    wire signed [7:0] sample_s8_w;
    wire signed [8:0] sample_bias_w;
    reg        [7:0]  dac_data_r;

    // 取 24bit 数据的高 8 位
    assign sample_s8_w = current_sample[23:16];

    // 扩成 9 位有符号数后加 128，便于后面判断是否越界
    assign sample_bias_w = $signed({sample_s8_w[7], sample_s8_w}) + 9'sd128;

    always @(*) begin
        if (sample_bias_w < 9'sd0)
            dac_data_r = 8'd0;
        else if (sample_bias_w > 9'sd255)
            dac_data_r = 8'hFF;
        else
            dac_data_r = sample_bias_w[7:0];
    end

    // DAC 时钟直接等于系统时钟
    assign dac_clk  = clk;
    assign dac_data = dac_data_r;

endmodule
