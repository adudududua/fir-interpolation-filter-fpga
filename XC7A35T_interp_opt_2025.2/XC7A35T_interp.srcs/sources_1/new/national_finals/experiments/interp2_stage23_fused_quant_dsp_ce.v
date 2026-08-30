`timescale 1ns / 1ps

//=============================================================
// 文件名       : interp2_stage23_fused_quant_dsp_ce.v
// 模块名       : interp2_stage23_fused_quant_dsp_ce
// 功能简述     : 第二、三级 2 倍插值滤波器：复用或折叠运算资源完成连续插值。
// 设计说明     : 本文件采用同步时序设计；复位、时钟使能、
//                有效信号和定点位宽关系均在对应代码段说明。
//                注释仅用于阐明实现，不参与综合结果。
// 设计作者     : kafeizizi
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     : 2026-08-30：统一中文文件头、模块编号与结构说明。
//=============================================================

//=============================================================
// 鏂囦欢鍚?      : interp2_stage23_lutram_cic_dsp_ce.v
// 妯″潡鍚?      : interp2_stage23_lutram_cic_dsp_ce
// 鍔熻兘绠€杩?    : Stage 2/3 鍏变韩 DSP 鐨勪綆 LUT true-polyphase FIR銆?
//                浣跨敤涓や釜 16 娣卞害鍗曡鍙ｅ垎甯冨紡 RAM 寰幆缂撳啿鏇夸唬
//                鍘嗗彶鏍风偣绉讳綅瀵勫瓨鍣ㄣ€傚绉版娊澶翠笉鍐嶅苟琛岄鍔狅紝鑰屾槸
//                渚濇閫佸叆鍚屼竴涓?DSP48 MAC锛屼互鍗曞彛 RAM 鍜屾洿澶氱┖闂?
//                鏃堕挓鍛ㄦ湡浜ゆ崲鏇村皯鐨?LUT銆?
//
//                Stage 2锛歱hase0=9 MAC锛宲hase1=8 MAC锛孮15
//                Stage 3锛歱hase0=6 MAC锛宲hase1=5 MAC锛孮15
//                Stage 3 涓績绯绘暟 35604 鐩存帴浣跨敤 18bit signed
//                琛ㄧず锛屼笌 -29932+65536 鐨?38bit 妯¤繍绠椾弗鏍肩瓑浠枫€?
//
// 褰撳墠榛樿閰嶇疆锛?
//                  Stage 2 鏁版嵁浣嶅锛?2bit signed
//                  Stage 3 鏁版嵁浣嶅锛?0bit signed
//                  绯绘暟浣嶅        锛?8bit signed Q15
//                  绱姞浣嶅        锛?8bit signed
//                  鍘嗗彶瀛樺偍        锛氬崟璇诲彛 LUTRAM 寰幆缂撳啿
//                  鍏变韩 DSP 鏁伴噺   锛?
//
// 璁捐浣滆€?    : kafeizizi
// 鍒涘缓鏃ユ湡     : 2026-07-18
// 鐗堟湰         : V2018.3
// 寮€鍙戝伐鍏?    : Vivado
// 淇璁板綍     :
//                2026-07-18锛氭柊澧?Stage 2/3 LUTRAM 浣?LUT 鍊欓€夈€?
//                2026-07-18锛氫覆琛?MAC 璋冨害鏀逛负 Stage 2 浼樺厛锛屼繚璇?
//                            4x 鏍风偣鍦ㄤ笅涓€娆?8x CE 鍓嶅畬鎴愩€?
//                2026-07-18锛氬鍔犲彲閫夊弻鍙?BRAM 鍘嗗彶缂撳瓨锛涢噰鐢ㄤ换鍔?
//                            鍚姩棰勫彇锛屼繚鎸佷覆琛?MAC 鍛ㄦ湡鏁颁笉鍙樸€?
//                2026-07-18锛氬鍔犲彲閫夐『搴忕郴鏁?BRAM锛屽睍寮€瀵圭О绯绘暟
//                            骞朵笌鍘嗗彶鏍风偣鍚屾媿棰勫彇銆?
//                2026-07-18锛氬鍔?Stage2/3 鍘嗗彶涓庝氦鍙夌骇绯绘暟 BRAM
//                            鎵撳寘鍊欓€夛紝澶嶇敤涓ゅ潡瀛樺偍閾惰鐨勮绔彛銆?
//=============================================================

`include "all2x_v2_coeff_pkg.vh"
//=============================================================
// 1）模块名称：interp2_stage23_fused_quant_dsp_ce
// 功能说明：第二、三级 2 倍插值滤波器：复用或折叠运算资源完成连续插值。
// 工程版本：Vivado 2025.2。
//=============================================================

module interp2_stage23_fused_quant_dsp_ce #(
    parameter integer DATA_W = 24,
    parameter integer STAGE2_INPUT_W = 24,
    parameter integer STAGE3_INPUT_W = 22,
    parameter integer STAGE2_DATA_W = 22,
    parameter integer STAGE3_DATA_W = 20,
    parameter integer STAGE3_OUTPUT_W = STAGE3_DATA_W,
    parameter integer COEFF_W = 18,
    parameter integer ACC_W = 38,
    parameter integer CIC_ORDER = 3,
    parameter integer STAGE3_FLAT = 0,
    parameter integer USE_BRAM_HISTORY = 0,
    parameter integer USE_UNIFIED_BRAM_HISTORY = 0,
    parameter integer USE_BRAM_COEFF = 0,
    parameter integer USE_PACKED_BRAM = 0,
    parameter integer USE_EXTERNAL_COEFF_BRAM = 0,
    parameter integer USE_P3_JOINT_STAGE3 = 0,
    parameter integer ASSUME_ALIGNED_POW2_CE = 0
)(
    input  wire                              clk,
    input  wire                              rst_n,

    input  wire                              stage2_ce_out,
    input  wire signed [STAGE2_INPUT_W-1:0]  stage2_x_in,
    input  wire                              stage2_x_in_valid,
    output reg  signed [STAGE2_DATA_W-1:0]   stage2_y_out,
    output reg                               stage2_y_out_valid,

    input  wire                              stage3_ce_out,
    input  wire signed [STAGE3_INPUT_W-1:0]  stage3_x_in,
    input  wire                              stage3_x_in_valid,
    input  wire                              stage3_compensated_mode,
    output reg  signed [STAGE3_OUTPUT_W-1:0] stage3_y_out,
    output reg                               stage3_y_out_valid,

    output wire                              stage2_phase_dbg,
    output wire                              stage3_phase_dbg,
    output wire                              scheduler_busy_dbg,
    output wire [1:0]                        scheduler_stage_dbg,
    output wire [3:0]                        scheduler_mac_index_dbg,

    output wire [6:0]                        external_coeff_addr,
    input  wire signed [17:0]                external_coeff_data
);

    localparam integer MEM_ADDR_W = 4;
    localparam integer MEM_DEPTH = 16;
    localparam integer FRAC_W = 15;
    localparam integer INPUT_QUANT_SHIFT = 2;
    localparam integer HISTORY_DATA_W = STAGE2_INPUT_W;
    localparam integer SHIFT_W = ACC_W - FRAC_W;
    localparam integer STAGE2_UPPER_W = SHIFT_W - STAGE2_DATA_W;
    localparam integer STAGE3_UPPER_W = SHIFT_W - STAGE3_OUTPUT_W;
    localparam integer PATTERN_SAT_SUPPORTED =
        (STAGE2_DATA_W == 22 && STAGE3_OUTPUT_W == 21);
    localparam [2:0] JOB_IDLE       = 3'd0;
    localparam [2:0] JOB_MAC        = 3'd1;
    localparam [2:0] JOB_ROUND      = 3'd2;
    localparam [2:0] JOB_SATURATION = 3'd3;
    localparam [2:0] JOB_WRITE      = 3'd4;
    localparam signed [STAGE2_DATA_W-1:0] STAGE2_OUT_MAX =
        {1'b0, {(STAGE2_DATA_W-1){1'b1}}};
    localparam signed [STAGE2_DATA_W-1:0] STAGE2_OUT_MIN =
        {1'b1, {(STAGE2_DATA_W-1){1'b0}}};
    localparam signed [STAGE3_OUTPUT_W-1:0] STAGE3_OUT_MAX =
        {1'b0, {(STAGE3_OUTPUT_W-1){1'b1}}};
    localparam signed [STAGE3_OUTPUT_W-1:0] STAGE3_OUT_MIN =
        {1'b1, {(STAGE3_OUTPUT_W-1){1'b0}}};

    (* ram_style = "distributed" *)
    reg signed [STAGE2_INPUT_W-1:0] stage2_hist_mem [0:MEM_DEPTH-1];
    (* ram_style = "distributed" *)
    reg signed [STAGE3_INPUT_W-1:0] stage3_hist_mem [0:MEM_DEPTH-1];
    (* ram_style = "block" *)
    reg signed [STAGE2_INPUT_W-1:0] stage2_hist_bram [0:MEM_DEPTH-1];
    (* ram_style = "block" *)
    reg signed [STAGE3_INPUT_W-1:0] stage3_hist_bram [0:MEM_DEPTH-1];

    reg [MEM_ADDR_W-1:0] stage2_head;
    reg [MEM_ADDR_W-1:0] stage3_head;
    // Head moves backwards from zero on every accepted history sample.  Its
    // two's-complement magnitude is the fill depth until the short FIR
    // history is full; only a sticky full flag is then required.
    reg stage2_history_full;
    reg stage3_history_full;

    reg stage2_phase;
    reg stage3_phase;
    reg stage2_pending;
    reg stage3_pending;
    reg stage3_pending_compensated;

    reg [2:0] job_state;
    reg job_stage3;
    reg job_phase;
    reg [3:0] job_mac_index;
    reg [MEM_ADDR_W-1:0] job_history_head;
    reg job_history_full;
    wire [3:0] job_mac_count;
    wire [MEM_ADDR_W-1:0] job_fill_from_head;
    wire job_history_valid;

    wire [MEM_ADDR_W-1:0] hist_index;
    wire [MEM_ADDR_W-1:0] hist_pair_limit;
    wire [MEM_ADDR_W-1:0] hist_mirror_index;
    wire [MEM_ADDR_W-1:0] coeff_index;
    wire [4:0] coeff_addr;
    wire signed [COEFF_W-1:0] coeff_comb;

    (* rom_style = "distributed" *)
    reg signed [COEFF_W-1:0] coeff_rom [0:31];
    (* rom_style = "block" *)
    reg signed [COEFF_W-1:0] coeff_sequence_bram [0:63];
    // 鎵撳寘妯″紡涓嬶紝Stage2 閾惰淇濆瓨 Stage2 鍘嗗彶鍜?Stage3 绯绘暟锛?
    // Stage3 閾惰淇濆瓨 Stage3 鍘嗗彶鍜?Stage2 绯绘暟銆備袱绾т换鍔′笉浼氬苟琛岋紝
    // 鍥犺€屾瘡鎷嶆瘡涓摱琛屽彧闇€瑕佷竴娆¤鍜屼竴娆″彲閫夊啓銆?
    (* ram_style = "block" *)
    reg signed [STAGE2_INPUT_W-1:0] stage2_packed_bram [0:63];
    (* ram_style = "block" *)
    reg signed [STAGE3_INPUT_W-1:0] stage3_packed_bram [0:63];

    reg signed [COEFF_W-1:0] coeff_bram_raw;
    wire job_active;
    wire job_result_pending;
    wire job_output_pending;
    wire job_saturation_pending;

    wire [MEM_ADDR_W-1:0] stage2_write_addr;
    wire [MEM_ADDR_W-1:0] stage3_write_addr;
    wire [MEM_ADDR_W-1:0] history_read_head;
    wire [MEM_ADDR_W-1:0] stage2_read_addr;
    wire [MEM_ADDR_W-1:0] stage3_read_addr;
    wire [MEM_ADDR_W-1:0] stage2_bram_read_index;
    wire [MEM_ADDR_W-1:0] stage3_bram_read_index;
    wire [MEM_ADDR_W-1:0] stage2_bram_read_addr;
    wire [MEM_ADDR_W-1:0] stage3_bram_read_addr;

    wire signed [STAGE2_INPUT_W-1:0] stage2_x_current;
    wire signed [STAGE3_INPUT_W-1:0] stage3_x_current;
    wire signed [STAGE2_INPUT_W-1:0] stage2_lutram_raw;
    wire signed [STAGE3_INPUT_W-1:0] stage3_lutram_raw;
    reg signed [STAGE2_INPUT_W-1:0] stage2_bram_raw;
    reg signed [STAGE3_INPUT_W-1:0] stage3_bram_raw;
    wire signed [HISTORY_DATA_W-1:0] stage23_unified_bram_raw;
    reg stage3_write_queued;
    reg [MEM_ADDR_W-1:0] stage3_queued_write_addr;
    reg signed [STAGE3_INPUT_W-1:0] stage3_queued_write_data;
    reg signed [STAGE2_INPUT_W-1:0] stage2_packed_raw;
    reg signed [STAGE3_INPUT_W-1:0] stage3_packed_raw;
    wire signed [STAGE2_INPUT_W-1:0] stage2_mem_raw;
    wire signed [STAGE3_INPUT_W-1:0] stage3_mem_raw;
    wire signed [STAGE2_INPUT_W-1:0] stage2_mem;
    wire signed [STAGE3_INPUT_W-1:0] stage3_mem;
    wire signed [STAGE2_DATA_W-1:0] stage2_truncated_sample;
    wire signed [STAGE3_DATA_W-1:0] stage3_truncated_sample;
    wire signed [STAGE2_DATA_W-1:0] selected_truncated_sample;
    wire selected_round_increment;
    wire signed [24:0] dsp_preadd_a;
    wire signed [29:0] dsp_input_a;
    wire signed [24:0] dsp_input_d;
    wire signed [17:0] dsp_coeff_b;
    wire signed [47:0] dsp_mac_full;
    wire signed [ACC_W-1:0] mac_sum_comb;
    wire dsp_p_reset;
    wire [6:0] dsp_opmode;
    wire signed [47:0] dsp_round_bias;
    wire signed [47:0] dsp_c_input;
    wire signed [47:0] dsp_saturation_value;
    wire signed [47:0] stage2_sat_max_scaled;
    wire signed [47:0] stage2_sat_min_scaled;
    wire signed [47:0] stage3_sat_max_scaled;
    wire signed [47:0] stage3_sat_min_scaled;
    wire dsp_round_carryin;
    wire dsp_pattern_zero;
    wire dsp_pattern_ones;
    wire signed [STAGE2_DATA_W-1:0] stage2_q15_rounded;
    wire signed [STAGE3_OUTPUT_W-1:0] stage3_q15_rounded;
    wire signed [SHIFT_W-1:0] truncated_value;
    wire stage2_upper_is_sign_extension;
    wire stage3_upper_is_sign_extension;
    wire coeff_bram_stage3;
    wire coeff_bram_phase;
    wire coeff_bram_stage3_compensated;
    wire [3:0] coeff_bram_next_index;
    wire [5:0] coeff_bram_read_addr;
    wire [5:0] packed_coeff_read_addr;
    wire [5:0] stage2_packed_read_addr;
    wire [5:0] stage3_packed_read_addr;
    wire signed [COEFF_W-1:0] packed_coeff_raw;
    wire unified_read_stage3;
    wire [MEM_ADDR_W-1:0] unified_read_index;
    wire [MEM_ADDR_W:0] unified_read_addr;
    wire stage2_history_write_event;
    wire stage3_history_write_event;
    wire unified_write_enable;
    wire [MEM_ADDR_W:0] unified_write_addr;
    wire signed [HISTORY_DATA_W-1:0] unified_write_data;

    integer coeff_init_idx;
    integer coeff_sequence_init_idx;
    integer packed_init_idx;


    assign job_active = job_state == JOB_MAC;
    assign job_result_pending = job_state == JOB_ROUND;
    assign job_output_pending = job_state == JOB_SATURATION;
    assign job_saturation_pending = job_state == JOB_WRITE;

    assign stage2_x_current = stage2_x_in_valid ?
                              stage2_x_in : {STAGE2_INPUT_W{1'b0}};
    assign stage3_x_current = stage3_x_in_valid ?
                              stage3_x_in : {STAGE3_INPUT_W{1'b0}};

    assign stage2_write_addr = stage2_head - {{(MEM_ADDR_W-1){1'b0}}, 1'b1};
    assign stage3_write_addr = stage3_head - {{(MEM_ADDR_W-1){1'b0}}, 1'b1};
    // The shared MAC can observe only one history bank at a time.  A single
    // latched head therefore serves both banks during a job; while idle, the
    // same address path prefetches index zero for the next priority-selected
    // pending job.
    assign history_read_head = job_active ? job_history_head :
        (stage2_pending ? stage2_head : stage3_head);
    assign hist_index = job_mac_index[MEM_ADDR_W-1:0];
    assign hist_pair_limit = !job_stage3 ?
                             (job_phase ? 4'd7 : 4'd8) :
                             (job_phase ? 4'd4 : 4'd5);
    assign hist_mirror_index = hist_pair_limit - hist_index;
    assign coeff_index = (hist_index <= hist_mirror_index) ?
                         hist_index : hist_mirror_index;
    assign coeff_addr = {job_stage3, job_phase,
                         coeff_index[2:0]};
    assign coeff_comb = coeff_rom[coeff_addr];
    assign job_mac_count = !job_stage3 ?
        (job_phase ? 4'd8 : 4'd9) :
        (job_phase ? 4'd5 : 4'd6);
    assign job_fill_from_head = (~job_history_head) + 4'd1;
    assign job_history_valid = job_history_full ||
                               hist_index < job_fill_from_head;

    assign coeff_bram_stage3 = job_active ? job_stage3 :
        (!stage2_pending && stage3_pending);
    assign coeff_bram_phase = job_active ? job_phase :
        (stage2_pending ? ~stage2_phase : ~stage3_phase);
    assign coeff_bram_stage3_compensated =
        (USE_P3_JOINT_STAGE3 != 0) && coeff_bram_stage3 &&
        stage3_pending_compensated;
    assign coeff_bram_next_index = job_active ?
        job_mac_index + 4'd1 : 4'd0;
    assign coeff_bram_read_addr = {coeff_bram_stage3,
                                   coeff_bram_phase,
                                   coeff_bram_next_index};
    assign external_coeff_addr = coeff_bram_stage3_compensated ?
        {2'b11, coeff_bram_phase, coeff_bram_next_index} :
        {1'b0, coeff_bram_read_addr};
    // 鍦板潃 0锝?5 淇濆瓨鍘嗗彶锛?6锝?1 鍜?32锝?7 鍒嗗埆淇濆瓨涓ょ浉绯绘暟銆?
    assign packed_coeff_read_addr = {coeff_bram_phase,
                                     ~coeff_bram_phase,
                                     coeff_bram_next_index};

    assign stage2_read_addr = history_read_head + hist_index;
    assign stage3_read_addr = history_read_head + hist_index;

    // BRAM 涓哄悓姝ヨ銆備换鍔＄┖闂蹭笖 pending 鏃惰鍙?index0锛涗换鍔℃椿鍔ㄦ椂锛?
    // 鍦ㄥ綋鍓嶆娊澶磋繘鍏?DSP 鐨勫悓鏃堕鍙栦笅涓€涓娊澶达紝閬垮厤棰濆绌烘媿銆?
    assign stage2_bram_read_index =
        (job_active && !job_stage3) ? hist_index + 4'd1 : 4'd0;
    assign stage3_bram_read_index =
        (job_active && job_stage3) ? hist_index + 4'd1 : 4'd0;
    assign stage2_bram_read_addr =
        history_read_head + stage2_bram_read_index;
    assign stage3_bram_read_addr =
        history_read_head + stage3_bram_read_index;
    assign stage2_packed_read_addr = coeff_bram_stage3 ?
        packed_coeff_read_addr : {2'b00, stage2_bram_read_addr};
    assign stage3_packed_read_addr = coeff_bram_stage3 ?
        {2'b00, stage3_bram_read_addr} : packed_coeff_read_addr;
    assign unified_read_stage3 = coeff_bram_stage3;
    assign unified_read_index = job_active ? hist_index + 4'd1 : 4'd0;
    assign unified_read_addr = {
        unified_read_stage3,
        history_read_head + unified_read_index
    };
    assign stage2_history_write_event =
        stage2_ce_out && stage2_phase == 1'b0;
    assign stage3_history_write_event =
        stage3_ce_out && stage3_phase == 1'b0;
    assign unified_write_enable =
                                  ((ASSUME_ALIGNED_POW2_CE == 0) &&
                                   stage3_write_queued) ||
                                  stage2_history_write_event ||
                                  stage3_history_write_event;
    assign unified_write_addr =
        ((ASSUME_ALIGNED_POW2_CE == 0) && stage3_write_queued) ?
        {1'b1, stage3_queued_write_addr} :
        (stage2_history_write_event ? {1'b0, stage2_write_addr} :
                                      {1'b1, stage3_write_addr});
    assign unified_write_data =
        ((ASSUME_ALIGNED_POW2_CE == 0) && stage3_write_queued) ?
        {{(HISTORY_DATA_W-STAGE3_INPUT_W){
            stage3_queued_write_data[STAGE3_INPUT_W-1]}},
         stage3_queued_write_data} :
        (stage2_history_write_event ? stage2_x_current :
         {{(HISTORY_DATA_W-STAGE3_INPUT_W){
            stage3_x_current[STAGE3_INPUT_W-1]}}, stage3_x_current});

    assign stage2_lutram_raw = stage2_hist_mem[stage2_read_addr];
    assign stage3_lutram_raw = stage3_hist_mem[stage3_read_addr];

    // Do not build a DATA_W-wide Fabric mux to replace unread BRAM history
    // with zero.  Invalid startup taps instead disable the DSP48 P register,
    // which is exactly equivalent to accumulating a zero product and leaves
    // the running sum unchanged.  This also preserves arbitrary reset
    // recovery without clearing the BRAM arrays.
    assign stage2_mem = stage2_mem_raw;
    assign stage3_mem = stage3_mem_raw;

    // Preserve the exact two-bit symmetric round-away-from-zero rule of the
    // removed bridge.  The arithmetic right shift is wiring; DSP48 A+D adds
    // the single rounding increment before multiplication, so no fabric
    // carry chain is required.
    assign stage2_truncated_sample = stage2_mem >>> INPUT_QUANT_SHIFT;
    assign stage3_truncated_sample = stage3_mem >>> INPUT_QUANT_SHIFT;
    assign selected_truncated_sample = !job_stage3 ?
        stage2_truncated_sample :
        {{(STAGE2_DATA_W-STAGE3_DATA_W){
            stage3_truncated_sample[STAGE3_DATA_W-1]}},
         stage3_truncated_sample};
    assign selected_round_increment = !job_stage3 ?
        (stage2_mem[1] && (!stage2_mem[STAGE2_INPUT_W-1] ||
                           stage2_mem[0]) &&
         !(stage2_truncated_sample ==
           {1'b0, {(STAGE2_DATA_W-1){1'b1}}})) :
        (stage3_mem[1] && (!stage3_mem[STAGE3_INPUT_W-1] ||
                           stage3_mem[0]) &&
         !(stage3_truncated_sample ==
           {1'b0, {(STAGE3_DATA_W-1){1'b1}}}));
    assign dsp_preadd_a =
        {{(25-STAGE2_DATA_W){
            selected_truncated_sample[STAGE2_DATA_W-1]}},
         selected_truncated_sample};
    assign dsp_input_a =
        {{5{dsp_preadd_a[24]}}, dsp_preadd_a};
    assign dsp_input_d = selected_round_increment ? 25'sd1 : 25'sd0;
    assign packed_coeff_raw = coeff_bram_stage3 ?
        stage2_packed_raw[COEFF_W-1:0] :
        stage3_packed_raw[COEFF_W-1:0];
    assign dsp_coeff_b = (USE_EXTERNAL_COEFF_BRAM != 0) ?
        external_coeff_data :
        ((USE_PACKED_BRAM != 0) ? packed_coeff_raw :
         ((USE_BRAM_COEFF != 0) ? coeff_bram_raw : coeff_comb));
    // PREG is synchronously cleared as a new job is accepted, then feeds the
    // DSP48 ALU Z input on every MAC cycle.  After the final MAC, one otherwise
    // idle cycle adds the exact signed Q15 rounding bias inside the same DSP:
    // +16384 for non-negative sums and +16383 for negative sums.  A second
    // spare cycle uses PATTERNDETECT to keep an in-range result or loads the
    // exact signed limit through the C input when saturation is required.
    assign dsp_p_reset = !rst_n ||
        (!job_active && !job_result_pending && !job_output_pending &&
         !job_saturation_pending &&
         (stage2_pending || stage3_pending));
    assign dsp_round_bias = 48'sd16383;
    assign stage2_sat_max_scaled =
        {{(48-STAGE2_DATA_W-FRAC_W){1'b0}},
         1'b0, {(STAGE2_DATA_W-1){1'b1}}, {FRAC_W{1'b0}}};
    assign stage2_sat_min_scaled =
        {{(48-STAGE2_DATA_W-FRAC_W){1'b1}},
         1'b1, {(STAGE2_DATA_W-1){1'b0}}, {FRAC_W{1'b0}}};
    assign stage3_sat_max_scaled =
        {{(48-STAGE3_OUTPUT_W-FRAC_W){1'b0}},
         1'b0, {(STAGE3_OUTPUT_W-1){1'b1}}, {FRAC_W{1'b0}}};
    assign stage3_sat_min_scaled =
        {{(48-STAGE3_OUTPUT_W-FRAC_W){1'b1}},
         1'b1, {(STAGE3_OUTPUT_W-1){1'b0}}, {FRAC_W{1'b0}}};
    assign dsp_saturation_value = !job_stage3 ?
        (mac_sum_comb[ACC_W-1] ?
         stage2_sat_min_scaled : stage2_sat_max_scaled) :
        (mac_sum_comb[ACC_W-1] ?
         stage3_sat_min_scaled : stage3_sat_max_scaled);
    assign dsp_c_input = job_output_pending ?
        dsp_saturation_value : dsp_round_bias;
    assign dsp_round_carryin =
        job_result_pending && !mac_sum_comb[ACC_W-1];
    assign dsp_opmode = job_output_pending ?
        7'b0001100 :
        (job_result_pending ? 7'b0001110 : 7'b0100101);

    // 鏄惧紡浣跨敤涓€棰?DSP48E1锛岄伩鍏嶇患鍚堝櫒鎶婁箻娉曞拰绱姞鎷嗘垚澶氶 DSP銆?
    // MAC 鍛ㄦ湡鐢?M+P锛屾彁浜ゅ懆鏈熺敤 P+C 鍔犲叆绗﹀彿鐩稿叧鑸嶅叆鍋忕疆銆?
    // 例化说明：调用 DSP48E1 算术原语，完成乘法、加减或累加；各控制字定义当前流水拍的运算功能。
    DSP48E1 #(
        .A_INPUT("DIRECT"),
        .B_INPUT("DIRECT"),
        .USE_DPORT("TRUE"),
        .USE_MULT("MULTIPLY"),
        .USE_PATTERN_DETECT("PATDET"),
        .SEL_MASK("MASK"),
        .SEL_PATTERN("PATTERN"),
        .MASK(48'h000FFFFFFFFF),
        .PATTERN(48'h000000000000),
        .USE_SIMD("ONE48"),
        .AREG(0),
        .ACASCREG(0),
        .BREG(0),
        .BCASCREG(0),
        .CREG(0),
        .DREG(0),
        .ADREG(0),
        .MREG(0),
        .PREG(1),
        .INMODEREG(0),
        .OPMODEREG(0),
        .ALUMODEREG(0),
        .CARRYINREG(0),
        .CARRYINSELREG(0)
    ) u_stage23_dsp48e1 (
        .P(dsp_mac_full),
        .A(dsp_input_a),
        .B(dsp_coeff_b),
        .C(dsp_c_input),
        .D(dsp_input_d),
        .INMODE(5'b00100),
        .OPMODE(dsp_opmode),
        .ALUMODE(4'b0000),
        .CARRYINSEL(3'b000),
        .CARRYIN(dsp_round_carryin),
        .ACIN(30'd0),
        .BCIN(18'd0),
        .PCIN(48'd0),
        .CARRYCASCIN(1'b0),
        .MULTSIGNIN(1'b0),
        .CLK(clk),
        .CEA1(1'b0),
        .CEA2(1'b0),
        .CEAD(1'b0),
        .CEALUMODE(1'b0),
        .CEB1(1'b0),
        .CEB2(1'b0),
        .CEC(1'b0),
        .CECARRYIN(1'b0),
        .CECTRL(1'b0),
        .CED(1'b0),
        .CEINMODE(1'b0),
        .CEM(1'b0),
        .CEP((job_active && job_history_valid) || job_result_pending ||
             (job_output_pending &&
              !(job_stage3 ? stage3_upper_is_sign_extension :
                              stage2_upper_is_sign_extension))),
        .RSTA(1'b0),
        .RSTALLCARRYIN(1'b0),
        .RSTALUMODE(1'b0),
        .RSTB(1'b0),
        .RSTC(1'b0),
        .RSTCTRL(1'b0),
        .RSTD(1'b0),
        .RSTINMODE(1'b0),
        .RSTM(1'b0),
        .RSTP(dsp_p_reset),
        .ACOUT(),
        .BCOUT(),
        .CARRYCASCOUT(),
        .CARRYOUT(),
        .MULTSIGNOUT(),
        .OVERFLOW(),
        .PATTERNBDETECT(dsp_pattern_ones),
        .PATTERNDETECT(dsp_pattern_zero),
        .PCOUT(),
        .UNDERFLOW()
    );
    assign mac_sum_comb = dsp_mac_full[ACC_W-1:0];

    // The PREG value has already received the exact signed rounding bias.
    // For the signed-22/signed-21 national-finals profile, PATTERNDETECT checks
    // P[47:36] and serves both widths exactly: Stage2 includes sign P[36],
    // while Stage3 compares those bits against sign P[35].  Other legal
    // parameterizations retain the generic Fabric comparison fallback.
    assign truncated_value = mac_sum_comb >>> FRAC_W;

    assign stage2_upper_is_sign_extension =
        PATTERN_SAT_SUPPORTED ?
        (mac_sum_comb[STAGE2_DATA_W+FRAC_W-1] ?
         dsp_pattern_ones : dsp_pattern_zero) :
        (truncated_value[SHIFT_W-1:STAGE2_DATA_W] ==
         {STAGE2_UPPER_W{truncated_value[STAGE2_DATA_W-1]}});
    assign stage2_q15_rounded =
        truncated_value[STAGE2_DATA_W-1:0];

    // The national-finals Stage3 coefficients are true Q15 values.  Their
    // worst-case absolute branch sum no longer makes the former 35-bit
    // direct slice safe, so the complete 38-bit view and exact signed
    // saturation remain mandatory.
    assign stage3_upper_is_sign_extension =
        PATTERN_SAT_SUPPORTED ?
        (mac_sum_comb[STAGE3_OUTPUT_W+FRAC_W-1] ?
         dsp_pattern_ones : dsp_pattern_zero) :
        (truncated_value[SHIFT_W-1:STAGE3_OUTPUT_W] ==
         {STAGE3_UPPER_W{truncated_value[STAGE3_OUTPUT_W-1]}});
    assign stage3_q15_rounded =
        truncated_value[STAGE3_OUTPUT_W-1:0];


    assign stage2_phase_dbg = stage2_phase;
    assign stage3_phase_dbg = stage3_phase;
    assign scheduler_busy_dbg =
        job_active || job_result_pending || job_output_pending ||
        job_saturation_pending;
    assign scheduler_stage_dbg = job_active ?
        {1'b1, job_stage3} : 2'd0;
    assign scheduler_mac_index_dbg = job_mac_index;

    initial begin
        for (coeff_init_idx = 0; coeff_init_idx < 32;
             coeff_init_idx = coeff_init_idx + 1)
            coeff_rom[coeff_init_idx] = {COEFF_W{1'b0}};
        for (coeff_sequence_init_idx = 0; coeff_sequence_init_idx < 64;
             coeff_sequence_init_idx = coeff_sequence_init_idx + 1)
            coeff_sequence_bram[coeff_sequence_init_idx] =
                {COEFF_W{1'b0}};
        for (packed_init_idx = 0; packed_init_idx < 64;
             packed_init_idx = packed_init_idx + 1) begin
            stage2_packed_bram[packed_init_idx] =
                {STAGE2_INPUT_W{1'b0}};
            stage3_packed_bram[packed_init_idx] =
                {STAGE3_INPUT_W{1'b0}};
        end

        coeff_rom[0]  = `V2_S2_P0_C0;
        coeff_rom[1]  = `V2_S2_P0_C1;
        coeff_rom[2]  = `V2_S2_P0_C2;
        coeff_rom[3]  = `V2_S2_P0_C3;
        coeff_rom[4]  = `V2_S2_P0_C4;
        coeff_rom[8]  = `V2_S2_P1_C0;
        coeff_rom[9]  = `V2_S2_P1_C1;
        coeff_rom[10] = `V2_S2_P1_C2;
        coeff_rom[11] = `V2_S2_P1_C3;

        coeff_sequence_bram[0] = `V2_S2_P0_C0;
        coeff_sequence_bram[1] = `V2_S2_P0_C1;
        coeff_sequence_bram[2] = `V2_S2_P0_C2;
        coeff_sequence_bram[3] = `V2_S2_P0_C3;
        coeff_sequence_bram[4] = `V2_S2_P0_C4;
        coeff_sequence_bram[5] = `V2_S2_P0_C3;
        coeff_sequence_bram[6] = `V2_S2_P0_C2;
        coeff_sequence_bram[7] = `V2_S2_P0_C1;
        coeff_sequence_bram[8] = `V2_S2_P0_C0;

        coeff_sequence_bram[16] = `V2_S2_P1_C0;
        coeff_sequence_bram[17] = `V2_S2_P1_C1;
        coeff_sequence_bram[18] = `V2_S2_P1_C2;
        coeff_sequence_bram[19] = `V2_S2_P1_C3;
        coeff_sequence_bram[20] = `V2_S2_P1_C3;
        coeff_sequence_bram[21] = `V2_S2_P1_C2;
        coeff_sequence_bram[22] = `V2_S2_P1_C1;
        coeff_sequence_bram[23] = `V2_S2_P1_C0;

        if (STAGE3_FLAT != 0) begin
            // 鍏ㄥ浗璧涚嫭绔?8x 杈撳嚭浣跨敤鍘?Phase 6 骞冲潶 Stage3銆?
            // CIC 鐨勯€氬甫涓嬪瀭鐢卞悗鎺ヤ笁鎶藉ご绉讳綅鍔犳硶鍣ㄥ崟鐙ˉ鍋裤€?
            coeff_rom[16] = 18'sd404;
            coeff_rom[17] = -18'sd3272;
            coeff_rom[18] = 18'sd19250;
            coeff_rom[24] = -18'sd148;
            coeff_rom[25] = 18'sd522;
            coeff_rom[26] = 18'sd32016;

            coeff_sequence_bram[32] = 18'sd404;
            coeff_sequence_bram[33] = -18'sd3272;
            coeff_sequence_bram[34] = 18'sd19250;
            coeff_sequence_bram[35] = 18'sd19250;
            coeff_sequence_bram[36] = -18'sd3272;
            coeff_sequence_bram[37] = 18'sd404;
            coeff_sequence_bram[48] = -18'sd148;
            coeff_sequence_bram[49] = 18'sd522;
            coeff_sequence_bram[50] = 18'sd32016;
            coeff_sequence_bram[51] = 18'sd522;
            coeff_sequence_bram[52] = -18'sd148;
        end
        else if (CIC_ORDER == 3) begin
            coeff_rom[16] = 18'sd561;
            coeff_rom[17] = -18'sd4234;
            coeff_rom[18] = 18'sd20057;
            coeff_rom[24] = 18'sd137;
            coeff_rom[25] = -18'sd1555;
            coeff_rom[26] = 18'sd35604;

            coeff_sequence_bram[32] = 18'sd561;
            coeff_sequence_bram[33] = -18'sd4234;
            coeff_sequence_bram[34] = 18'sd20057;
            coeff_sequence_bram[35] = 18'sd20057;
            coeff_sequence_bram[36] = -18'sd4234;
            coeff_sequence_bram[37] = 18'sd561;
            coeff_sequence_bram[48] = 18'sd137;
            coeff_sequence_bram[49] = -18'sd1555;
            coeff_sequence_bram[50] = 18'sd35604;
            coeff_sequence_bram[51] = -18'sd1555;
            coeff_sequence_bram[52] = 18'sd137;
        end
        else begin
            coeff_rom[16] = 18'sd624;
            coeff_rom[17] = -18'sd4587;
            coeff_rom[18] = 18'sd20348;
            coeff_rom[24] = 18'sd153;
            coeff_rom[25] = -18'sd1971;
            coeff_rom[26] = 18'sd36402;

            coeff_sequence_bram[32] = 18'sd624;
            coeff_sequence_bram[33] = -18'sd4587;
            coeff_sequence_bram[34] = 18'sd20348;
            coeff_sequence_bram[35] = 18'sd20348;
            coeff_sequence_bram[36] = -18'sd4587;
            coeff_sequence_bram[37] = 18'sd624;
            coeff_sequence_bram[48] = 18'sd153;
            coeff_sequence_bram[49] = -18'sd1971;
            coeff_sequence_bram[50] = 18'sd36402;
            coeff_sequence_bram[51] = -18'sd1971;
            coeff_sequence_bram[52] = 18'sd153;
        end

        // Stage2 绯绘暟鍐欏叆 Stage3 閾惰锛孲tage3 绯绘暟鍐欏叆 Stage2 閾惰銆?
        // 璧嬪€煎埌鏇村鐨?signed 鍏冪礌鏃惰嚜鍔ㄦ墽琛岀鍙锋墿灞曘€?
        for (packed_init_idx = 0; packed_init_idx < 16;
             packed_init_idx = packed_init_idx + 1) begin
            stage3_packed_bram[16+packed_init_idx] =
                coeff_sequence_bram[packed_init_idx];
            stage3_packed_bram[32+packed_init_idx] =
                coeff_sequence_bram[16+packed_init_idx];
            stage2_packed_bram[16+packed_init_idx] =
                coeff_sequence_bram[32+packed_init_idx];
            stage2_packed_bram[32+packed_init_idx] =
                coeff_sequence_bram[48+packed_init_idx];
        end
    end

    // 涓ょ RAM 閮戒笉澶嶄綅鍏ㄩ樀鍒椼€傚浣嶆椂娓呯┖宸插啓娣卞害璁℃暟锛岃鍑虹浼?
    // 灞忚斀灏氭湭閲嶅啓鐨勬Ы浣嶏紝鍥犳澶栭儴琛屼负绛変环浜庡巻鍙叉暟缁勬竻闆躲€?
    generate
        if (USE_PACKED_BRAM != 0) begin : gen_packed_bram
            assign stage2_mem_raw = stage2_packed_raw;
            assign stage3_mem_raw = stage3_packed_raw;

            always @(posedge clk) begin
                stage2_packed_raw <=
                    stage2_packed_bram[stage2_packed_read_addr];
                stage3_packed_raw <=
                    stage3_packed_bram[stage3_packed_read_addr];

                if (rst_n) begin
                    if (stage2_ce_out && stage2_phase == 1'b0)
                        stage2_packed_bram[{2'b00, stage2_write_addr}] <=
                            stage2_x_current;
                    if (stage3_ce_out && stage3_phase == 1'b0)
                        stage3_packed_bram[{2'b00, stage3_write_addr}] <=
                            stage3_x_current;
                end
            end
        end
        else if (USE_UNIFIED_BRAM_HISTORY != 0) begin :
                gen_unified_bram_history
            assign stage2_mem_raw = stage23_unified_bram_raw;
            assign stage3_mem_raw =
                stage23_unified_bram_raw[STAGE3_INPUT_W-1:0];

            // 例化说明：调用 nf_stage23_history_ramb18_sdp 全国赛签核子模块，完成正式数据通路中的存储、运算或控制任务。
            nf_stage23_history_ramb18_sdp #(
                .DATA_W(HISTORY_DATA_W),
                .ADDR_W(MEM_ADDR_W+1)
            ) u_nf_stage23_history_ramb18_sdp (
                .clk(clk),
                .read_addr(unified_read_addr),
                .read_data(stage23_unified_bram_raw),
                .write_enable(unified_write_enable),
                .write_addr(unified_write_addr),
                .write_data(unified_write_data)
            );

            // Generic callers retain a one-entry collision queue.  The signed
            // national-finals clock-enable schedule is stronger: ce4 and ce8
            // are aligned powers of two, both phases reset to one, and every
            // coincident CE therefore sees opposite write phases.  Enabling
            // the assumption removes the otherwise unreachable 25-bit queue.
            if (ASSUME_ALIGNED_POW2_CE == 0) begin : gen_write_queue
                always @(posedge clk) begin
                    if (!rst_n) begin
                        stage3_write_queued <= 1'b0;
                        stage3_queued_write_addr <= {MEM_ADDR_W{1'b0}};
                        stage3_queued_write_data <=
                            {STAGE3_INPUT_W{1'b0}};
                    end
                    else if (stage3_write_queued) begin
                        stage3_write_queued <= 1'b0;
                    end
                    else if (stage2_history_write_event) begin
                        if (stage3_history_write_event) begin
                            stage3_write_queued <= 1'b1;
                            stage3_queued_write_addr <= stage3_write_addr;
                            stage3_queued_write_data <= stage3_x_current;
                        end
                    end
                end
            end
        end
        else if (USE_BRAM_HISTORY != 0) begin : gen_bram_history
            assign stage2_mem_raw = stage2_bram_raw;
            assign stage3_mem_raw = stage3_bram_raw;

            always @(posedge clk) begin
                stage2_bram_raw <= stage2_hist_bram[stage2_bram_read_addr];
                stage3_bram_raw <= stage3_hist_bram[stage3_bram_read_addr];

                if (rst_n) begin
                    if (stage2_ce_out && stage2_phase == 1'b0)
                        stage2_hist_bram[stage2_write_addr] <= stage2_x_current;
                    if (stage3_ce_out && stage3_phase == 1'b0)
                        stage3_hist_bram[stage3_write_addr] <= stage3_x_current;
                end
            end
        end
        else begin : gen_lutram_history
            assign stage2_mem_raw = stage2_lutram_raw;
            assign stage3_mem_raw = stage3_lutram_raw;

            always @(posedge clk) begin
                if (rst_n) begin
                    if (stage2_ce_out && stage2_phase == 1'b0)
                        stage2_hist_mem[stage2_write_addr] <= stage2_x_current;
                    if (stage3_ce_out && stage3_phase == 1'b0)
                        stage3_hist_mem[stage3_write_addr] <= stage3_x_current;
                end
            end
        end
    endgenerate

    generate
        if (USE_PACKED_BRAM == 0 &&
            USE_BRAM_COEFF != 0 &&
            USE_EXTERNAL_COEFF_BRAM == 0) begin : gen_bram_coeff
            always @(posedge clk) begin
                coeff_bram_raw <= coeff_sequence_bram[coeff_bram_read_addr];
            end
        end
    endgenerate

    always @(posedge clk) begin
        if (!rst_n) begin
            stage2_head <= {MEM_ADDR_W{1'b0}};
            stage3_head <= {MEM_ADDR_W{1'b0}};
            stage2_history_full <= 1'b0;
            stage3_history_full <= 1'b0;
            stage2_phase <= 1'b1;
            stage3_phase <= 1'b1;
            stage2_pending <= 1'b0;
            stage3_pending <= 1'b0;
            stage3_pending_compensated <= 1'b0;
            job_state <= JOB_IDLE;
            job_stage3 <= 1'b0;
            job_phase <= 1'b0;
            job_mac_index <= 4'd0;
            job_history_head <= {MEM_ADDR_W{1'b0}};
            job_history_full <= 1'b0;
            stage2_y_out <= {STAGE2_DATA_W{1'b0}};
            stage3_y_out <= {STAGE3_OUTPUT_W{1'b0}};
            stage2_y_out_valid <= 1'b0;
            stage3_y_out_valid <= 1'b0;
        end
        else begin
            stage2_y_out_valid <= 1'b0;
            stage3_y_out_valid <= 1'b0;

            if (stage2_ce_out) begin
                stage2_pending <= 1'b1;
                if (stage2_phase == 1'b0) begin
                    stage2_head <= stage2_write_addr;
                    if (stage2_head == 4'd8)
                        stage2_history_full <= 1'b1;
                end
                stage2_phase <= ~stage2_phase;
            end

            if (stage3_ce_out) begin
                stage3_pending <= 1'b1;
                stage3_pending_compensated <=
                    stage3_compensated_mode;
                if (stage3_phase == 1'b0) begin
                    stage3_head <= stage3_write_addr;
                    if (stage3_head == 4'd11)
                        stage3_history_full <= 1'b1;
                end
                stage3_phase <= ~stage3_phase;
            end

            if (job_saturation_pending) begin
                if (!job_stage3) begin
                    stage2_y_out <= stage2_q15_rounded;
                    stage2_y_out_valid <= 1'b1;
                end
                else begin
                    stage3_y_out <= stage3_q15_rounded;
                    stage3_y_out_valid <= 1'b1;
                end
                job_state <= JOB_IDLE;
            end
            else if (job_output_pending) begin
                job_state <= JOB_WRITE;
            end
            else if (job_result_pending) begin
                job_state <= JOB_SATURATION;
            end
            else if (job_active) begin
                if (job_mac_index == job_mac_count - 4'd1) begin
                    job_state <= JOB_ROUND;
                    job_mac_index <= 4'd0;
                end
                else begin
                    job_mac_index <= job_mac_index + 4'd1;
                end
            end
            else if (stage2_pending) begin
                job_state <= JOB_MAC;
                job_stage3 <= 1'b0;
                job_phase <= ~stage2_phase;
                job_mac_index <= 4'd0;
                job_history_head <= stage2_head;
                job_history_full <= stage2_history_full;
                stage2_pending <= 1'b0;
            end
            else if (stage3_pending) begin
                job_state <= JOB_MAC;
                job_stage3 <= 1'b1;
                job_phase <= ~stage3_phase;
                job_mac_index <= 4'd0;
                job_history_head <= stage3_head;
                job_history_full <= stage3_history_full;
                stage3_pending <= 1'b0;
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (STAGE2_INPUT_W != STAGE2_DATA_W + INPUT_QUANT_SHIFT ||
            STAGE3_INPUT_W != STAGE3_DATA_W + INPUT_QUANT_SHIFT)
            $fatal(1, "Fused Stage2/3 inputs must retain the two discarded bits");
        if (STAGE2_DATA_W > 24 || STAGE2_DATA_W < STAGE3_DATA_W)
            $fatal(1, "Invalid Stage 2/3 data widths");
        if (STAGE3_OUTPUT_W < STAGE3_DATA_W ||
            STAGE3_OUTPUT_W > STAGE3_DATA_W+1)
            $fatal(1, "Stage3 output must retain input width or one headroom bit");
        if (USE_P3_JOINT_STAGE3 != 0 &&
            (STAGE3_OUTPUT_W != 21 || COEFF_W != 18 ||
             USE_EXTERNAL_COEFF_BRAM == 0))
            $fatal(1, "P3 Stage3 requires 21bit output and external signed18 coefficients");
        if (COEFF_W != 18 && !(STAGE3_FLAT != 0 && COEFF_W == 16))
            $fatal(1, "Stage 2/3 coefficients require 18bit, or 16bit in flat Stage3 mode");
        if (USE_PACKED_BRAM != 0 &&
            (STAGE2_INPUT_W < COEFF_W || STAGE3_INPUT_W < COEFF_W))
            $fatal(1, "Packed BRAM banks must be at least COEFF_W wide");
        if (CIC_ORDER != 3 && CIC_ORDER != 4)
            $fatal(1, "CIC_ORDER must be 3 or 4");
        if (STAGE3_FLAT != 0 && STAGE3_FLAT != 1)
            $fatal(1, "STAGE3_FLAT must be 0 or 1");
        if (USE_BRAM_HISTORY != 0 && USE_BRAM_HISTORY != 1)
            $fatal(1, "USE_BRAM_HISTORY must be 0 or 1");
        if (USE_UNIFIED_BRAM_HISTORY != 0 &&
            USE_UNIFIED_BRAM_HISTORY != 1)
            $fatal(1, "USE_UNIFIED_BRAM_HISTORY must be 0 or 1");
        if (USE_BRAM_COEFF != 0 && USE_BRAM_COEFF != 1)
            $fatal(1, "USE_BRAM_COEFF must be 0 or 1");
        if (ASSUME_ALIGNED_POW2_CE != 0 &&
            ASSUME_ALIGNED_POW2_CE != 1)
            $fatal(1, "ASSUME_ALIGNED_POW2_CE must be 0 or 1");
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (stage2_ce_out && stage2_pending)
                $fatal(1, "Stage 2 LUTRAM pending overwrite");
            if (stage3_ce_out && stage3_pending)
                $fatal(1, "Stage 3 LUTRAM pending overwrite");
            if (USE_UNIFIED_BRAM_HISTORY != 0 &&
                stage3_write_queued &&
                (stage2_history_write_event ||
                 stage3_history_write_event))
                $fatal(1, "Unified Stage2/3 history write queue overflow");
            if (USE_UNIFIED_BRAM_HISTORY != 0 &&
                ASSUME_ALIGNED_POW2_CE != 0 &&
                stage2_history_write_event && stage3_history_write_event)
                $fatal(1, "Aligned Stage2/3 CE assumption violated");
        end
    end
`endif

endmodule
