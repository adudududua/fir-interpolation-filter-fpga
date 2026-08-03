`timescale 1ns / 1ps
//=============================================================
// 文件名       : demo_interp_dac8_audio_pcm_common.v
// 模块名       : demo_interp_dac8_audio_pcm_common
// 功能简述     : 音频 PCM 输入版 FIR 插值 DAC 演示公共模块。
//                本模块使用 audio_pcm_rom_source 读取 24bit
//                signed 音频 PCM 采样点，并送入 44.1kHz 专用
//                Phase 7 N=3 折叠补偿 FIR-CIC 128x 插值链路。
//                
//                当前输入为 147 点、15kHz、24bit 单正弦 ROM，
//                专门用于示波器比较四档阶梯粗糙度。
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
//                2026-07-10：替换为 7 级全 2x 插值链路，新增
//                            ce2_out，并去掉旧链路显示增益补偿。
//                2026-07-11：板级链路切换为 V2 Phase 2 true-polyphase
//                            与 valid-only 轻量桥接结构。
//                2026-07-12：板级链路切换为 V3 Stage 1 严格半带
//                            BRAM 循环缓冲结构，其余级保持 V2 优化结构。
//                2026-07-12：测试输入改为 15kHz 单正弦，并增加
//                            未经过插值链的 1x DAC 旁路档位。
//                2026-07-13：板级链路切换为 Phase 6 混合数据字长
//                            24/22/20/18/18/18/18bit 结构。
//                2026-07-13：增加 Phase 7 N=3 折叠补偿 FIR-CIC
//                            分支，并保留 Phase 6 常量回退路径。
//                2026-07-14：模式请求仅在候选 DAC 时钟公共低电平
//                            窗口提交，消除运行中切档窄脉冲。
//                2026-07-18：增加 Stage 2/3 单读 LUTRAM 候选参数；
//                            默认关闭，不改变稳定板级版本。
//                2026-07-18：增加 CIC burst 计数器 DSP/LUT 选择参数。
//                2026-07-18：增加 Stage2/3 交叉系数 BRAM 打包参数。
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
    parameter integer USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE = 2
)(
    input  wire        force_mute,
    input  wire        clk_audio_128x,  // 5.6448MHz 连续音频 128x 时钟
    input  wire        rst_n,           // 低有效复位
    input  wire        family_48k,      // 0=44.1kHz，1=48kHz
    input  wire [1:0]  mode_sel,        // 00=1x，01=4x，10=8x，11=128x

    output wire        dac_clk,         // 输出给 AD9708 的 DAC 采样时钟
    output wire [7:0]  dac_data,        // 输出给 AD9708 的 8bit 并行数据
    output wire [1:0]  mode_led         // 当前模式编码
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

    always @(posedge clk_audio_128x) begin
        if (!rst_n)
            ce_cnt <= 7'd0;
        else
            ce_cnt <= ce_cnt + 7'd1;
    end

    // 只在所有候选 DAC 时钟均为低电平时切换时钟源。
    // 这样 mode_sel 即使在任意基准时钟上升沿更新，也不会让
    // 组合时钟选择器产生零宽或不足半个基准周期的脉冲。
    always @(negedge clk_audio_128x) begin
        if (!rst_n)
            mode_state <= MODE_128X;
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
    reg                x_in_valid;

    assign x_in = audio_sample_w;

    always @(posedge clk_audio_128x) begin
        if (!rst_n)
            x_in_valid <= 1'b0;
        else
            x_in_valid <= 1'b1;
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
    // The AD9708 only consumes bits [23:16]. Select those eight bits before
    // the mode mux instead of building a 24-bit four-way mux and truncating
    // it afterwards. Every source is already signed 24-bit, so the former
    // 32-bit sign-extension/saturation stage could never clip. Likewise,
    // signed8 + 128 is always in 0..255 and needs no second saturation.
    reg signed [7:0] selected_sample_s8;
    reg              selected_valid;

    always @(*) begin
        case (mode_state)
            MODE_1X: begin
                selected_sample_s8 = audio_sample_w[23:16];
                selected_valid  = audio_sample_update_w;
            end

            MODE_4X: begin
                selected_sample_s8 = dbg_y4_w[23:16];
                selected_valid  = dbg_y4_valid_w;
            end

            MODE_8X: begin
                selected_sample_s8 = dbg_y8_w[23:16];
                selected_valid  = dbg_y8_valid_w;
            end

            default: begin
                selected_sample_s8 = y_out_w[23:16];
                selected_valid  = y_out_valid_w;
            end
        endcase
    end

    //=========================================================
    // 7）DAC 显示幅度处理
    //
    // 全 2x 各级系数已经包含 2 倍插值增益，1x、4x、8x、128x
    // 四个节点均保持输入幅度，因此不再做额外左移补偿。
    //=========================================================
    // Two's-complement signed8 to offset-binary unsigned8 is exactly a sign
    // bit inversion; no adder or comparator is required.
    wire [7:0] sample_u8_w = {
        ~selected_sample_s8[7], selected_sample_s8[6:0]};

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
        else if (force_mute || (mode_state != mode_request))
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
            // SAME_EDGE captures both values on the 128x rising edge. Low-rate
            // modes repeat the next divider value across both half cycles;
            // 128x mode emits the canonical 1/0 forwarded-clock pattern.
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
