`timescale 1ns / 1ps

//=============================================================
// 文件名       : interp2_stage23_lutram_cic_dsp_ce.v
// 模块名       : interp2_stage23_lutram_cic_dsp_ce
// 功能简述     : Stage 2/3 共享 DSP 的低 LUT true-polyphase FIR。
//                使用两个 16 深度单读口分布式 RAM 循环缓冲替代
//                历史样点移位寄存器。对称抽头不再并行预加，而是
//                依次送入同一个 DSP48 MAC，以单口 RAM 和更多空闲
//                时钟周期交换更少的 LUT。
//
//                Stage 2：phase0=9 MAC，phase1=8 MAC，Q15
//                Stage 3：phase0=6 MAC，phase1=5 MAC，Q15
//                Stage 3 中心系数 35604 直接使用 18bit signed
//                表示，与 -29932+65536 的 38bit 模运算严格等价。
//
// 当前默认配置：
//                  Stage 2 数据位宽：22bit signed
//                  Stage 3 数据位宽：20bit signed
//                  系数位宽        ：18bit signed Q15
//                  累加位宽        ：38bit signed
//                  历史存储        ：单读口 LUTRAM 循环缓冲
//                  共享 DSP 数量   ：1
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-18
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-18：新增 Stage 2/3 LUTRAM 低 LUT 候选。
//                2026-07-18：串行 MAC 调度改为 Stage 2 优先，保证
//                            4x 样点在下一次 8x CE 前完成。
//                2026-07-18：增加可选双口 BRAM 历史缓存；采用任务
//                            启动预取，保持串行 MAC 周期数不变。
//                2026-07-18：增加可选顺序系数 BRAM，展开对称系数
//                            并与历史样点同拍预取。
//                2026-07-18：增加 Stage2/3 历史与交叉级系数 BRAM
//                            打包候选，复用两块存储银行的读端口。
//=============================================================

`include "all2x_v2_coeff_pkg.vh"

module interp2_stage23_lutram_cic_dsp_ce #(
    parameter integer DATA_W = 24,
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
    input  wire signed [STAGE2_DATA_W-1:0]   stage2_x_in,
    input  wire                              stage2_x_in_valid,
    output reg  signed [STAGE2_DATA_W-1:0]   stage2_y_out,
    output reg                               stage2_y_out_valid,

    input  wire                              stage3_ce_out,
    input  wire signed [STAGE3_DATA_W-1:0]   stage3_x_in,
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
    localparam integer SHIFT_W = ACC_W - FRAC_W;
    localparam integer STAGE2_UPPER_W = SHIFT_W - STAGE2_DATA_W;
    localparam integer STAGE3_UPPER_W = SHIFT_W - STAGE3_OUTPUT_W;
    localparam integer PATTERN_SAT_SUPPORTED =
        ((STAGE2_DATA_W == 22 || STAGE2_DATA_W == 20) &&
         STAGE3_OUTPUT_W == 21);
    // DSP48 MASK位为1表示忽略。22/21位配置检查P[47:36]；20/21位配置
    // 检查P[47:35]，同时覆盖Stage2有符号20位和Stage3有符号21位扩展。
    localparam [47:0] SATURATION_PATTERN_MASK =
        (STAGE2_DATA_W == 20) ? 48'h0007FFFFFFFF :
                               48'h000FFFFFFFFF;
    localparam signed [STAGE2_DATA_W-1:0] STAGE2_OUT_MAX =
        {1'b0, {(STAGE2_DATA_W-1){1'b1}}};
    localparam signed [STAGE2_DATA_W-1:0] STAGE2_OUT_MIN =
        {1'b1, {(STAGE2_DATA_W-1){1'b0}}};
    localparam signed [STAGE3_OUTPUT_W-1:0] STAGE3_OUT_MAX =
        {1'b0, {(STAGE3_OUTPUT_W-1){1'b1}}};
    localparam signed [STAGE3_OUTPUT_W-1:0] STAGE3_OUT_MIN =
        {1'b1, {(STAGE3_OUTPUT_W-1){1'b0}}};

    (* ram_style = "distributed" *)
    reg signed [STAGE2_DATA_W-1:0] stage2_hist_mem [0:MEM_DEPTH-1];
    (* ram_style = "distributed" *)
    reg signed [STAGE3_DATA_W-1:0] stage3_hist_mem [0:MEM_DEPTH-1];
    (* ram_style = "block" *)
    reg signed [STAGE2_DATA_W-1:0] stage2_hist_bram [0:MEM_DEPTH-1];
    (* ram_style = "block" *)
    reg signed [STAGE3_DATA_W-1:0] stage3_hist_bram [0:MEM_DEPTH-1];

    reg [MEM_ADDR_W-1:0] stage2_head;
    reg [MEM_ADDR_W-1:0] stage3_head;
    // 每接收一个历史样本，环形头指针从0向后递减；短FIR历史写满前，
    // 其补码幅值即填充深度，写满后只需一个粘滞full标志。
    reg stage2_history_full;
    reg stage3_history_full;

    reg stage2_phase;
    reg stage3_phase;
    reg stage2_pending;
    reg stage3_pending;
    reg stage3_pending_compensated;

    reg job_active;
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
    // 打包模式下，Stage2 银行保存 Stage2 历史和 Stage3 系数，
    // Stage3 银行保存 Stage3 历史和 Stage2 系数。两级任务不会并行，
    // 因而每拍每个银行只需要一次读和一次可选写。
    (* ram_style = "block" *)
    reg signed [STAGE2_DATA_W-1:0] stage2_packed_bram [0:63];
    (* ram_style = "block" *)
    reg signed [STAGE3_DATA_W-1:0] stage3_packed_bram [0:63];

    reg signed [COEFF_W-1:0] coeff_bram_raw;
    reg job_result_pending;
    reg job_output_pending;
    reg job_saturation_pending;

    wire [MEM_ADDR_W-1:0] stage2_write_addr;
    wire [MEM_ADDR_W-1:0] stage3_write_addr;
    wire [MEM_ADDR_W-1:0] history_read_head;
    wire [MEM_ADDR_W-1:0] stage2_read_addr;
    wire [MEM_ADDR_W-1:0] stage3_read_addr;
    wire [MEM_ADDR_W-1:0] stage2_bram_read_index;
    wire [MEM_ADDR_W-1:0] stage3_bram_read_index;
    wire [MEM_ADDR_W-1:0] stage2_bram_read_addr;
    wire [MEM_ADDR_W-1:0] stage3_bram_read_addr;

    wire signed [STAGE2_DATA_W-1:0] stage2_x_current;
    wire signed [STAGE3_DATA_W-1:0] stage3_x_current;
    wire signed [STAGE2_DATA_W-1:0] stage2_lutram_raw;
    wire signed [STAGE3_DATA_W-1:0] stage3_lutram_raw;
    reg signed [STAGE2_DATA_W-1:0] stage2_bram_raw;
    reg signed [STAGE3_DATA_W-1:0] stage3_bram_raw;
    wire signed [STAGE2_DATA_W-1:0] stage23_unified_bram_raw;
    reg stage3_write_queued;
    reg [MEM_ADDR_W-1:0] stage3_queued_write_addr;
    reg signed [STAGE3_DATA_W-1:0] stage3_queued_write_data;
    reg signed [STAGE2_DATA_W-1:0] stage2_packed_raw;
    reg signed [STAGE3_DATA_W-1:0] stage3_packed_raw;
    wire signed [STAGE2_DATA_W-1:0] stage2_mem_raw;
    wire signed [STAGE3_DATA_W-1:0] stage3_mem_raw;
    wire signed [STAGE2_DATA_W-1:0] stage2_mem;
    wire signed [STAGE3_DATA_W-1:0] stage3_mem;
    wire signed [STAGE2_DATA_W-1:0] selected_sample;
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
    wire signed [STAGE2_DATA_W-1:0] unified_write_data;

    integer coeff_init_idx;
    integer coeff_sequence_init_idx;
    integer packed_init_idx;



    assign stage2_x_current = stage2_x_in_valid ?
                              stage2_x_in : {STAGE2_DATA_W{1'b0}};
    assign stage3_x_current = stage3_x_in_valid ?
                              stage3_x_in : {STAGE3_DATA_W{1'b0}};

    assign stage2_write_addr = stage2_head - {{(MEM_ADDR_W-1){1'b0}}, 1'b1};
    assign stage3_write_addr = stage3_head - {{(MEM_ADDR_W-1){1'b0}}, 1'b1};
    // 共享MAC每次只能访问一个历史bank，因此一次任务期间用单个锁存头指针
    // 服务所选bank；空闲时同一地址路径预取下一优先级任务的索引0。
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
    // 地址 0～15 保存历史；16～31 和 32～47 分别保存两相系数。
    assign packed_coeff_read_addr = {coeff_bram_phase,
                                     ~coeff_bram_phase,
                                     coeff_bram_next_index};

    assign stage2_read_addr = history_read_head + hist_index;
    assign stage3_read_addr = history_read_head + hist_index;

    // BRAM 为同步读。任务空闲且 pending 时读取 index0；任务活动时，
    // 在当前抽头进入 DSP 的同时预取下一个抽头，避免额外空拍。
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
        {{(STAGE2_DATA_W-STAGE3_DATA_W){
            stage3_queued_write_data[STAGE3_DATA_W-1]}},
         stage3_queued_write_data} :
        (stage2_history_write_event ? stage2_x_current :
         {{(STAGE2_DATA_W-STAGE3_DATA_W){
            stage3_x_current[STAGE3_DATA_W-1]}}, stage3_x_current});

    assign stage2_lutram_raw = stage2_hist_mem[stage2_read_addr];
    assign stage3_lutram_raw = stage3_hist_mem[stage3_read_addr];

    // 不使用DATA_W位Fabric MUX把未读BRAM历史替换为0；启动期无效抽头改为
    // 禁止DSP48 P寄存器，严格等价于累加零乘积并保持运行和不变。这样无需
    // 清空BRAM数组，也能保证任意复位时刻后的恢复行为。
    assign stage2_mem = stage2_mem_raw;
    assign stage3_mem = stage3_mem_raw;

    assign selected_sample = !job_stage3 ? stage2_mem :
        {{(STAGE2_DATA_W-STAGE3_DATA_W){stage3_mem[STAGE3_DATA_W-1]}},
         stage3_mem};
    assign dsp_input_a =
        {{(30-STAGE2_DATA_W){selected_sample[STAGE2_DATA_W-1]}},
         selected_sample};
    assign dsp_input_d = 25'sd0;
    assign packed_coeff_raw = coeff_bram_stage3 ?
        stage2_packed_raw[COEFF_W-1:0] :
        stage3_packed_raw[COEFF_W-1:0];
    assign dsp_coeff_b = (USE_EXTERNAL_COEFF_BRAM != 0) ?
        external_coeff_data :
        ((USE_PACKED_BRAM != 0) ? packed_coeff_raw :
         ((USE_BRAM_COEFF != 0) ? coeff_bram_raw : coeff_comb));
    // 接收新任务时同步清零PREG，之后每个MAC周期由它反馈DSP48 ALU的Z输入。
    // 最后一次MAC后，利用一个空闲周期在同一DSP内加入精确有符号Q15偏置：
    // 非负和加16384，负和加16383；第二个空闲周期用PATTERNDETECT保留范围内
    // 结果，或在需要饱和时通过C输入装入精确有符号极限。
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

    // 显式使用一颗 DSP48E1，避免综合器把乘法和累加拆成多颗 DSP。
    // MAC 周期用 M+P，提交周期用 P+C 加入符号相关舍入偏置。
    DSP48E1 #(
        .A_INPUT("DIRECT"),
        .B_INPUT("DIRECT"),
        .USE_DPORT("FALSE"),
        .USE_MULT("MULTIPLY"),
        .USE_PATTERN_DETECT("PATDET"),
        .SEL_MASK("MASK"),
        .SEL_PATTERN("PATTERN"),
        .MASK(SATURATION_PATTERN_MASK),
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
        .INMODE(5'b00000),
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

    // PREG已获得精确有符号舍入偏置；PATTERNDETECT可精确覆盖22/21位签核
    // 配置及20/21位候选配置，其它合法参数组合保留通用Fabric比较分支。
    assign truncated_value = mac_sum_comb >>> FRAC_W;

    assign stage2_upper_is_sign_extension =
        PATTERN_SAT_SUPPORTED ?
        (mac_sum_comb[STAGE2_DATA_W+FRAC_W-1] ?
         dsp_pattern_ones : dsp_pattern_zero) :
        (truncated_value[SHIFT_W-1:STAGE2_DATA_W] ==
         {STAGE2_UPPER_W{truncated_value[STAGE2_DATA_W-1]}});
    assign stage2_q15_rounded =
        truncated_value[STAGE2_DATA_W-1:0];

    // 全国赛Stage3系数为真实Q15值，其最坏绝对支路和已不能保证原35位直接
    // 切片安全，因此必须保留完整38位观察范围及精确有符号饱和。
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
                {STAGE2_DATA_W{1'b0}};
            stage3_packed_bram[packed_init_idx] =
                {STAGE3_DATA_W{1'b0}};
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
            // 全国赛独立 8x 输出使用原 Phase 6 平坦 Stage3。
            // CIC 的通带下垂由后接三抽头移位加法器单独补偿。
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

        // Stage2 系数写入 Stage3 银行，Stage3 系数写入 Stage2 银行。
        // 赋值到更宽的 signed 元素时自动执行符号扩展。
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

    // 两种 RAM 都不复位全阵列。复位时清空已写深度计数，读出端会
    // 屏蔽尚未重写的槽位，因此外部行为等价于历史数组清零。
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
                stage23_unified_bram_raw[STAGE3_DATA_W-1:0];

            nf_stage23_history_ramb18_sdp #(
                .DATA_W(STAGE2_DATA_W),
                .ADDR_W(MEM_ADDR_W+1)
            ) u_nf_stage23_history_ramb18_sdp (
                .clk(clk),
                .read_addr(unified_read_addr),
                .read_data(stage23_unified_bram_raw),
                .write_enable(unified_write_enable),
                .write_addr(unified_write_addr),
                .write_data(unified_write_data)
            );

    // 通用调用者保留一级碰撞队列。全国赛签核CE调度约束更强：ce4与ce8
    // 是对齐的二次幂节拍，两相位复位为1，每次CE重合时写相位必然相反；
    // 启用该假设可删除正常运行下不可达的25位队列。
            if (ASSUME_ALIGNED_POW2_CE == 0) begin : gen_write_queue
                always @(posedge clk) begin
                    if (!rst_n) begin
                        stage3_write_queued <= 1'b0;
                        stage3_queued_write_addr <= {MEM_ADDR_W{1'b0}};
                        stage3_queued_write_data <=
                            {STAGE3_DATA_W{1'b0}};
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
            job_active <= 1'b0;
            job_stage3 <= 1'b0;
            job_phase <= 1'b0;
            job_mac_index <= 4'd0;
            job_history_head <= {MEM_ADDR_W{1'b0}};
            job_history_full <= 1'b0;
            job_result_pending <= 1'b0;
            job_output_pending <= 1'b0;
            job_saturation_pending <= 1'b0;
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
                job_saturation_pending <= 1'b0;
            end
            else if (job_output_pending) begin
                job_output_pending <= 1'b0;
                job_saturation_pending <= 1'b1;
            end
            else if (job_result_pending) begin
                job_result_pending <= 1'b0;
                job_output_pending <= 1'b1;
            end
            else if (job_active) begin
                if (job_mac_index == job_mac_count - 4'd1) begin
                    job_active <= 1'b0;
                    job_result_pending <= 1'b1;
                    job_mac_index <= 4'd0;
                end
                else begin
                    job_mac_index <= job_mac_index + 4'd1;
                end
            end
            else if (stage2_pending) begin
                job_active <= 1'b1;
                job_stage3 <= 1'b0;
                job_phase <= ~stage2_phase;
                job_mac_index <= 4'd0;
                job_history_head <= stage2_head;
                job_history_full <= stage2_history_full;
                stage2_pending <= 1'b0;
            end
            else if (stage3_pending) begin
                job_active <= 1'b1;
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
            (STAGE2_DATA_W < COEFF_W || STAGE3_DATA_W < COEFF_W))
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
