`timescale 1ns / 1ps

`include "../all2x_v3/all2x_v3_stage1_coeff_pkg.vh"

// =============================================================================
// 模块名称：interp2_stage1_single_bram_serial_ce
// 功    能：全国总决赛插值链第1级2倍插值FIR，使用单个64×24 RAMB18E1保存历史样本。
//
// 设计目标：
//   1. 与原双RAM、并行读取结构保持逐样本位真一致；
//   2. 将Stage1历史存储由两个RAMB18E1缩减为一个RAMB18E1；
//   3. 复用一颗DSP48E1完成对称预加、乘法、累加、Q15舍入及输出饱和；
//   4. 利用相邻ce_out脉冲之间的64个系统时钟完成串行计算，降低LUT、FF和BRAM消耗。
//
// 串行读取顺序：
//   L0,R0,L1,R1,...,L25,R25，共26组对称样本、52次RAM读取。
//   每读到一个左样本Lk，先将其装入DSP48E1内部AREG；下一拍读到右样本Rk，
//   DSP48E1内部预加器计算Lk+Rk，再与第k个系数相乘并累加到PREG。
//
// 当前输入样本处理：
//   phase=0到来时，当前输入先写入wr_ptr指向的RAM地址；随后立即从同一地址同步读回，
//   作为L0参与计算。这样不需要在Fabric中增加24-bit“当前输入旁路”寄存器和选择器。
//
// 历史有效性处理：
//   环形RAM尚未填满时，部分左右历史地址还没有有效样本。控制器为每次读取生成mask，
//   在DSP预加模式下利用INMODE直接屏蔽无效的AREG或D端口操作数，避免额外24-bit掩码逻辑。
//
// P3-T资源优化：
//   - 串行计算期间wr_ptr保持稳定，因此直接用wr_ptr-1派生本轮历史基址，删除6-bit base_ptr；
//   - MAC结束后的空闲尾周期由同一DSP执行Q15舍入、符号扩展检测和饱和极值装载，
//     删除Fabric中的宽位溢出比较器和宽饱和选择器；
//   - 全国赛固定参数为DATA_W=24、ACC_W=41、FRAC_W=15；其他参数组合继续使用通用回退逻辑。
//
// 输出相位：
//   phase=0输出半带滤波器的纯延迟支路样本，同时写入一个新输入并启动串行MAC；
//   phase=1输出奇相滤波支路结果。y_out_valid只由ce_out节拍产生，内部多拍运算不改变采样率。
// =============================================================================
module interp2_stage1_single_bram_serial_ce #(
    // 数据通路参数。全国赛正式配置为24-bit输入、41-bit累加器和Q15系数。
    parameter integer DATA_W      = 24,
    parameter integer COEFF_W     = `V3_S1_COEFF_W,
    parameter integer ACC_W       = `V3_S1_ACC_W,
    parameter integer FRAC_W      = `V3_S1_FRAC_W,
    parameter integer HISTORY_LEN = `V3_S1_HISTORY_LEN,
    parameter integer PAIR_COUNT  = `V3_S1_PAIR_COUNT,
    parameter integer DELAY_INDEX = `V3_S1_DELAY_INDEX,
    parameter integer USE_DSP48_PREADDER = 0,
    parameter integer USE_EXTERNAL_COEFF_BRAM = 0
)(
    // 时钟与复位：所有内部状态均工作在clk域，rst_n为低有效同步逻辑复位输入。
    input  wire                         clk,
    input  wire                         rst_n,
    // ce_out：Stage1输出节拍使能；相邻脉冲间隔为串行52次读和26次MAC提供时间预算。
    input  wire                         ce_out,
    // 输入样本及有效标志。无效输入按0处理，但仍保持既定相位和输出节拍。
    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,
    // 2倍插值输出及其有效标志。
    output reg  signed [DATA_W-1:0]     y_out,
    output reg                          y_out_valid,
    // 调试接口：观察当前输出相位、实际送入FIR的样本以及对应有效时刻。
    output reg                          phase_dbg,
    output wire signed [DATA_W-1:0]     fir_in_dbg,
    output wire                         fir_in_valid_dbg,
    output wire [4:0]                   external_coeff_addr,
    input  wire signed [15:0]           external_coeff_data
);

    // -------------------------------------------------------------------------
    // 固定宽度、读取类型与饱和边界
    // -------------------------------------------------------------------------
    localparam integer ADDR_W = 6;
    localparam integer PAIR_W = DATA_W + 1;
    localparam integer QUOT_W = ACC_W - FRAC_W;
    localparam integer UPPER_W = QUOT_W - DATA_W;
    // DSP48 Pattern饱和只针对已完成完整验证的全国赛24/41/Q15参数组合启用。
    // 其他参数组合仍使用后面的Fabric通用比较与饱和路径，保证模块可复用性。
    localparam integer PATTERN_SAT_SUPPORTED =
        (DATA_W == 24 && ACC_W == 41 && FRAC_W == 15);
    // RAM返回数据的用途标签：对称左样本、对称右样本或偶相纯延迟支路样本。
    localparam [1:0] READ_LEFT  = 2'd0;
    localparam [1:0] READ_RIGHT = 2'd1;
    localparam [1:0] READ_DELAY = 2'd2;
    localparam signed [DATA_W-1:0] OUT_MAX =
        {1'b0, {(DATA_W-1){1'b1}}};
    localparam signed [DATA_W-1:0] OUT_MIN =
        {1'b1, {(DATA_W-1){1'b0}}};

    // -------------------------------------------------------------------------
    // 单RAMB18E1历史存储状态
    // -------------------------------------------------------------------------
    reg [ADDR_W-1:0] read_addr;
    wire signed [DATA_W-1:0] read_data;
    reg [ADDR_W-1:0] wr_ptr;
    wire [ADDR_W-1:0] history_base_ptr;
    // 第一次回绕前，wr_ptr的数值同时等于已初始化历史样本数量，可以直接用于有效性判断。
    // 当52个历史位置全部写过后，history_full置1并保持，避免另设宽位填充计数器。
    // 该“写指针+粘滞满标志”组合取代了两个6-bit历史深度计数器。
    reg history_full;

    // -------------------------------------------------------------------------
    // 输出相位和串行MAC调度状态
    // -------------------------------------------------------------------------
    // phase_cnt=0：偶相纯延迟输出并启动新一轮MAC；phase_cnt=1：输出滤波支路。
    reg phase_cnt;
    // mac_active主要用于仿真截止时间断言；issue_active控制是否继续签发RAM读取。
    reg mac_active;
    // filter_ready/delay_ready分别表示奇相滤波结果和偶相延迟样本已经准备完成。
    reg filter_ready;
    reg delay_ready;
    reg issue_active;
    reg next_issue_is_left;
    // schedule_index范围0~25，对应26组对称样本和26个非零半带系数。
    reg [4:0] schedule_index;

    // -------------------------------------------------------------------------
    // 同步RAM读取请求及其一级元数据流水
    // -------------------------------------------------------------------------
    // read_issue_*描述本拍发出的地址；read_*在下一拍与RAM输出数据严格对齐。
    reg read_issue_valid;
    reg [1:0] read_issue_kind;
    reg read_issue_mask;
    reg [4:0] issue_index;
    reg read_data_valid;
    reg [1:0] read_kind;
    reg read_mask;
    reg [4:0] read_coeff_index;

    // left_sample/left_mask只服务于关闭DSP预加器的兼容配置。
    // 正式全国赛配置将左操作数保存在DSP48E1内部AREG，不消耗24-bit Fabric寄存器。
    reg signed [DATA_W-1:0] left_sample;
    reg left_mask;
    // delay_result保存半带FIR偶相的纯延迟支路样本。
    reg signed [DATA_W-1:0] delay_result;
    // 两个pending标志构成MAC后的尾处理流水：先舍入，再检测并在必要时装载饱和值。
    reg filter_commit_pending;
    reg filter_saturation_pending;

    // -------------------------------------------------------------------------
    // FIR、DSP48E1及舍入饱和组合信号
    // -------------------------------------------------------------------------
    wire signed [DATA_W-1:0] x_current;
    reg signed [PAIR_W-1:0] pair_sum_comb;
    reg signed [COEFF_W-1:0] coeff_comb;
    wire signed [24:0] dsp_preadd_a;
    wire signed [24:0] dsp_preadd_d;
    wire signed [29:0] dsp_input_a;
    wire signed [17:0] dsp_coeff_b;
    wire signed [47:0] dsp_mac_full;
    wire signed [ACC_W-1:0] mac_sum_comb;
    wire signed [DATA_W-1:0] filter_rounded;
    wire [4:0] dsp_inmode;
    wire dsp_p_reset;
    wire dsp_p_ce;
    wire [6:0] dsp_opmode;
    wire signed [47:0] dsp_round_bias;
    wire signed [47:0] dsp_c_input;
    wire signed [47:0] dsp_saturation_value;
    wire signed [47:0] output_max_scaled;
    wire signed [47:0] output_min_scaled;
    wire dsp_round_carryin;
    wire dsp_pattern_zero;
    wire dsp_pattern_ones;
    wire signed [QUOT_W-1:0] rounded_quotient;
    wire rounded_upper_is_sign_extension;

    // 无效输入以0进入滤波器，避免X传播，同时保持固定输出节拍。
    assign x_current = x_in_valid ? x_in : {DATA_W{1'b0}};
    // phase=0写入当前样本后wr_ptr递增，并在整轮串行计算期间保持稳定。
    // 因此wr_ptr的前一个地址就是本轮最新历史样本位置，严格等价于旧版保存的6-bit base_ptr。
    // 6-bit减法按模64自然回绕，wr_ptr=0时结果为63，符合环形RAM寻址规则。
    assign history_base_ptr = wr_ptr - {{(ADDR_W-1){1'b0}}, 1'b1};
    assign fir_in_dbg = x_current;
    assign fir_in_valid_dbg = ce_out && (phase_cnt == 1'b0);
    assign external_coeff_addr = issue_index;

    // 64×24简单双口RAM：A侧同步读，B侧在phase=0时写入当前输入。
    // 物理实现固定为一个RAMB18E1；同址写后读行为已由原语级测试验证。
    nf_stage1_history_ramb18_sdp #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W)
    ) u_nf_stage1_history_ramb18_sdp (
        .clk(clk),
        .read_addr(read_addr),
        .read_data(read_data),
        .write_enable(rst_n && ce_out && phase_cnt == 1'b0),
        .write_addr(wr_ptr),
        .write_data(x_current)
    );

    // -------------------------------------------------------------------------
    // DSP48E1输入整理与预加器控制
    // -------------------------------------------------------------------------
    // DSP48E1的A/D预加器端口宽度为25 bit，24-bit样本在此进行符号扩展。
    assign dsp_preadd_a =
        {{(25-DATA_W){read_data[DATA_W-1]}}, read_data};
    assign dsp_preadd_d =
        {{(25-DATA_W){read_data[DATA_W-1]}}, read_data};
    assign dsp_input_a = (USE_DSP48_PREADDER != 0) ?
        {{5{dsp_preadd_a[24]}}, dsp_preadd_a} :
        {{(30-PAIR_W){pair_sum_comb[PAIR_W-1]}}, pair_sum_comb};
    assign dsp_coeff_b =
        {{(18-COEFF_W){coeff_comb[COEFF_W-1]}}, coeff_comb};
    // 预加器模式的操作流程：
    //   READ_LEFT ：左样本装入DSP内部AREG，并保存其有效mask；
    //   READ_RIGHT：右样本由D端口直接进入，DSP计算(A+D)×B并累加到PREG。
    // INMODE[1]用于屏蔽无效的AREG左操作数，INMODE[2]用于屏蔽无效的D端口右操作数。
    // 这样启动填充阶段的无效历史样本在DSP内部被视为0，不需要Fabric宽位与门或选择器。
    assign dsp_inmode = (USE_DSP48_PREADDER != 0) ?
        {2'b00, read_mask, ~left_mask, 1'b0} : 5'b00000;
    // 每次phase=0启动新一轮计算时清零DSP PREG累加状态。
    assign dsp_p_reset = !rst_n || (ce_out && phase_cnt == 1'b0);
    // PREG只在三类时刻更新：右样本MAC、Q15舍入尾拍、以及检测到溢出后的饱和装载尾拍。
    // 未溢出时最后一项CE关闭，PREG继续保留已经舍入完成的正确结果。
    assign dsp_p_ce =
        (read_data_valid && read_kind == READ_RIGHT) ||
        filter_commit_pending ||
        (filter_saturation_pending &&
         !rounded_upper_is_sign_extension);
    // 对称的“最近整数、半值远离零”Q15舍入：
    //   负数加16383；非负数通过CARRYIN再多加1，等效加16384。
    assign dsp_round_bias = 48'sd16383;
    // 将24-bit正/负饱和极值左移FRAC_W，构造成与DSP PREG当前Q15尺度一致的48-bit数值。
    assign output_max_scaled =
        {{(48-DATA_W-FRAC_W){1'b0}},
         1'b0, {(DATA_W-1){1'b1}}, {FRAC_W{1'b0}}};
    assign output_min_scaled =
        {{(48-DATA_W-FRAC_W){1'b1}},
         1'b1, {(DATA_W-1){1'b0}}, {FRAC_W{1'b0}}};
    assign dsp_saturation_value = mac_sum_comb[ACC_W-1] ?
        output_min_scaled : output_max_scaled;
    // 正常舍入尾拍C端口输入舍入偏置；饱和尾拍改为输入对应的正/负极限。
    assign dsp_c_input = filter_saturation_pending ?
        dsp_saturation_value : dsp_round_bias;
    assign dsp_round_carryin =
        filter_commit_pending && !mac_sum_comb[ACC_W-1];
    // OPMODE分为三种：常规乘累加、PREG加舍入偏置、C端口极值装载。
    assign dsp_opmode = filter_saturation_pending ?
        7'b0001100 :
        (filter_commit_pending ? 7'b0001110 : 7'b0100101);

    // -------------------------------------------------------------------------
    // DSP48E1原语
    // -------------------------------------------------------------------------
    // AREG=1保存左样本，PREG=1保存MAC/舍入/饱和最终结果；其余寄存级关闭以节省时序状态。
    // MASK忽略结果低39位，只检查P[47:39]是否全0或全1，即检查24-bit结果在Q15尺度下
    // 是否具有合法符号扩展。PATTERNDETECT表示高位全0，PATTERNBDETECT表示高位全1。
    DSP48E1 #(
        .A_INPUT("DIRECT"), .B_INPUT("DIRECT"),
        .USE_DPORT("TRUE"), .USE_MULT("MULTIPLY"),
        .USE_PATTERN_DETECT("PATDET"),
        .SEL_MASK("MASK"), .SEL_PATTERN("PATTERN"),
        .MASK(48'h007FFFFFFFFF),
        .PATTERN(48'h000000000000),
        .USE_SIMD("ONE48"),
        .AREG((USE_DSP48_PREADDER != 0) ? 1 : 0),
        .ACASCREG((USE_DSP48_PREADDER != 0) ? 1 : 0),
        .BREG(0), .BCASCREG(0), .CREG(0), .DREG(0),
        .ADREG(0), .MREG(0), .PREG(1), .INMODEREG(0),
        .OPMODEREG(0), .ALUMODEREG(0), .CARRYINREG(0),
        .CARRYINSELREG(0)
    ) u_stage1_dsp48e1 (
        .P(dsp_mac_full), .A(dsp_input_a), .B(dsp_coeff_b),
        .C(dsp_c_input),
        .D((USE_DSP48_PREADDER != 0) ? dsp_preadd_d : 25'sd0),
        .INMODE(dsp_inmode), .OPMODE(dsp_opmode),
        .ALUMODE(4'b0000), .CARRYINSEL(3'b000),
        .CARRYIN(dsp_round_carryin),
        .ACIN(30'd0), .BCIN(18'd0), .PCIN(48'd0),
        .CARRYCASCIN(1'b0), .MULTSIGNIN(1'b0), .CLK(clk),
        .CEA1(1'b0),
        .CEA2((USE_DSP48_PREADDER != 0) && read_data_valid &&
              read_kind == READ_LEFT),
        .CEAD(1'b0),
        .CEALUMODE(1'b0), .CEB1(1'b0), .CEB2(1'b0),
        .CEC(1'b0), .CECARRYIN(1'b0), .CECTRL(1'b0),
        .CED(1'b0), .CEINMODE(1'b0), .CEM(1'b0), .CEP(dsp_p_ce),
        .RSTA(!rst_n), .RSTALLCARRYIN(1'b0), .RSTALUMODE(1'b0),
        .RSTB(1'b0), .RSTC(1'b0), .RSTCTRL(1'b0), .RSTD(1'b0),
        .RSTINMODE(1'b0), .RSTM(1'b0), .RSTP(dsp_p_reset),
        .ACOUT(), .BCOUT(), .CARRYCASCOUT(), .CARRYOUT(),
        .MULTSIGNOUT(), .OVERFLOW(),
        .PATTERNBDETECT(dsp_pattern_ones),
        .PATTERNDETECT(dsp_pattern_zero), .PCOUT(), .UNDERFLOW()
    );

    // 全国赛累加器只使用DSP PREG低ACC_W位；其范围已通过定点边界分析和强信号测试验证。
    assign mac_sum_comb = dsp_mac_full[ACC_W-1:0];

    // -------------------------------------------------------------------------
    // 兼容预加路径与系数选择
    // -------------------------------------------------------------------------
    always @(*) begin
        // 仅USE_DSP48_PREADDER=0时使用Fabric计算对称样本和；正式配置不走此数据通路。
        pair_sum_comb =
            $signed({left_sample[DATA_W-1], left_sample}) +
            $signed({(read_mask ? read_data[DATA_W-1] : 1'b0),
                     (read_mask ? read_data : {DATA_W{1'b0}})});

        // 正式工程从统一系数RAMB18读取16-bit系数；关闭外部系数RAM时使用宏定义常量表。
        if (USE_EXTERNAL_COEFF_BRAM != 0) begin
            coeff_comb = {{(COEFF_W-16){external_coeff_data[15]}},
                          external_coeff_data};
        end
        else begin
            case (read_coeff_index)
                5'd0:  coeff_comb = `V3_S1_C00;
                5'd1:  coeff_comb = `V3_S1_C01;
                5'd2:  coeff_comb = `V3_S1_C02;
                5'd3:  coeff_comb = `V3_S1_C03;
                5'd4:  coeff_comb = `V3_S1_C04;
                5'd5:  coeff_comb = `V3_S1_C05;
                5'd6:  coeff_comb = `V3_S1_C06;
                5'd7:  coeff_comb = `V3_S1_C07;
                5'd8:  coeff_comb = `V3_S1_C08;
                5'd9:  coeff_comb = `V3_S1_C09;
                5'd10: coeff_comb = `V3_S1_C10;
                5'd11: coeff_comb = `V3_S1_C11;
                5'd12: coeff_comb = `V3_S1_C12;
                5'd13: coeff_comb = `V3_S1_C13;
                5'd14: coeff_comb = `V3_S1_C14;
                5'd15: coeff_comb = `V3_S1_C15;
                5'd16: coeff_comb = `V3_S1_C16;
                5'd17: coeff_comb = `V3_S1_C17;
                5'd18: coeff_comb = `V3_S1_C18;
                5'd19: coeff_comb = `V3_S1_C19;
                5'd20: coeff_comb = `V3_S1_C20;
                5'd21: coeff_comb = `V3_S1_C21;
                5'd22: coeff_comb = `V3_S1_C22;
                5'd23: coeff_comb = `V3_S1_C23;
                5'd24: coeff_comb = `V3_S1_C24;
                5'd25: coeff_comb = `V3_S1_C25;
                default: coeff_comb = {COEFF_W{1'b0}};
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Q15舍入、符号扩展检测及饱和输出
    // -------------------------------------------------------------------------
    // filter_commit_pending尾拍完成舍入后，PREG仍保持Q15缩放形式；算术右移FRAC_W得到整数商。
    assign rounded_quotient = mac_sum_comb >>> FRAC_W;
    // 全国赛配置使用DSP Pattern标志判断P[47:39]是否等于结果符号位；
    // 通用配置则显式比较rounded_quotient的高UPPER_W位，二者判定语义完全一致。
    assign rounded_upper_is_sign_extension =
        PATTERN_SAT_SUPPORTED ?
        (rounded_quotient[DATA_W-1] ?
         dsp_pattern_ones : dsp_pattern_zero) :
        (rounded_quotient[QUOT_W-1:DATA_W] ==
         {UPPER_W{rounded_quotient[DATA_W-1]}});
    // 全国赛配置若溢出，DSP已在额外尾拍把正确极值写入PREG，因此这里只需固定截取低DATA_W位。
    // 非全国赛参数组合仍保留显式比较和OUT_MIN/OUT_MAX选择，避免Pattern掩码宽度不适配。
    assign filter_rounded = PATTERN_SAT_SUPPORTED ?
        rounded_quotient[DATA_W-1:0] :
        (rounded_upper_is_sign_extension ?
         rounded_quotient[DATA_W-1:0] :
         (rounded_quotient[QUOT_W-1] ? OUT_MIN : OUT_MAX));

    // -------------------------------------------------------------------------
    // RAM读取元数据流水
    // -------------------------------------------------------------------------
    // RAM为同步读：本拍签发read_addr，下一拍read_data才有效。
    // 因而读取类型、有效mask和系数索引也延迟一拍，与RAM数据和统一系数RAM输出严格对齐。
    always @(posedge clk) begin
        if (!rst_n) begin
            read_data_valid <= 1'b0;
            read_kind <= READ_LEFT;
            read_mask <= 1'b0;
            read_coeff_index <= 5'd0;
        end
        else begin
            read_data_valid <= read_issue_valid;
            if (read_issue_valid) begin
                read_kind <= read_issue_kind;
                read_mask <= read_issue_mask;
                read_coeff_index <= issue_index;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 主控制器：串行读取、MAC尾处理及两相输出
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            // 复位时清空所有可见输出、历史有效状态、调度状态和DSP尾处理标志。
            // RAM内容无需物理清零，启动阶段由read_mask/history_full保证未初始化地址按0使用。
            wr_ptr <= {ADDR_W{1'b0}};
            history_full <= 1'b0;
            phase_cnt <= 1'b1;
            phase_dbg <= 1'b1;
            mac_active <= 1'b0;
            filter_ready <= 1'b0;
            delay_ready <= 1'b0;
            issue_active <= 1'b0;
            next_issue_is_left <= 1'b0;
            schedule_index <= 5'd0;
            read_issue_valid <= 1'b0;
            read_issue_kind <= READ_LEFT;
            read_issue_mask <= 1'b0;
            issue_index <= 5'd0;
            read_addr <= {ADDR_W{1'b0}};
            left_sample <= {DATA_W{1'b0}};
            left_mask <= 1'b0;
            delay_result <= {DATA_W{1'b0}};
            filter_commit_pending <= 1'b0;
            filter_saturation_pending <= 1'b0;
            y_out <= {DATA_W{1'b0}};
            y_out_valid <= 1'b0;
        end
        else begin
            // 默认每拍撤销脉冲型标志；在相应条件满足时于本拍末重新置位。
            y_out_valid <= 1'b0;
            read_issue_valid <= 1'b0;

            // MAC后的两级尾处理：
            //   commit_pending拍：DSP执行精确Q15舍入；
            //   saturation_pending拍：检查Pattern，若溢出则DSP装载极值，随后结果标记为ready。
            // 无论是否溢出都经过相同控制延迟，保证valid相位固定。
            if (filter_saturation_pending) begin
                filter_ready <= 1'b1;
                filter_saturation_pending <= 1'b0;
            end
            else if (filter_commit_pending) begin
                filter_saturation_pending <= 1'b1;
                filter_commit_pending <= 1'b0;
            end

            // 消费上一拍RAM返回的数据及其元数据。
            if (read_data_valid) begin
                if (read_kind == READ_LEFT) begin
                    // 兼容模式保存左样本；预加器模式下实际左样本已由DSP AREG保存。
                    left_sample <= read_mask ? read_data :
                                   {DATA_W{1'b0}};
                    left_mask <= read_mask;
                end
                else if (read_kind == READ_DELAY) begin
                    // 偶相纯延迟支路样本准备完成，等待下一次phase=0输出。
                    delay_result <= read_mask ? read_data :
                                    {DATA_W{1'b0}};
                    delay_ready <= 1'b1;
                end
                else if (read_coeff_index == PAIR_COUNT-1) begin
                    // 最后一组右样本已进入DSP，本轮MAC结束，启动舍入/饱和尾处理。
                    filter_commit_pending <= 1'b1;
                    mac_active <= 1'b0;
                end
            end

            // 每个有效系统时钟签发一次RAM读取，严格按Lk、Rk交替。
            if (issue_active) begin
                read_issue_valid <= 1'b1;
                issue_index <= schedule_index;

                if (next_issue_is_left) begin
                    // 左地址：最新历史基址向旧样本方向回退k个位置。
                    read_issue_kind <= READ_LEFT;
                    read_addr <= history_base_ptr - schedule_index;
                    read_issue_mask <= history_full ||
                                       schedule_index < wr_ptr;
                    next_issue_is_left <= 1'b0;
                end
                else begin
                    // 右地址：读取与左样本关于52-tap冲激响应中心对称的另一端历史样本。
                    read_issue_kind <= READ_RIGHT;
                    read_addr <= history_base_ptr -
                        (HISTORY_LEN-1-schedule_index);
                    read_issue_mask <= history_full ||
                        (HISTORY_LEN-1-schedule_index) < wr_ptr;

                    if (schedule_index == PAIR_COUNT-1) begin
                        // R25已签发，停止继续读；后续由RAM流水和DSP尾处理完成收尾。
                        issue_active <= 1'b0;
                    end
                    else begin
                        schedule_index <= schedule_index + 5'd1;
                        next_issue_is_left <= 1'b1;
                    end
                end
            end

            // ce_out到来时产生一个2倍插值输出，并在偶相/奇相之间切换。
            if (ce_out) begin
                phase_dbg <= phase_cnt;
                y_out_valid <= 1'b1;

                if (phase_cnt == 1'b0) begin
                    // 偶相：输出半带FIR中心抽头对应的纯延迟样本。
                    y_out <= delay_ready ? delay_result :
                             {DATA_W{1'b0}};
                    delay_ready <= 1'b0;

                    // 将当前输入写入环形历史RAM；写指针递增，写满52个位置后history_full保持1。
                    wr_ptr <= wr_ptr + 6'd1;
                    if (wr_ptr == HISTORY_LEN-1)
                        history_full <= 1'b1;

                    // 启动新的26组对称MAC。第一拍直接读取旧wr_ptr地址，即刚写入的当前L0。
                    mac_active <= 1'b1;
                    filter_ready <= 1'b0;
                    issue_active <= 1'b1;
                    next_issue_is_left <= 1'b0;
                    schedule_index <= 5'd0;
                    read_issue_valid <= 1'b1;
                    read_issue_kind <= READ_LEFT;
                    read_issue_mask <= 1'b1;
                    issue_index <= 5'd0;
                    read_addr <= wr_ptr;
                end
                else begin
                    // 奇相：输出已经完成舍入和饱和的滤波支路结果。
                    // 正常运行时filter_ready必须为1；否则输出0并由仿真断言立即报告截止时间错误。
                    y_out <= filter_ready ? filter_rounded :
                             {DATA_W{1'b0}};
                    filter_ready <= 1'b0;

                    // 同时预取下一次偶相需要的中心延迟样本，为下一个phase=0做准备。
                    read_issue_valid <= 1'b1;
                    read_issue_kind <= READ_DELAY;
                    read_issue_mask <= history_full ||
                                       wr_ptr > DELAY_INDEX;
                    issue_index <= 5'd0;
                    read_addr <= wr_ptr - (DELAY_INDEX + 1);
                end

                phase_cnt <= ~phase_cnt;
            end
        end
    end

`ifndef SYNTHESIS
    // -------------------------------------------------------------------------
    // 仅仿真断言：不进入综合网表，不消耗FPGA资源
    // -------------------------------------------------------------------------
    reg input_seen;

    always @(posedge clk) begin
        if (!rst_n) begin
            input_seen <= 1'b0;
        end
        else if (ce_out && phase_cnt == 1'b0) begin
            input_seen <= 1'b1;
            // 新一轮偶相开始时，上一轮串行读取和MAC必须已经完全结束。
            if (mac_active || issue_active)
                $fatal(1, "Stage1 single-BRAM MAC deadline miss");
        end
        else if (ce_out && phase_cnt == 1'b1 && input_seen &&
                 !filter_ready) begin
            // 奇相输出时滤波结果必须ready；该断言直接监控新增DSP尾拍是否超出时间预算。
            $fatal(1, "Stage1 single-BRAM filter result not ready");
        end
    end

    initial begin
        // 当前串行调度固定针对24-bit、52-tap、26组对称乘法；参数不匹配时仿真立即终止。
        if (DATA_W != 24 || HISTORY_LEN != 52 || PAIR_COUNT != 26)
            $fatal(1, "Stage1 single-BRAM schedule requires 24/52/26");
    end
`endif

endmodule
