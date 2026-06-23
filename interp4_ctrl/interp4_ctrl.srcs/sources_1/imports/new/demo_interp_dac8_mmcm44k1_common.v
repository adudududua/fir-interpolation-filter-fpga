`timescale 1ns / 1ps
//=============================================================
// 文件名       : demo_interp_dac8_mmcm44k1_common.v
// 模块名       : demo_interp_dac8_mmcm44k1_common
// 功能简述     : 44.1kHz 家族 MMCM 正式采样率 DAC 演示公共模块。
//                本模块使用 6.144MHz 连续音频时钟作为 128x
//                工作时钟，在该时钟域内用整数计数方式产生
//                4x、8x、16x、32x、64x、128x 插值节拍，
//                并将选中的插值节点输出到 8bit 并行 DAC。
//
// 设计作者     :kafeizizi 
// 创建日期     : 2026-05-17
// 版本         : V2018.3 
// 开发工具     : Vivado
// 修订记录     :
// 其他描述     :
//=============================================================

module demo_interp_dac8_mmcm44k1_common (
    input  wire        clk_audio_128x,  // MMCM 输出的 6.144MHz 连续音频时钟
    input  wire        rst_n,           // 低有效复位，建议由 rst_n 和 mmcm_locked 共同产生
    input  wire [1:0]  mode_sel,        // 插值倍率选择：00=4x，01=8x，10/11=128x

    output wire        dac_clk,         // 输出给 DA9708 的 DAC 采样时钟
    output wire [7:0]  dac_data,        // 输出给 DA9708 的 8bit 并行数据
    output wire [1:0]  mode_led         // 当前模式编码
);
    //=========================================================
    // 1）模式和演示参数设置
    //
    // 本模块是 48kHz 家族 MMCM 专用版本。
    //
    // clk_audio_128x：
    //   外部 MMCM 已经产生 5.6448MHz 连续音频时钟。
    //   因此本模块内部不再选择 44.1kHz / 48kHz，
    //   也不再使用分数 CE 发生器。
    //
    // MODE_4X：
    //   输出 4x 节点 dbg_y4。
    //   对应输出采样率约 176.4kHz。
    //
    // MODE_8X：
    //   输出 8x 节点 dbg_y8。
    //   对应输出采样率约 352.8kHz。
    //
    // MODE_128X：
    //   输出最终 128x 节点 y_out。
    //   对应输出采样率约 5.6448MHz。
    //
    // ROM_ADDR_STEP：
    //   每次输入采样更新时，正弦 ROM 地址前进的步长。
    //   当前为 12。
    //   在 44.1kHz 输入采样率下，测试正弦频率约为：
    //     44.1kHz * 12 / 64 = 8.26875kHz
    //
    // mode_sel：
    //   来自顶层拨码开关。
    //   00 -> 4x
    //   01 -> 8x
    //   10 -> 128x
    //   11 -> 128x
    //=========================================================
    localparam [1:0] MODE_4X   = 2'b01;
    localparam [1:0] MODE_8X   = 2'b10;
    localparam [1:0] MODE_128X = 2'b11;

    localparam [5:0] ROM_ADDR_STEP = 6'd12;

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
    // 2）在 6.144MHz 音频时钟域内产生整数 CE
    //
    // 原来的 audio_rate_ce_gen 是给 50MHz 系统时钟用的。
    // 它通过分数相位累加器产生 6.144MHz 平均采样节拍。
    //
    // 现在这个 MMCM44.1kHz 版本不同：
    //   clk_audio_128x 已经是 6.144MHz 连续时钟。
    //
    // 所以这里不再需要分数 CE。
    // 只需要用一个 7bit 计数器，在 6.144MHz 时钟域内
    // 按整数关系产生各级插值节拍。
    //
    // ce128_out：
    //   每一拍都有效，对应 6.144MHz。
    //
    // ce64_out：
    //   每 2 拍有效一次，对应 3.072MHz。
    //
    // ce32_out：
    //   每 4 拍有效一次，对应 1.536MHz。
    //
    // ce16_out：
    //   每 8 拍有效一次，对应 768kHz。
    //
    // ce8_out：
    //   每 16 拍有效一次，对应 384kHz。
    //
    // ce4_out：
    //   每 32 拍有效一次，对应 192kHz。
    //
    // x_in_update_ce：
    //   每 128 拍有效一次，对应 48kHz 输入采样率。
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
    // 3）板内 24bit 正弦输入源
    //
    // wave_rom：
    //   64 点 signed 24bit 正弦查找表。
    //
    // x_in：
    //   送入 interp128_top_ce 的原始输入样本。
    //
    // 更新节拍：
    //   x_in 只在 x_in_update_ce 有效时更新。
    //   在 48kHz 家族下，x_in_update_ce 平均频率为 48kHz。
    //
    // 地址步进：
    //   每次更新输入样本时，rom_addr 加 ROM_ADDR_STEP。
    //   因为 rom_addr 是 6bit，超过 63 会自然回绕到 0。
    //=========================================================
    reg signed [23:0] x_in;
    reg               x_in_valid;
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

    always @(posedge clk_audio_128x or negedge rst_n) begin
        if (!rst_n) begin
            x_in       <= 24'sd0;
            x_in_valid <= 1'b0;
            rom_addr   <= 6'd0;
        end
        else begin
            x_in_valid <= 1'b1;

            if (x_in_update_ce) begin
                x_in     <= wave_rom[rom_addr];
                rom_addr <= rom_addr + ROM_ADDR_STEP;
            end
        end
    end

    //=========================================================
    // 4）实例化 128x 统一插值链
    //
    // interp128_top_ce 内部结构：
    //   第一级：4x 插值 FIR
    //   后五级：2x 插值 FIR 级联
    //
    // 输出节点：
    //   dbg_y4  ：4x 输出
    //   dbg_y8  ：8x 输出
    //   y_out   ：128x 输出
    //
    // 本模块只负责提供正式采样率 CE 和输入样本，
    // 不修改 interp128_top_ce 内部算法。
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
        .ACC_W    (56),
        .NTAPS4X  (155),
        .NTAPS2X  (11)
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
    // 5）选择当前需要送到 DAC 的插值节点
    //
    // mode_state = MODE_4X：
    //   DAC 输出 dbg_y4。
    //
    // mode_state = MODE_8X：
    //   DAC 输出 dbg_y8。
    //
    // mode_state = MODE_128X：
    //   DAC 输出 y_out。
    //
    // selected_valid 表示当前 selected_sample 是新样本。
    // 后面 DAC 只在 selected_valid 有效时更新数据。
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
    // 6）按模式做 DAC 显示幅度补偿
    //
    // 这里的补偿只用于板级 DAC 显示，
    // 不改变插值链内部算法。
    //
    // 补偿原因：
    //   不同插值节点经过的 2x 后级数量不同，
    //   直接取高 8 位时，示波器上显示幅度可能差异较大。
    //
    // 当前补偿关系：
    //   4x   ：不补偿
    //   8x   ：左移 1 位，约等于乘 2
    //   128x ：左移 5 位，约等于乘 32
    //=========================================================
    reg  signed [31:0] display_sample_ext;
    reg  signed [23:0] display_sample_sat;

    wire signed [7:0] sample_s8_w;
    wire signed [8:0] sample_bias_w;
    reg        [7:0]  sample_u8_w;

    always @(*) begin
        case (mode_state)
            MODE_4X: begin
                display_sample_ext = {{8{selected_sample[23]}}, selected_sample};
            end

            MODE_8X: begin
                display_sample_ext = ({{8{selected_sample[23]}}, selected_sample} <<< 1);
            end

            default: begin
                display_sample_ext = ({{8{selected_sample[23]}}, selected_sample} <<< 5);
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
    // 7）输出到 8bit 并行 DAC
    //
    // dac_data_r：
    //   在 clk_audio_128x 的下降沿更新。
    //
    // 这样做的目的：
    //   dac_clk 的上升沿用于 DA9708 采样。
    //   数据在下降沿先更新，到了下一个上升沿时已经稳定。
    //
    // dac_clk：
    //   4x 模式输出约 192kHz 连续方波。
    //   8x 模式输出约 384kHz 连续方波。
    //   128x 模式输出约 6.144MHz 连续方波。
    //=========================================================
    reg [7:0] dac_data_r;

    always @(negedge clk_audio_128x or negedge rst_n) begin
        if (!rst_n)
            dac_data_r <= 8'd128;
        else if (selected_valid)
            dac_data_r <= sample_u8_w;
    end

    assign dac_data = dac_data_r;

    assign dac_clk = (mode_state == MODE_4X)   ? ce_cnt[4] :
                     (mode_state == MODE_8X)   ? ce_cnt[3] :
                                                  clk_audio_128x;


endmodule
