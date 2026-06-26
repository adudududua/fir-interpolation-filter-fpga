`timescale 1ns / 1ps
//=============================================================
// 文件名       : demo_interp_dac8_audio_pcm_common.v
// 模块名       : demo_interp_dac8_audio_pcm_common
// 功能简述     : 音频 PCM 输入版 FIR 插值 DAC 演示公共模块。
//                本模块使用 audio_pcm_rom_source 读取 24bit
//                signed 音频 PCM 采样点，并送入现有 128x
//                插值滤波器链路。
//                
//                与正弦 ROM 版本相比，本模块的区别是：
//                  原输入：内部 64 点正弦 ROM
//                  新输入：8192 点音频 PCM ROM
//
//                输出仍然通过 AD9708 并行 DAC 送到示波器，
//                用于验证真实音频采样经过 FIR 插值链后的
//                板级输出情况。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-06-20
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-06-21：新增音频 PCM 输入版本。
//=============================================================

module demo_interp_dac8_audio_pcm_common (
    input  wire        clk_audio_128x,  // 5.6448MHz 或 6.144MHz 连续音频 128x 时钟
    input  wire        rst_n,           // 低有效复位
    input  wire [1:0]  mode_sel,        // 插值倍率选择：00=4x，01=8x，10/11=128x

    output wire        dac_clk,         // 输出给 AD9708 的 DAC 采样时钟
    output wire [7:0]  dac_data,        // 输出给 AD9708 的 8bit 并行数据
    output wire [1:0]  mode_led         // 当前模式编码
);

    //=========================================================
    // 1）模式设置
    //
    // mode_sel:
    //   00 -> 4x 输出
    //   01 -> 8x 输出
    //   10 -> 128x 输出
    //   11 -> 128x 输出
    //=========================================================
    localparam [1:0] MODE_4X   = 2'b01;
    localparam [1:0] MODE_8X   = 2'b10;
    localparam [1:0] MODE_128X = 2'b11;

    reg [1:0] mode_state;

    always @(*) begin
        case (mode_sel)
            2'b00: begin
                mode_state = MODE_4X;
            end

            2'b01: begin
                mode_state = MODE_8X;
            end

            2'b10: begin
                mode_state = MODE_128X;
            end

            default: begin
                mode_state = MODE_128X;
            end
        endcase
    end

    assign mode_led = mode_state;

    //=========================================================
    // 2）在音频 128x 时钟域内产生整数 CE
    //
    // 若 clk_audio_128x = 6.144MHz：
    //   x_in_update_ce = 48kHz
    //   ce4_out        = 192kHz
    //   ce8_out        = 384kHz
    //   ce128_out      = 6.144MHz
    //
    // 若 clk_audio_128x = 5.6448MHz：
    //   x_in_update_ce = 44.1kHz
    //   ce4_out        = 176.4kHz
    //   ce8_out        = 352.8kHz
    //   ce128_out      = 5.6448MHz
    //=========================================================
    reg [6:0] ce_cnt;

    wire ce4_out;
    wire ce8_out;
    wire ce16_out;
    wire ce32_out;
    wire ce64_out;
    wire ce128_out;
    wire x_in_update_ce;

    assign ce128_out      = 1'b1;
    assign ce64_out       = (ce_cnt[0]   == 1'b0);
    assign ce32_out       = (ce_cnt[1:0] == 2'b00);
    assign ce16_out       = (ce_cnt[2:0] == 3'b000);
    assign ce8_out        = (ce_cnt[3:0] == 4'b0000);
    assign ce4_out        = (ce_cnt[4:0] == 5'b00000);
    assign x_in_update_ce = (ce_cnt == 7'd127);

    always @(posedge clk_audio_128x or negedge rst_n) begin
        if (!rst_n)
            ce_cnt <= 7'd0;
        else
            ce_cnt <= ce_cnt + 7'd1;
    end

    //=========================================================
    // 3）音频 PCM ROM 输入源
    //
    // audio_pcm_rom_source:
    //   从 audio_48k_24bit_8192.mem 中读取 24bit signed
    //   PCM 音频采样点。
    //
    // 注意：
    //   这个 .mem 文件本身是 48kHz 生成的测试数据。
    //   当 sw2=1 时，按照 48kHz 正常速度播放；
    //   当 sw2=0 时，按照 44.1kHz 速度播放，会稍微变慢。
    //
    //   这不影响我们用示波器验证“真实音频采样可以进入
    //   FIR 插值链并输出”。
    //=========================================================
    wire signed [23:0] audio_sample_w;
    wire               audio_sample_update_w;
    wire [9:0] audio_sample_addr_dbg_w;

    audio_pcm_rom_source #(
        .DATA_W   (24),
        .ADDR_W   (10),
        .DEPTH    (1024),
        .MEM_FILE ("audio_48k_24bit_1024.mem")
    ) u_audio_pcm_rom_source (
        .clk             (clk_audio_128x),
        .rst_n           (rst_n),
        .sample_ce       (x_in_update_ce),

        .sample_out      (audio_sample_w),
        .sample_update   (audio_sample_update_w),
        .sample_addr_dbg (audio_sample_addr_dbg_w)
    );

    //=========================================================
    // 4）送入插值链的输入样本
    //
    // 为了保持和原正弦 ROM 版本一致：
    //   x_in_valid 在复位释放后保持为 1。
    //
    // audio_sample_w 只会在 x_in_update_ce 节拍更新。
    // 插值链看到的是一个 44.1kHz/48kHz 更新的 24bit
    // signed 音频采样序列。
    //=========================================================
    wire signed [23:0] x_in;
    reg                x_in_valid;

    assign x_in = audio_sample_w;

    always @(posedge clk_audio_128x or negedge rst_n) begin
        if (!rst_n)
            x_in_valid <= 1'b0;
        else
            x_in_valid <= 1'b1;
    end

    //=========================================================
    // 5）实例化 128x 统一插值链
    //
    // 插值链内部结构：
    //   第一级：4x 插值 FIR
    //   后五级：2x 插值 FIR 级联
    //
    // 输出节点：
    //   dbg_y4 ：4x 输出
    //   dbg_y8 ：8x 输出
    //   y_out  ：128x 输出
    //=========================================================
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
        // .ACC_W    (56),
        .ACC_W    (49), // 24bit 输入 + 18bit 系数 + 3bit 进位 + 1bit 符号 = 46bit，向上取整为 45bit
        .NTAPS4X  (155),
        .NTAPS2X  (29)
    ) u_interp128_top_ce (
        .clk            (clk_audio_128x),
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

    //=========================================================
    // 6）选择当前需要送到 DAC 的插值节点
    //
    // mode_state = MODE_4X:
    //   DAC 输出 dbg_y4。
    //
    // mode_state = MODE_8X:
    //   DAC 输出 dbg_y8。
    //
    // mode_state = MODE_128X:
    //   DAC 输出 y_out。
    //=========================================================
    reg signed [23:0] selected_sample;
    reg               selected_valid;

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

    //=========================================================
    // 7）按模式做 DAC 显示幅度补偿
    //
    // 补偿只用于 AD9708 示波器显示，不改变 FIR 内部算法。
    //
    // 当前补偿：
    //   4x   ：不补偿
    //   8x   ：左移 1 位
    //   128x ：左移 4 位
    //
    // 如果示波器上 128x 音频波形幅度太小，可以改成 <<< 5。
    // 如果削顶明显，则保持 <<< 4 或进一步减小。
    //=========================================================
    reg  signed [31:0] display_sample_ext;
    reg  signed [23:0] display_sample_sat;

    wire signed [7:0] sample_s8_w;
    wire signed [8:0] sample_bias_w;
    reg        [7:0]  sample_u8_w;

    // always @(*) begin
    //     case (mode_state)
    //         MODE_4X: begin
    //             display_sample_ext = {{8{selected_sample[23]}}, selected_sample};
    //         end

    //         MODE_8X: begin
    //             display_sample_ext = ({{8{selected_sample[23]}}, selected_sample} <<< 1);
    //         end

    //         default: begin
    //             display_sample_ext = ({{8{selected_sample[23]}}, selected_sample} <<< 4);
    //         end
    //     endcase
    // end
    always @(*) begin
        case (mode_state)
            MODE_4X: begin
                display_sample_ext = {{8{selected_sample[23]}}, selected_sample};
            end

            MODE_8X: begin
                // polyphase_mac2_v2b 测试：先不做显示放大，避免削顶成方波
                display_sample_ext = {{8{selected_sample[23]}}, selected_sample};
            end

            default: begin
                // 128x DAC 显示补偿：5 级 2x FIR 每级幅度约减半，
                // 这里临时左移 3 位做显示放大，只影响 DAC 显示。
                display_sample_ext = ({{8{selected_sample[23]}}, selected_sample} <<< 4);
            end
        endcase
    end

    always @(*) begin
        if (display_sample_ext > 32'sd8388607)
            display_sample_sat = 24'sd8388607;
        else if (display_sample_ext < -32'sd8388608)
            display_sample_sat = -24'sd8388608;
        else
            display_sample_sat = display_sample_ext[23:0];
    end

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

    //=========================================================
    // 8）输出到 8bit 并行 DAC
    //
    // dac_data_r:
    //   在 clk_audio_128x 下降沿更新。
    //
    // 原因：
    //   dac_clk 上升沿给 AD9708 采样；
    //   数据在下降沿提前更新，可以给 DAC 留出建立时间。
    //=========================================================
    reg [7:0] dac_data_r;

    always @(negedge clk_audio_128x or negedge rst_n) begin
        if (!rst_n)
            dac_data_r <= 8'd128;
        else if (selected_valid)
            dac_data_r <= sample_u8_w;
    end

    assign dac_data = dac_data_r;

    assign dac_clk = (mode_state == MODE_4X) ? ce_cnt[4] :
                     (mode_state == MODE_8X) ? ce_cnt[3] :
                                                clk_audio_128x;

endmodule