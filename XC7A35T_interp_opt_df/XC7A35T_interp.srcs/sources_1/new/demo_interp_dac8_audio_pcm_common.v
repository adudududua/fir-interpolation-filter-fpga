`timescale 1ns / 1ps
//=============================================================
// 文件名       : demo_interp_dac8_audio_pcm_common.v
// 模块名       : demo_interp_dac8_audio_pcm_common
// 功能简述     : 可调正弦输入版 FIR 插值 DAC 演示公共模块。
//                本模块使用 audio_nco_sine_source 产生 24bit
//                signed 音频采样点，并送入 44.1kHz 专用
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
//                2026-07-18：输入源改为 1kHz～20kHz 可调正弦 NCO。
//                2026-07-19：保留原可调 NCO 与四档 DAC 功能，新增
//                            SW9 控制的 ILA 镜像抑制演示旁路。
//                2026-07-19：向 ILA 导出 1x～128x 各级采样更新脉冲，
//                            用于同步观察逐级采样率。
//=============================================================

module demo_interp_dac8_audio_pcm_common #(
    parameter integer USE_PHASE7_FOLDED = 1,
    parameter integer USE_PHASE7_LUTRAM_STAGE23 = 0,
    parameter integer USE_PHASE7_BRAM_STAGE23_HISTORY = 0,
    parameter integer USE_PHASE7_BRAM_STAGE23_COEFF = 0,
    parameter integer USE_PHASE8_PACKED_BRAM_STAGE23 = 0,
    parameter integer USE_PHASE7_CIC_BURST_COUNTER_DSP = 0
)(
    input  wire        clk_audio_128x,  // 5.6448MHz 连续音频 128x 时钟
    input  wire        rst_n,           // 低有效复位
    input  wire [1:0]  mode_sel,        // 00=1x，01=4x，10=8x，11=128x
    input  wire [4:0]  tone_khz,        // 输入正弦频率，单位 kHz（1～20）
    input  wire        ila_demo_enable, // 1=4.1kHz+15kHz ILA 演示输入

    output wire        dac_clk,         // 输出给 AD9708 的 DAC 采样时钟
    output wire [7:0]  dac_data,        // 输出给 AD9708 的 8bit 并行数据
    output wire [1:0]  mode_led,        // 当前模式编码

    output wire signed [23:0] ila_pre2_sample,
    output wire signed [23:0] ila_post2_sample,
    output wire signed [23:0] ila_final128_sample,
    output wire               ila_ce2_tick,
    output wire [15:0]        ila_magnitude_15k_pre,
    output wire [15:0]        ila_magnitude_15k_post,
    output wire [15:0]        ila_magnitude_40k_pre,
    output wire [15:0]        ila_magnitude_40k_post,
    output wire [7:0]         ila_suppression_40k_db,
    output wire               ila_measurement_valid,
    output wire [7:0]         ila_rate_tick
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

    always @(posedge clk_audio_128x or negedge rst_n) begin
        if (!rst_n)
            ce_cnt <= 7'd0;
        else
            ce_cnt <= ce_cnt + 7'd1;
    end

    // 只在所有候选 DAC 时钟均为低电平时切换时钟源。
    // 这样 mode_sel 即使在任意基准时钟上升沿更新，也不会让
    // 组合时钟选择器产生零宽或不足半个基准周期的脉冲。
    always @(negedge clk_audio_128x or negedge rst_n) begin
        if (!rst_n)
            mode_state <= MODE_128X;
        else if (!ce_cnt[6] && !ce_cnt[4] && !ce_cnt[3])
            mode_state <= mode_request;
    end

    //=========================================================
    // 3）可调正弦 NCO 输入源
    //
    // audio_nco_sine_source 按 44.1kHz 节拍输出 24bit signed、
    // 0.50FS 正弦采样点。tone_khz 可在 1kHz～20kHz 范围内调节，
    // 频率切换时相位保持连续，用于示波器比较四档阶梯粗糙度。
    //=========================================================
    wire signed [23:0] audio_sample_w;
    wire               audio_sample_update_w;
    wire [7:0] audio_sample_addr_dbg_w;
    wire signed [23:0] demo_sample_w;
    wire               demo_sample_update_w;
    wire [8:0]          demo_sample_index_dbg_w;

    audio_nco_sine_source #(
        .DATA_W   (24),
        .ADDR_W   (8),
        .MEM_FILE ("nco_sine_0p50fs_256.mem")
    ) u_audio_nco_sine_source (
        .clk             (clk_audio_128x),
        .rst_n           (rst_n),
        .sample_ce       (x_in_update_ce),
        .tone_khz        (tone_khz),

        .sample_out      (audio_sample_w),
        .sample_update   (audio_sample_update_w),
        .phase_addr_dbg  (audio_sample_addr_dbg_w)
    );

    ila_demo_multitone_source #(
        .DATA_W    (24),
        .ROM_DEPTH (441),
        .MEM_FILE  ("ila_demo_mix_4k1_15k_441.mem")
    ) u_ila_demo_multitone_source (
        .clk              (clk_audio_128x),
        .rst_n            (rst_n),
        .enable           (ila_demo_enable),
        .sample_ce        (x_in_update_ce),
        .sample_out       (demo_sample_w),
        .sample_update    (demo_sample_update_w),
        .sample_index_dbg (demo_sample_index_dbg_w)
    );

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
    wire               x_in_sample_update;
    reg                x_in_valid;

    assign x_in = ila_demo_enable ? demo_sample_w : audio_sample_w;
    assign x_in_sample_update = ila_demo_enable ?
                                demo_sample_update_w : audio_sample_update_w;

    always @(posedge clk_audio_128x or negedge rst_n) begin
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

    wire signed [23:0] dbg_y2_w;
    wire               dbg_y2_valid_w;
    wire signed [23:0] stage1_fir_in_w;
    wire               stage1_fir_in_valid_w;

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
                .STAGE23_ACC_W   (38),
                .CIC_ORDER       (3),
                .FINAL_PRUNE_LSB (0),
                .USE_LUTRAM_STAGE23(USE_PHASE7_LUTRAM_STAGE23),
                .USE_BRAM_STAGE23_HISTORY(USE_PHASE7_BRAM_STAGE23_HISTORY),
                .USE_BRAM_STAGE23_COEFF(USE_PHASE7_BRAM_STAGE23_COEFF),
                .USE_PACKED_BRAM_STAGE23(USE_PHASE8_PACKED_BRAM_STAGE23),
                .CIC_BURST_COUNTER_USE_DSP(
                    USE_PHASE7_CIC_BURST_COUNTER_DSP)
            ) u_interp128_all2x_v7_folded_fir_cic_top_ce (
                .clk(clk_audio_128x), .rst_n(rst_n),
                .ce2_out(ce2_out), .ce4_out(ce4_out),
                .ce8_out(ce8_out), .ce16_out(ce16_out),
                .ce32_out(ce32_out), .ce64_out(ce64_out),
                .ce128_out(ce128_out),
                .x_in(x_in), .x_in_valid(x_in_valid),
                .y_out(y_out_w), .y_out_valid(y_out_valid_w),
                .dbg_y2(dbg_y2_w), .dbg_y2_valid(dbg_y2_valid_w),
                .dbg_y4(dbg_y4_w), .dbg_y4_valid(dbg_y4_valid_w),
                .dbg_y8(dbg_y8_w), .dbg_y8_valid(dbg_y8_valid_w),
                .dbg_y16(), .dbg_y16_valid(),
                .dbg_y32(dbg_y32_w), .dbg_y32_valid(dbg_y32_valid_w),
                .dbg_y64(dbg_y64_w), .dbg_y64_valid(dbg_y64_valid_w),
                .dbg_stage1_fir_in(stage1_fir_in_w),
                .dbg_stage1_fir_in_valid(stage1_fir_in_valid_w)
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

            assign dbg_y2_w = 24'sd0;
            assign dbg_y2_valid_w = 1'b0;
            assign stage1_fir_in_w = 24'sd0;
            assign stage1_fir_in_valid_w = 1'b0;
        end
    endgenerate

    //=========================================================
    // 6）ILA 第一级插值前后波形与固定频点测量
    //
    // fir_in_valid=0 的 2x 相位显式补零，形成真实的零插值序列；
    // y2_valid 后的样点是同一 88.2kHz 节拍上的第一级 FIR 输出。
    // 两路都锁存保持，便于 5.6448MHz ILA 采用同一横轴观察。
    //=========================================================
    reg signed [23:0] ila_pre2_hold;
    reg signed [23:0] ila_post2_hold;
    wire              monitor_result_strobe_unused;

    always @(posedge clk_audio_128x or negedge rst_n) begin
        if (!rst_n) begin
            ila_pre2_hold  <= 24'sd0;
            ila_post2_hold <= 24'sd0;
        end
        else begin
            if (ce2_out)
                ila_pre2_hold <= stage1_fir_in_valid_w ?
                                 stage1_fir_in_w : 24'sd0;
            if (dbg_y2_valid_w)
                ila_post2_hold <= dbg_y2_w;
        end
    end

    ila_image_rejection_monitor #(
        .WARMUP_SAMPLES (2048),
        .BLOCK_SAMPLES  (882),
        .REF_DEPTH      (441),
        .REF_MEM_FILE   ("ila_demo_refs_15k_40k_441.mem")
    ) u_ila_image_rejection_monitor (
        .clk                 (clk_audio_128x),
        .rst_n               (rst_n),
        .enable              (ila_demo_enable),
        .sample_ce           (dbg_y2_valid_w),
        .sample_pre          (ila_pre2_hold),
        .sample_post         (dbg_y2_w),
        .magnitude_15k_pre   (ila_magnitude_15k_pre),
        .magnitude_15k_post  (ila_magnitude_15k_post),
        .magnitude_40k_pre   (ila_magnitude_40k_pre),
        .magnitude_40k_post  (ila_magnitude_40k_post),
        .suppression_40k_db  (ila_suppression_40k_db),
        .measurement_valid   (ila_measurement_valid),
        .result_strobe       (monitor_result_strobe_unused)
    );

    assign ila_pre2_sample     = ila_pre2_hold;
    assign ila_post2_sample    = ila_post2_hold;
    assign ila_final128_sample = y_out_w;
    assign ila_ce2_tick        = ce2_out;

    // bit0～bit7 依次对应 1x、2x、4x、8x、16x、32x、64x、128x。
    // 这些信号是统一 5.6448MHz 时钟域内的采样更新使能，不是门控时钟。
    assign ila_rate_tick = {ce128_out, ce64_out, ce32_out, ce16_out,
                            ce8_out, ce4_out, ce2_out, x_in_update_ce};

    //=========================================================
    // 7）选择当前需要送到 DAC 的插值节点
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

    always @(*) begin
        case (mode_state)
            MODE_1X: begin
                selected_sample = x_in;
                selected_valid  = x_in_sample_update;
            end

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
    // 8）DAC 显示幅度处理
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
    // 9）输出到 8bit 并行 DAC
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

    assign dac_clk = (mode_state == MODE_1X) ? ce_cnt[6] :
                     (mode_state == MODE_4X) ? ce_cnt[4] :
                     (mode_state == MODE_8X) ? ce_cnt[3] :
                                                clk_audio_128x;

endmodule
