`default_nettype none
`timescale 1ns / 1ps
//=============================================================
// 文件名       : interp4_top_symm_ce.v
// 模块名       : interp4_top_symm_ce
// 功能简述     : 4x 前级插值 FIR 的 polyphase + 2-lane MAC 实验版 v2b。
//
// 重要说明：
//   这个文件用于替换原 interp4_top_symm_ce.v。
//   模块名和端口保持不变，因此 interp128_top_ce.v 不需要修改。
//
// 设计动机：
//   v1 版本采用 39 个并行乘法器：
//     - 禁用 DSP 时：DSP=0，但 LUT 偏高；
//     - 放开 DSP 时：LUT 很低，但 DSP=39。
//   因此 v2 改为 2-lane 时分复用 MAC：
//     - 每个 4x 输出周期之间有 32 个 clk_audio_128x 时钟周期；
//     - 每相 polyphase 大约 39 tap；
//     - 每拍计算 2 个 tap，约 20 拍完成一次 4x 输出计算；
//     - 目标是用少量 DSP 换取明显 LUT 降低。
//
// polyphase 公式：
//   y[4n+p] = sum_j h[p+4j] * x[n-j], p=0,1,2,3
//
// 当前版本特点：
//   1. 保持 4x / 8x / 128x 实时切换功能不变；
//   2. 保持原 155 tap Q16 系数不变；
//   3. 保持模块接口不变；
//   4. 使用 2 个乘法通道时分复用，预期 DSP 数约为 2；
//   5. 输出相对原并行结构会增加若干拍固定延迟，但 valid 会同步给出，
//      对后级插值链和 DAC 显示不应产生功能性影响。
//
// 设计作者     : kafeizizi
// 修改建议     : ChatGPT
// 日期         : 2026-06-25
//=============================================================

// v2b：不在整个模块级强制 use_dsp，避免加法器/累加器也映射到 DSP。
module interp4_top_symm_ce #(
    parameter DATA_W  = 24,
    parameter COEFF_W = 18,
    parameter ACC_W   = 49,
    parameter NTAPS   = 155
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         ce_out,

    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,

    output wire signed [23:0]           y_out,
    output wire                         y_out_valid,

    output wire [1:0]                   phase_dbg,
    output wire signed [23:0]           fir_in_dbg,
    output wire                         fir_in_valid_dbg
);

    //=========================================================
    // 1）基本参数
    //=========================================================
    localparam integer PHASE_TAPS = 39;              // ceil(155/4)
    localparam integer PROD_W     = DATA_W + COEFF_W;
    localparam integer PAIR_W     = PROD_W + 1;

    //=========================================================
    // 2）原始采样率延时线
    //
    // x_delay[0] 是最新 1x 原始样本。
    // phase=0 且 ce_out 到来时，写入新的 x_in。
    //=========================================================
    reg signed [DATA_W-1:0] x_delay [0:PHASE_TAPS-1];

    // 当前准备启动的相位
    reg [1:0] phase_cnt;

    integer i;

    //=========================================================
    // 3）4 相 polyphase 系数查找函数
    //
    // coeff_lookup(phase, tap_idx) = h[phase + 4*tap_idx]
    //=========================================================
    function signed [COEFF_W-1:0] coeff_lookup;
        input [1:0] phase;
        input [5:0] tap_idx;
        begin
            case (phase)
            2'd0: begin
                case (tap_idx)
                     0: coeff_lookup =  18'sd13;
                     1: coeff_lookup = -18'sd8;
                     2: coeff_lookup = -18'sd7;
                     3: coeff_lookup =  18'sd1;
                     4: coeff_lookup = -18'sd14;
                     5: coeff_lookup =  18'sd19;
                     6: coeff_lookup = -18'sd35;
                     7: coeff_lookup =  18'sd51;
                     8: coeff_lookup = -18'sd76;
                     9: coeff_lookup =  18'sd106;
                    10: coeff_lookup = -18'sd147;
                    11: coeff_lookup =  18'sd199;
                    12: coeff_lookup = -18'sd268;
                    13: coeff_lookup =  18'sd359;
                    14: coeff_lookup = -18'sd483;
                    15: coeff_lookup =  18'sd664;
                    16: coeff_lookup = -18'sd948;
                    17: coeff_lookup =  18'sd1473;
                    18: coeff_lookup = -18'sd2806;
                    19: coeff_lookup =  18'sd14631;
                    20: coeff_lookup =  18'sd5012;
                    21: coeff_lookup = -18'sd2176;
                    22: coeff_lookup =  18'sd1382;
                    23: coeff_lookup = -18'sd998;
                    24: coeff_lookup =  18'sd764;
                    25: coeff_lookup = -18'sd604;
                    26: coeff_lookup =  18'sd484;
                    27: coeff_lookup = -18'sd391;
                    28: coeff_lookup =  18'sd316;
                    29: coeff_lookup = -18'sd255;
                    30: coeff_lookup =  18'sd203;
                    31: coeff_lookup = -18'sd161;
                    32: coeff_lookup =  18'sd124;
                    33: coeff_lookup = -18'sd97;
                    34: coeff_lookup =  18'sd69;
                    35: coeff_lookup = -18'sd55;
                    36: coeff_lookup =  18'sd32;
                    37: coeff_lookup = -18'sd32;
                    38: coeff_lookup =  18'sd16;
                    default: coeff_lookup = 18'sd0;
                endcase
            end
            2'd1: begin
                case (tap_idx)
                     0: coeff_lookup =  18'sd16;
                     1: coeff_lookup = -18'sd24;
                     2: coeff_lookup =  18'sd17;
                     3: coeff_lookup = -18'sd33;
                     4: coeff_lookup =  18'sd35;
                     5: coeff_lookup = -18'sd48;
                     6: coeff_lookup =  18'sd55;
                     7: coeff_lookup = -18'sd67;
                     8: coeff_lookup =  18'sd77;
                     9: coeff_lookup = -18'sd89;
                    10: coeff_lookup =  18'sd99;
                    11: coeff_lookup = -18'sd111;
                    12: coeff_lookup =  18'sd121;
                    13: coeff_lookup = -18'sd131;
                    14: coeff_lookup =  18'sd139;
                    15: coeff_lookup = -18'sd147;
                    16: coeff_lookup =  18'sd153;
                    17: coeff_lookup = -18'sd157;
                    18: coeff_lookup =  18'sd160;
                    19: coeff_lookup =  18'sd16223;
                    20: coeff_lookup =  18'sd160;
                    21: coeff_lookup = -18'sd157;
                    22: coeff_lookup =  18'sd153;
                    23: coeff_lookup = -18'sd147;
                    24: coeff_lookup =  18'sd139;
                    25: coeff_lookup = -18'sd131;
                    26: coeff_lookup =  18'sd121;
                    27: coeff_lookup = -18'sd111;
                    28: coeff_lookup =  18'sd99;
                    29: coeff_lookup = -18'sd89;
                    30: coeff_lookup =  18'sd77;
                    31: coeff_lookup = -18'sd67;
                    32: coeff_lookup =  18'sd55;
                    33: coeff_lookup = -18'sd48;
                    34: coeff_lookup =  18'sd35;
                    35: coeff_lookup = -18'sd33;
                    36: coeff_lookup =  18'sd17;
                    37: coeff_lookup = -18'sd24;
                    38: coeff_lookup =  18'sd16;
                    default: coeff_lookup = 18'sd0;
                endcase
            end
            2'd2: begin
                case (tap_idx)
                     0: coeff_lookup =  18'sd16;
                     1: coeff_lookup = -18'sd32;
                     2: coeff_lookup =  18'sd32;
                     3: coeff_lookup = -18'sd55;
                     4: coeff_lookup =  18'sd69;
                     5: coeff_lookup = -18'sd97;
                     6: coeff_lookup =  18'sd124;
                     7: coeff_lookup = -18'sd161;
                     8: coeff_lookup =  18'sd203;
                     9: coeff_lookup = -18'sd255;
                    10: coeff_lookup =  18'sd316;
                    11: coeff_lookup = -18'sd391;
                    12: coeff_lookup =  18'sd484;
                    13: coeff_lookup = -18'sd604;
                    14: coeff_lookup =  18'sd764;
                    15: coeff_lookup = -18'sd998;
                    16: coeff_lookup =  18'sd1382;
                    17: coeff_lookup = -18'sd2176;
                    18: coeff_lookup =  18'sd5012;
                    19: coeff_lookup =  18'sd14631;
                    20: coeff_lookup = -18'sd2806;
                    21: coeff_lookup =  18'sd1473;
                    22: coeff_lookup = -18'sd948;
                    23: coeff_lookup =  18'sd664;
                    24: coeff_lookup = -18'sd483;
                    25: coeff_lookup =  18'sd359;
                    26: coeff_lookup = -18'sd268;
                    27: coeff_lookup =  18'sd199;
                    28: coeff_lookup = -18'sd147;
                    29: coeff_lookup =  18'sd106;
                    30: coeff_lookup = -18'sd76;
                    31: coeff_lookup =  18'sd51;
                    32: coeff_lookup = -18'sd35;
                    33: coeff_lookup =  18'sd19;
                    34: coeff_lookup = -18'sd14;
                    35: coeff_lookup =  18'sd1;
                    36: coeff_lookup = -18'sd7;
                    37: coeff_lookup = -18'sd8;
                    38: coeff_lookup =  18'sd13;
                    default: coeff_lookup = 18'sd0;
                endcase
            end
            2'd3: begin
                case (tap_idx)
                     0: coeff_lookup =  18'sd8;
                     1: coeff_lookup = -18'sd26;
                     2: coeff_lookup =  18'sd27;
                     3: coeff_lookup = -18'sd49;
                     4: coeff_lookup =  18'sd65;
                     5: coeff_lookup = -18'sd95;
                     6: coeff_lookup =  18'sd126;
                     7: coeff_lookup = -18'sd170;
                     8: coeff_lookup =  18'sd221;
                     9: coeff_lookup = -18'sd286;
                    10: coeff_lookup =  18'sd367;
                    11: coeff_lookup = -18'sd468;
                    12: coeff_lookup =  18'sd597;
                    13: coeff_lookup = -18'sd769;
                    14: coeff_lookup =  18'sd1008;
                    15: coeff_lookup = -18'sd1370;
                    16: coeff_lookup =  18'sd1999;
                    17: coeff_lookup = -18'sd3424;
                    18: coeff_lookup =  18'sd10413;
                    19: coeff_lookup =  18'sd10413;
                    20: coeff_lookup = -18'sd3424;
                    21: coeff_lookup =  18'sd1999;
                    22: coeff_lookup = -18'sd1370;
                    23: coeff_lookup =  18'sd1008;
                    24: coeff_lookup = -18'sd769;
                    25: coeff_lookup =  18'sd597;
                    26: coeff_lookup = -18'sd468;
                    27: coeff_lookup =  18'sd367;
                    28: coeff_lookup = -18'sd286;
                    29: coeff_lookup =  18'sd221;
                    30: coeff_lookup = -18'sd170;
                    31: coeff_lookup =  18'sd126;
                    32: coeff_lookup = -18'sd95;
                    33: coeff_lookup =  18'sd65;
                    34: coeff_lookup = -18'sd49;
                    35: coeff_lookup =  18'sd27;
                    36: coeff_lookup = -18'sd26;
                    37: coeff_lookup =  18'sd8;
                    38: coeff_lookup =  18'sd0;
                    default: coeff_lookup = 18'sd0;
                endcase
            end
                default: coeff_lookup = 18'sd0;
            endcase
        end
    endfunction

    //=========================================================
    // 4）MAC 控制寄存器
    //=========================================================
    reg        busy;
    reg [5:0]  tap_idx;
    reg [1:0]  work_phase;

    reg signed [ACC_W-1:0] acc_work;

    reg signed [ACC_W-1:0] result_reg;
    reg                    result_valid;
    reg [1:0]              result_phase;

    // 输出寄存
    reg signed [ACC_W-1:0] y_out_full_r;
    reg                    y_out_valid_r;
    reg [1:0]              phase_dbg_r;
    reg signed [23:0]      fir_in_dbg_r;
    reg                    fir_in_valid_dbg_r;

    //=========================================================
    // 5）两路乘法通道的组合输入
    //=========================================================
    reg signed [DATA_W-1:0]  sample_a;
    reg signed [DATA_W-1:0]  sample_b;
    reg signed [COEFF_W-1:0] coeff_a;
    reg signed [COEFF_W-1:0] coeff_b;

    always @(*) begin
        if (tap_idx < PHASE_TAPS)
            sample_a = x_delay[tap_idx];
        else
            sample_a = {DATA_W{1'b0}};

        if ((tap_idx + 6'd1) < PHASE_TAPS)
            sample_b = x_delay[tap_idx + 6'd1];
        else
            sample_b = {DATA_W{1'b0}};

        coeff_a = coeff_lookup(work_phase, tap_idx);
        coeff_b = coeff_lookup(work_phase, tap_idx + 6'd1);
    end

    // 两个时分复用乘法器。
    // 由于 sample/coeff 都是运行时选择值，Vivado 通常会推成 2 个 DSP48。
    // 只对两个乘法器结果加 use_dsp="yes"，
    // 不对 pair_sum / acc_next 加该属性，避免累加器被综合进 DSP。
    (* use_dsp = "yes" *) wire signed [PROD_W-1:0] prod_a;
    (* use_dsp = "yes" *) wire signed [PROD_W-1:0] prod_b;

    assign prod_a = $signed(sample_a) * $signed(coeff_a);
    assign prod_b = $signed(sample_b) * $signed(coeff_b);

    wire signed [PAIR_W-1:0] pair_sum;
    assign pair_sum = $signed({prod_a[PROD_W-1], prod_a})
                    + $signed({prod_b[PROD_W-1], prod_b});

    wire signed [ACC_W-1:0] pair_sum_ext;
    assign pair_sum_ext = {{(ACC_W-PAIR_W){pair_sum[PAIR_W-1]}}, pair_sum};

    wire signed [ACC_W-1:0] acc_next;
    assign acc_next = acc_work + pair_sum_ext;

    //=========================================================
    // 6）主时序逻辑
    //
    // ce_out 到来：
    //   1. 输出上一相已经算好的 result；
    //   2. 启动当前相位的 39 tap MAC 计算；
    //   3. 若当前相位为 0，则写入新的原始输入样本。
    //
    // 非 ce_out 周期：
    //   如果 busy=1，则每拍计算 2 个 tap。
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_cnt          <= 2'd0;
            busy               <= 1'b0;
            tap_idx            <= 6'd0;
            work_phase         <= 2'd0;
            acc_work           <= {ACC_W{1'b0}};

            result_reg         <= {ACC_W{1'b0}};
            result_valid       <= 1'b0;
            result_phase       <= 2'd0;

            y_out_full_r       <= {ACC_W{1'b0}};
            y_out_valid_r      <= 1'b0;
            phase_dbg_r        <= 2'd0;
            fir_in_dbg_r       <= 24'sd0;
            fir_in_valid_dbg_r <= 1'b0;

            for (i = 0; i < PHASE_TAPS; i = i + 1) begin
                x_delay[i] <= {DATA_W{1'b0}};
            end
        end
        else begin
            y_out_valid_r      <= 1'b0;
            fir_in_valid_dbg_r <= 1'b0;

            if (ce_out) begin
                // 输出上一相计算结果
                if (result_valid) begin
                    y_out_full_r  <= result_reg;
                    y_out_valid_r <= 1'b1;
                    phase_dbg_r   <= result_phase;
                end

                // result 被消费
                result_valid <= 1'b0;

                // 若当前启动 phase=0，则写入新原始输入样本
                if ((phase_cnt == 2'd0) && x_in_valid) begin
                    x_delay[0] <= x_in;
                    for (i = 1; i < PHASE_TAPS; i = i + 1) begin
                        x_delay[i] <= x_delay[i-1];
                    end
                end

                // 启动当前相位 MAC
                busy       <= 1'b1;
                tap_idx    <= 6'd0;
                acc_work   <= {ACC_W{1'b0}};
                work_phase <= phase_cnt;

                // 调试：等效补零输入序列
                fir_in_valid_dbg_r <= 1'b1;
                if ((phase_cnt == 2'd0) && x_in_valid)
                    fir_in_dbg_r <= x_in;
                else
                    fir_in_dbg_r <= 24'sd0;

                // 下次 ce_out 启动下一相
                if (phase_cnt == 2'd3)
                    phase_cnt <= 2'd0;
                else
                    phase_cnt <= phase_cnt + 2'd1;
            end
            else if (busy) begin
                acc_work <= acc_next;

                if (tap_idx >= 6'd38) begin
                    // 39 tap 计算完成
                    busy         <= 1'b0;
                    result_reg   <= acc_next;
                    result_valid <= 1'b1;
                    result_phase <= work_phase;
                    tap_idx      <= 6'd0;
                end
                else begin
                    tap_idx <= tap_idx + 6'd2;
                end
            end
        end
    end

    //=========================================================
    // 7）Q16 全精度输出 -> 24 bit 饱和输出
    //=========================================================
    round_sat_q16_to24 #(
        .IN_W    (ACC_W),
        .OUT_W   (24),
        .FRAC_W  (16)
    ) u_round_sat_q16_to24 (
        .din_full (y_out_full_r),
        .dout_24  (y_out)
    );

    assign y_out_valid      = y_out_valid_r;
    assign phase_dbg        = phase_dbg_r;
    assign fir_in_dbg       = fir_in_dbg_r;
    assign fir_in_valid_dbg = fir_in_valid_dbg_r;

endmodule
`default_nettype wire
