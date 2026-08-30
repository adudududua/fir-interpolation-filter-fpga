`timescale 1ns / 1ps

//=============================================================
// 文件名       : demo_interp_dac8_audio_pcm_common.v
// 模块名       : demo_interp_dac8_audio_pcm_common
// 功能简述     : 板级音频数据通路公共模块。完成 ROM/UDP 上传源选择、44.1/48 kHz 家族复位切换、1x/4x/8x/128x 节点选择、24 位监测索引生成以及 AD9708 前的定点截位。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
module demo_interp_dac8_audio_pcm_common #(
    parameter integer USE_PHASE7_FOLDED = 1,
    parameter integer USE_PHASE7_LUTRAM_STAGE23 = 0,
    parameter integer USE_PHASE7_BRAM_STAGE23_HISTORY = 0,
    parameter integer USE_PHASE7_UNIFIED_BRAM_STAGE23_HISTORY = 0,
    parameter integer USE_NATIONAL_FINALS_SINGLE_BRAM_STAGE1 = 0,
    parameter integer USE_PHASE7_BRAM_STAGE23_COEFF = 0,
    parameter integer USE_PHASE8_PACKED_BRAM_STAGE23 = 0,
    parameter integer USE_PHASE7_CIC_BURST_COUNTER_DSP = 0,
    parameter integer USE_NATIONAL_FINALS_DATAPATH = 0,
    parameter integer USE_NATIONAL_FINALS_SERIAL_CIC_COMB = 0,
    parameter integer USE_NATIONAL_FINALS_N3_HOLD_EQUIV = 0,
    parameter integer USE_NATIONAL_FINALS_CIC_COMB_DSP = 0,
    parameter integer USE_NATIONAL_FINALS_STAGE1_DSP48_PREADDER = 0,
    parameter integer USE_NATIONAL_FINALS_NARROW_STAGE23 = 0,
    parameter integer USE_NATIONAL_FINALS_P3_JOINT_STAGE3 = 0,
    parameter integer USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE = 2,
    parameter integer USE_NATIONAL_FINALS_STAGE2_DATA_W = 22
)(
    input  wire        force_mute,
    input  wire        clk_audio_128x,  // 5.6448MHz 连续音频 128x 时钟
    input  wire        rst_n,           // 低有效复位
    input  wire        family_48k,      // 0=44.1kHz，1=48kHz
    input  wire [1:0]  mode_sel,        // 00=1x，01=4x，10=8x，11=128x
    // 可选的 PC 上传 1x PCM 输入。外部播放器必须在
    // external_sample_update 有效时给出一个新的 24 位样本；未启用时
    // 保持原来的板载 15 kHz ROM 行为。
    input  wire        external_source_enable,
    input  wire signed [23:0] external_sample,
    input  wire        external_sample_update,
    output wire        input_sample_ce,

    output wire        dac_clk,         // 输出给 AD9708 的 DAC 采样时钟
    output wire [7:0]  dac_data,        // 输出给 AD9708 的 8bit 并行数据
    output wire [1:0]  mode_led,        // 当前模式编码
    // 在 DAC 截位之前选中的精确 24 位有符号数据节点。
    output wire signed [23:0] monitor_sample,
    output wire               monitor_valid,
    // 当前插值分支内从 0 开始的输出序号；从插值数据通路复位后
    // 持续计数，用于让板上抓取数据与 RTL 参考向量精确对齐。
    output wire [31:0]        monitor_sample_index
);

    //=========================================================
    // 1）模式设置
    //
    // mode_sel:
    //   00 -> 1x 原始 PCM 输出
    //   01 -> 4x 输出
    //   10 -> 8x 输出
    //   11 -> 128x 输出
    //=========================================================
    localparam [1:0] MODE_1X   = 2'b00;
    localparam [1:0] MODE_4X   = 2'b01;
    localparam [1:0] MODE_8X   = 2'b10;
    localparam [1:0] MODE_128X = 2'b11;

    reg [1:0] mode_request;
    reg [1:0] mode_state;

    always @(*) begin
        case (mode_sel)
            2'b00: begin
                mode_request = MODE_1X;
            end

            2'b01: begin
                mode_request = MODE_4X;
            end

            2'b10: begin
                mode_request = MODE_8X;
            end

            default: begin
                mode_request = MODE_128X;
            end
        endcase
    end

    assign mode_led = mode_state;

    //=========================================================
    // 2）在音频 128x 时钟域内产生整数 CE
    //
    // clk_audio_128x = 5.6448MHz：
    //   x_in_update_ce = 44.1kHz
    //   ce2_out        = 88.2kHz
    //   ce4_out        = 176.4kHz
    //   ce8_out        = 352.8kHz
    //   ce128_out      = 5.6448MHz
    //=========================================================
    reg [6:0] ce_cnt;

    wire ce2_out;
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
    assign ce2_out        = (ce_cnt[5:0] == 6'b000000);
    assign x_in_update_ce = (ce_cnt == 7'd127);
    assign input_sample_ce = x_in_update_ce;

    always @(posedge clk_audio_128x) begin
        if (!rst_n)
            ce_cnt <= 7'd0;
        else
            ce_cnt <= ce_cnt + 7'd1;
    end

    // 全国总决赛通路使用 ODDR，并在 force_mute 有效期间接收原子化的
    // audio_mode。模式在随后的下降沿提交，确保下一上升沿解除静音前
    // mode_state 已经稳定。旧版组合时钟复用器仍采用“所有分频时钟均为
    // 低电平时才切换”的规则。
    always @(negedge clk_audio_128x) begin
        if (!rst_n)
            mode_state <= MODE_128X;
        else if (USE_NATIONAL_FINALS_DATAPATH != 0)
            mode_state <= mode_request;
        else if (!ce_cnt[6] && !ce_cnt[4] && !ce_cnt[3])
            mode_state <= mode_request;
    end

    //=========================================================
    // 3）音频 PCM ROM 输入源
    //
    // audio_pcm_rom_source 从 demo_sine_15k_44k1_24bit_147.mem
    // 中读取 24bit signed、15kHz 单正弦采样点。该测试数据按
    // 44.1kHz 节拍播放，用于示波器比较四档阶梯粗糙度。
    //=========================================================
    wire signed [23:0] audio_sample_w;
    wire               audio_sample_update_w;
    wire [7:0] audio_sample_addr_dbg_w;

    generate
        if (USE_NATIONAL_FINALS_DATAPATH != 0) begin :
                gen_dual_rate_test_tone
            dual_rate_test_tone_rom_source #(
                .MEM_FILE("nf_sine_15k_dual_rate_packed32_256.mem")
            ) u_dual_rate_test_tone_rom_source (
                .clk(clk_audio_128x),
                .rst_n(rst_n),
                .sample_ce(x_in_update_ce),
                .family_48k(family_48k),
                .sample_out(audio_sample_w),
                .sample_update(audio_sample_update_w),
                .sample_addr_dbg(audio_sample_addr_dbg_w)
            );
        end
        else begin : gen_regional_test_tone
            audio_pcm_rom_source #(
                .DATA_W   (24),
                .ADDR_W   (8),
                .DEPTH    (147),
                .MEM_FILE ("demo_sine_15k_44k1_24bit_147.mem")
            ) u_audio_pcm_rom_source (
                .clk             (clk_audio_128x),
                .rst_n           (rst_n),
                .sample_ce       (x_in_update_ce),
                .sample_out      (audio_sample_w),
                .sample_update   (audio_sample_update_w),
                .sample_addr_dbg (audio_sample_addr_dbg_w)
            );
        end
    endgenerate

    //=========================================================
    // 4）送入插值链的输入样本
    //
    // 为了保持和原正弦 ROM 版本一致：
    //   x_in_valid 在复位释放后保持为 1。
    //
    // audio_sample_w 只会在 x_in_update_ce 节拍更新。
    // 插值链看到的是一个 44.1kHz 更新的 24bit
    // signed 音频采样序列。
    //=========================================================
    wire signed [23:0] x_in;
    reg                x_in_valid_legacy;
    wire               x_in_valid;
    wire signed [23:0] source_sample_w;
    wire               source_sample_update_w;

    assign source_sample_w = external_source_enable ?
                             external_sample : audio_sample_w;
    assign source_sample_update_w = external_source_enable ?
                                    external_sample_update :
                                    audio_sample_update_w;
    assign x_in = source_sample_w;
    // 全国总决赛通路会把 ROM 和所有下游历史端口同步清零。因此，无论
    // valid 晚一个时钟拉高还是固定为高，复位后的第一次 CE 都会接收相同
    // 的零样本。显式利用这一已签核的不变量，可让 Vivado 删除 Stage1 RAM
    // 前的 24 位输入清零复用器；区域赛回退通路仍保留旧版的一拍 valid 行为。
    assign x_in_valid = (USE_NATIONAL_FINALS_DATAPATH != 0) ?
                        1'b1 : x_in_valid_legacy;

    always @(posedge clk_audio_128x) begin
        if (!rst_n)
            x_in_valid_legacy <= 1'b0;
        else
            x_in_valid_legacy <= 1'b1;
    end

    //=========================================================
    // 5）实例化 44.1kHz 专用 128x 插值链
    //
    // 默认 Phase 7 结构：
    //   2x × 2x × 2x × CIC16 = 128x
    //   Stage 1 使用 BRAM 单 DSP，Stage 2/3 共用第 2 个 DSP；
    //   Stage3 11tap Q15 系数同时承担 CIC 通带补偿，CIC 为 N=3。
    // USE_PHASE7_FOLDED=0 时回退到 Phase 6 七级全 2x 结构。
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

    generate
        if (USE_PHASE7_FOLDED != 0) begin : gen_phase7_folded
            interp128_all2x_v7_folded_fir_cic_top_ce #(
                .STAGE1_ACC_W(
                    (USE_NATIONAL_FINALS_DATAPATH != 0) ? 41 : 42),
                .STAGE23_ACC_W   (38),
                .STAGE2_DATA_W(
                    USE_NATIONAL_FINALS_STAGE2_DATA_W),
                .CIC_ORDER       (3),
                .FINAL_PRUNE_LSB (0),
                .USE_LUTRAM_STAGE23(USE_PHASE7_LUTRAM_STAGE23),
                .STAGE3_FLAT(USE_NATIONAL_FINALS_DATAPATH),
                .USE_CIC3_SHIFTADD_COMPENSATOR(
                    USE_NATIONAL_FINALS_DATAPATH &&
                    !USE_NATIONAL_FINALS_P3_JOINT_STAGE3),
                .USE_BRAM_STAGE23_HISTORY(USE_PHASE7_BRAM_STAGE23_HISTORY),
                .USE_UNIFIED_BRAM_STAGE23_HISTORY(
                    USE_PHASE7_UNIFIED_BRAM_STAGE23_HISTORY),
                .USE_SINGLE_BRAM_STAGE1(
                    USE_NATIONAL_FINALS_SINGLE_BRAM_STAGE1),
                .USE_BRAM_STAGE23_COEFF(USE_PHASE7_BRAM_STAGE23_COEFF),
                .USE_PACKED_BRAM_STAGE23(USE_PHASE8_PACKED_BRAM_STAGE23),
                .CIC_BURST_COUNTER_USE_DSP(
                    USE_PHASE7_CIC_BURST_COUNTER_DSP),
                .CIC_COMB_USE_DSP(
                    USE_NATIONAL_FINALS_CIC_COMB_DSP),
                .USE_SERIAL_CIC_COMB(
                    USE_NATIONAL_FINALS_SERIAL_CIC_COMB),
                .USE_N3_HOLD_EQUIV(
                    USE_NATIONAL_FINALS_N3_HOLD_EQUIV),
                .USE_STAGE1_DSP48_PREADDER(
                    USE_NATIONAL_FINALS_STAGE1_DSP48_PREADDER),
                .USE_NATIONAL_FINALS_NARROW_STAGE23(
                    USE_NATIONAL_FINALS_NARROW_STAGE23),
                .USE_P3_JOINT_STAGE3(
                    USE_NATIONAL_FINALS_P3_JOINT_STAGE3),
                .ASSUME_ALIGNED_POW2_CE(
                    USE_NATIONAL_FINALS_DATAPATH &&
                    USE_PHASE7_UNIFIED_BRAM_STAGE23_HISTORY),
                .CIC_INTEGRATOR_DSP_MODE(
                    USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE),
                .USE_UNIFIED_FIR_COEFF_BRAM(
                    USE_NATIONAL_FINALS_DATAPATH)
            ) u_interp128_all2x_v7_folded_fir_cic_top_ce (
                .clk(clk_audio_128x), .rst_n(rst_n),
                .ce2_out(ce2_out), .ce4_out(ce4_out),
                .ce8_out(ce8_out), .ce16_out(ce16_out),
                .ce32_out(ce32_out), .ce64_out(ce64_out),
                .ce128_out(ce128_out),
                .x_in(x_in), .x_in_valid(x_in_valid),
                .stage3_compensated_mode(mode_state == MODE_128X),
                .y_out(y_out_w), .y_out_valid(y_out_valid_w),
                .dbg_y2(), .dbg_y2_valid(),
                .dbg_y4(dbg_y4_w), .dbg_y4_valid(dbg_y4_valid_w),
                .dbg_y8(dbg_y8_w), .dbg_y8_valid(dbg_y8_valid_w),
                .dbg_y16(), .dbg_y16_valid(),
                .dbg_y32(dbg_y32_w), .dbg_y32_valid(dbg_y32_valid_w),
                .dbg_y64(dbg_y64_w), .dbg_y64_valid(dbg_y64_valid_w)
            );
        end
        else begin : gen_phase6_fallback
            interp128_all2x_v6_mixed_width_top_ce #(
                .STAGE23_ACC_W (38)
            ) u_interp128_all2x_v6_mixed_width_top_ce (
                .clk(clk_audio_128x), .rst_n(rst_n),
                .ce2_out(ce2_out), .ce4_out(ce4_out),
                .ce8_out(ce8_out), .ce16_out(ce16_out),
                .ce32_out(ce32_out), .ce64_out(ce64_out),
                .ce128_out(ce128_out),
                .x_in(x_in), .x_in_valid(x_in_valid),
                .y_out(y_out_w), .y_out_valid(y_out_valid_w),
                .dbg_y2(), .dbg_y2_valid(),
                .dbg_y4(dbg_y4_w), .dbg_y4_valid(dbg_y4_valid_w),
                .dbg_y8(dbg_y8_w), .dbg_y8_valid(dbg_y8_valid_w),
                .dbg_y16(), .dbg_y16_valid(),
                .dbg_y32(dbg_y32_w), .dbg_y32_valid(dbg_y32_valid_w),
                .dbg_y64(dbg_y64_w), .dbg_y64_valid(dbg_y64_valid_w)
            );
        end
    endgenerate

    //=========================================================
    // 6）选择当前需要送到 DAC 的插值节点
    //
    // mode_state = MODE_1X:
    //   DAC 直接输出原始 44.1kHz PCM，不经过插值链。
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
    reg [31:0]        count_1x;
    reg [31:0]        count_4x;
    reg [31:0]        count_8x;
    reg [31:0]        count_128x;
    reg [31:0]        selected_sample_index;

    always @(posedge clk_audio_128x) begin
        if (!rst_n) begin
            count_1x   <= 32'd0;
            count_4x   <= 32'd0;
            count_8x   <= 32'd0;
            count_128x <= 32'd0;
        end else begin
            if (source_sample_update_w)
                count_1x <= count_1x + 32'd1;
            if (dbg_y4_valid_w)
                count_4x <= count_4x + 32'd1;
            if (dbg_y8_valid_w)
                count_8x <= count_8x + 32'd1;
            if (y_out_valid_w)
                count_128x <= count_128x + 32'd1;
        end
    end

    always @(*) begin
        case (mode_state)
            MODE_1X: begin
                selected_sample = source_sample_w;
                selected_valid  = source_sample_update_w;
                selected_sample_index = count_1x;
            end

            MODE_4X: begin
                selected_sample = dbg_y4_w;
                selected_valid  = dbg_y4_valid_w;
                selected_sample_index = count_4x;
            end

            MODE_8X: begin
                selected_sample = dbg_y8_w;
                selected_valid  = dbg_y8_valid_w;
                selected_sample_index = count_8x;
            end

            default: begin
                selected_sample = y_out_w;
                selected_valid  = y_out_valid_w;
                selected_sample_index = count_128x;
            end
        endcase
    end

    assign monitor_sample = selected_sample;
    assign monitor_valid  = selected_valid && !force_mute;
    assign monitor_sample_index = selected_sample_index;

    //=========================================================
    // 7）DAC 显示幅度处理
    //
    // 全 2x 各级系数已经包含 2 倍插值增益，1x、4x、8x、128x
    // 四个节点均保持输入幅度，因此不再做额外左移补偿。
    //=========================================================
    reg  signed [31:0] display_sample_ext;
    reg  signed [23:0] display_sample_sat;

    wire signed [7:0] sample_s8_w;
    wire signed [8:0] sample_bias_w;
    reg        [7:0]  sample_u8_w;

    always @(*) begin
        display_sample_ext = {{8{selected_sample[23]}}, selected_sample};
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
    (* IOB = "TRUE" *) reg [7:0] dac_data_r;

    always @(negedge clk_audio_128x) begin
        if (!rst_n)
            dac_data_r <= 8'd128;
        // ODDR 通路会在中间的下降沿提交原子模式，此时 force_mute 尚未解除。
        // 模式不一致判断只为旧版组合时钟复用器回退通路保留。
        else if (force_mute ||
                 ((USE_NATIONAL_FINALS_DATAPATH == 0) &&
                  (mode_state != mode_request)))
            dac_data_r <= 8'd128;
        else if (selected_valid)
            dac_data_r <= sample_u8_w;
    end

    assign dac_data = dac_data_r;

    wire [6:0] ce_cnt_next_w;
    wire       dac_clk_div_next_w;

    assign ce_cnt_next_w = ce_cnt + 7'd1;
    assign dac_clk_div_next_w =
        (mode_state == MODE_1X) ? ce_cnt_next_w[6] :
        (mode_state == MODE_4X) ? ce_cnt_next_w[4] :
        (mode_state == MODE_8X) ? ce_cnt_next_w[3] : 1'b0;

    generate
        if (USE_NATIONAL_FINALS_DATAPATH != 0) begin : gen_dac_clock_oddr
            // SAME_EDGE 会在 128x 上升沿同时锁存两个值。低速模式在两个
            // 半周期重复下一分频值；128x 模式输出标准的 1/0 转发时钟波形。
            ODDR #(
                .DDR_CLK_EDGE("SAME_EDGE"),
                .INIT(1'b0),
                .SRTYPE("SYNC")
            ) u_dac_clock_oddr (
                .Q(dac_clk),
                .C(clk_audio_128x),
                .CE(1'b1),
                .D1((mode_state == MODE_128X) ? 1'b1 :
                    dac_clk_div_next_w),
                .D2((mode_state == MODE_128X) ? 1'b0 :
                    dac_clk_div_next_w),
                .R(~rst_n),
                .S(1'b0)
            );
        end
        else begin : gen_legacy_dac_clock_mux
            assign dac_clk = (mode_state == MODE_1X) ? ce_cnt[6] :
                             (mode_state == MODE_4X) ? ce_cnt[4] :
                             (mode_state == MODE_8X) ? ce_cnt[3] :
                                                        clk_audio_128x;
        end
    endgenerate

endmodule
