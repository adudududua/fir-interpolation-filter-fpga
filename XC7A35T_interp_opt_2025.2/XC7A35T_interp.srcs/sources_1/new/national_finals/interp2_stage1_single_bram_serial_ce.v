`timescale 1ns / 1ps

`include "../all2x_v3/all2x_v3_stage1_coeff_pkg.vh"

//=============================================================
// 文件名       : interp2_stage1_single_bram_serial_ce.v
// 模块名       : interp2_stage1_single_bram_serial_ce
// 功能简述     : 第一级 2x 半带 FIR 的单 BRAM 串行抽头微引擎。
//                模块把 26 个对称系数扩展为 52 个顺序系数，写入
//                同一 RAMB18E1 的空闲地址，并按“最新到最旧”顺序
//                每拍读取一个历史样本、完成一次精确乘加。
//
//                  (Lk + Rk) * Ck = Lk*Ck + Rk*Ck
//
//                两种写法在相同二进制补码模累加器中逐位等价。
//                串行抽头方式删除左右地址元数据、第二套地址方程和
//                DSP 预加器控制；中心抽头在扫描过程中同步捕获，
//                不再需要额外的 BRAM 预取周期。
//
// 当前默认配置：
//                  数据宽度 24 bit，累加器 41 bit
//                  历史深度 52，系数小数位 15
//                  正式工程使用外部统一系数 BRAM
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-29
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-29：新增单 BRAM 顺序抽头 Stage1 实现。
//                2026-08-16：补充中文算法、存储和时序说明。
//=============================================================
//=============================================================
// 1）模块名称：interp2_stage1_single_bram_serial_ce
// 功能说明：第一级 2 倍插值滤波器：处理最长抽头滤波并完成定点量化。
// 工程版本：Vivado 2025.2。
//=============================================================

module interp2_stage1_single_bram_serial_ce #(
    parameter integer DATA_W      = 24,
    parameter integer COEFF_W     = `V3_S1_COEFF_W,
    parameter integer ACC_W       = `V3_S1_ACC_W,
    parameter integer FRAC_W      = `V3_S1_FRAC_W,
    parameter integer HISTORY_LEN = `V3_S1_HISTORY_LEN,
    parameter integer PAIR_COUNT  = `V3_S1_PAIR_COUNT,
    parameter integer DELAY_INDEX = `V3_S1_DELAY_INDEX,
    // 保留该参数以兼容既有例化接口。顺序抽头模式有意直接使用乘法器，
    // 不启用DSP预加器；参数仅用于保持源代码配置的一致性。
    parameter integer USE_DSP48_PREADDER = 0,
    parameter integer USE_EXTERNAL_COEFF_BRAM = 0
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ce_out,
    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,
    output reg  signed [DATA_W-1:0]     y_out,
    output reg                          y_out_valid,
    output reg                          phase_dbg,
    output wire signed [DATA_W-1:0]     fir_in_dbg,
    output wire                         fir_in_valid_dbg,
    output wire [5:0]                   external_coeff_addr,
    input  wire signed [15:0]           external_coeff_data
);

    localparam integer ADDR_W = 6;
    localparam integer INDEX_W = 6;
    localparam integer QUOT_W = ACC_W - FRAC_W;
    localparam integer UPPER_W = QUOT_W - DATA_W;
    localparam integer PATTERN_SAT_SUPPORTED =
        (DATA_W == 24 && ACC_W == 41 && FRAC_W == 15);
    localparam signed [DATA_W-1:0] OUT_MAX =
        {1'b0, {(DATA_W-1){1'b1}}};
    localparam signed [DATA_W-1:0] OUT_MIN =
        {1'b1, {(DATA_W-1){1'b0}}};

    reg [ADDR_W-1:0] read_addr;
    wire signed [DATA_W-1:0] read_data;
    reg [ADDR_W-1:0] wr_ptr;
    reg history_full;

    reg phase_cnt;
    // 保留mac_active作为复位/截止周期回归可观察的调度镜像；实际功能控制
    // 使用issue_active及流水尾部标志，不依赖该观测状态。
    reg mac_active;
`ifndef SYNTHESIS
    // 仅在仿真中保留固定延迟调度镜像，供截止周期断言使用。硬件输出路径
    // 无需冗余ready状态，因为52次读取及2个DSP尾部周期必在下一奇相前结束。
    reg filter_ready;
`endif
    reg scan_exhausted;

    reg read_issue_valid;
    reg read_issue_mask;
    reg [INDEX_W-1:0] issue_index;
    reg issue_active;
    reg read_data_valid;
    reg read_mask;
    reg [INDEX_W-1:0] read_coeff_index;

    reg signed [DATA_W-1:0] delay_result;
    reg filter_commit_pending;
    reg filter_saturation_pending;

    wire signed [DATA_W-1:0] x_current;
    wire [INDEX_W-1:0] mirrored_coeff_index;
    reg signed [COEFF_W-1:0] coeff_comb;
    wire signed [29:0] dsp_input_a;
    wire signed [17:0] dsp_coeff_b;
    wire signed [47:0] dsp_mac_full;
    wire signed [ACC_W-1:0] mac_sum_comb;
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
    wire signed [DATA_W-1:0] filter_rounded;

    assign x_current = x_in_valid ? x_in : {DATA_W{1'b0}};
    assign fir_in_dbg = x_current;
    assign fir_in_valid_dbg = ce_out && phase_cnt == 1'b0;
    assign external_coeff_addr = issue_index;

    // Stage1历史样本存储：单块RAMB18E1简单双口包装器，读口服务串行MAC，
    // 写口仅在偶相输入有效节拍更新环形历史。
    // 例化说明：调用 nf_stage1_history_ramb18_sdp 全国赛签核子模块，完成正式数据通路中的存储、运算或控制任务。
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

    // 内部系数表仅用于独立测试兼容；板级正式构建会常量折叠该分支，并从
    // 统一系数BRAM读取按MAC次序展开后的Stage1系数。
    assign mirrored_coeff_index =
        (read_coeff_index < PAIR_COUNT) ? read_coeff_index :
        (HISTORY_LEN-1-read_coeff_index);

    always @(*) begin
        case (mirrored_coeff_index[4:0])
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

    assign dsp_input_a =
        {{(30-DATA_W){read_data[DATA_W-1]}}, read_data};
    assign dsp_coeff_b = (USE_EXTERNAL_COEFF_BRAM != 0) ?
        {{2{external_coeff_data[15]}}, external_coeff_data} :
        {{(18-COEFF_W){coeff_comb[COEFF_W-1]}}, coeff_comb};

    assign dsp_p_reset = !rst_n || (ce_out && phase_cnt == 1'b0);
    assign dsp_p_ce =
        (read_data_valid && read_mask) ||
        filter_commit_pending ||
        (filter_saturation_pending &&
         !rounded_upper_is_sign_extension);
    assign dsp_round_bias = 48'sd16383;
    assign output_max_scaled =
        {{(48-DATA_W-FRAC_W){1'b0}},
         1'b0, {(DATA_W-1){1'b1}}, {FRAC_W{1'b0}}};
    assign output_min_scaled =
        {{(48-DATA_W-FRAC_W){1'b1}},
         1'b1, {(DATA_W-1){1'b0}}, {FRAC_W{1'b0}}};
    assign dsp_saturation_value = mac_sum_comb[ACC_W-1] ?
        output_min_scaled : output_max_scaled;
    assign dsp_c_input = filter_saturation_pending ?
        dsp_saturation_value : dsp_round_bias;
    assign dsp_round_carryin =
        filter_commit_pending && !mac_sum_comb[ACC_W-1];
    assign dsp_opmode = filter_saturation_pending ?
        7'b0001100 :
        (filter_commit_pending ? 7'b0001110 : 7'b0100101);

    // 例化说明：调用 DSP48E1 算术原语，完成乘法、加减或累加；各控制字定义当前流水拍的运算功能。
    DSP48E1 #(
        .A_INPUT("DIRECT"), .B_INPUT("DIRECT"),
        .USE_DPORT("FALSE"), .USE_MULT("MULTIPLY"),
        .USE_PATTERN_DETECT("PATDET"),
        .SEL_MASK("MASK"), .SEL_PATTERN("PATTERN"),
        .MASK(48'h007FFFFFFFFF),
        .PATTERN(48'h000000000000),
        .USE_SIMD("ONE48"),
        .AREG(0), .ACASCREG(0), .BREG(0), .BCASCREG(0),
        .CREG(0), .DREG(0), .ADREG(0), .MREG(0), .PREG(1),
        .INMODEREG(0), .OPMODEREG(0), .ALUMODEREG(0),
        .CARRYINREG(0), .CARRYINSELREG(0)
    ) u_stage1_dsp48e1 (
        .P(dsp_mac_full), .A(dsp_input_a), .B(dsp_coeff_b),
        .C(dsp_c_input), .D(25'sd0),
        .INMODE(5'b00000), .OPMODE(dsp_opmode),
        .ALUMODE(4'b0000), .CARRYINSEL(3'b000),
        .CARRYIN(dsp_round_carryin),
        .ACIN(30'd0), .BCIN(18'd0), .PCIN(48'd0),
        .CARRYCASCIN(1'b0), .MULTSIGNIN(1'b0), .CLK(clk),
        .CEA1(1'b0), .CEA2(1'b0), .CEAD(1'b0),
        .CEALUMODE(1'b0), .CEB1(1'b0), .CEB2(1'b0),
        .CEC(1'b0), .CECARRYIN(1'b0), .CECTRL(1'b0),
        .CED(1'b0), .CEINMODE(1'b0), .CEM(1'b0), .CEP(dsp_p_ce),
        .RSTA(1'b0), .RSTALLCARRYIN(1'b0), .RSTALUMODE(1'b0),
        .RSTB(1'b0), .RSTC(1'b0), .RSTCTRL(1'b0), .RSTD(1'b0),
        .RSTINMODE(1'b0), .RSTM(1'b0), .RSTP(dsp_p_reset),
        .ACOUT(), .BCOUT(), .CARRYCASCOUT(), .CARRYOUT(),
        .MULTSIGNOUT(), .OVERFLOW(),
        .PATTERNBDETECT(dsp_pattern_ones),
        .PATTERNDETECT(dsp_pattern_zero), .PCOUT(), .UNDERFLOW()
    );

    assign mac_sum_comb = dsp_mac_full[ACC_W-1:0];
    assign rounded_quotient = mac_sum_comb >>> FRAC_W;
    assign rounded_upper_is_sign_extension =
        PATTERN_SAT_SUPPORTED ?
        (rounded_quotient[DATA_W-1] ?
         dsp_pattern_ones : dsp_pattern_zero) :
        (rounded_quotient[QUOT_W-1:DATA_W] ==
         {UPPER_W{rounded_quotient[DATA_W-1]}});
    assign filter_rounded = PATTERN_SAT_SUPPORTED ?
        rounded_quotient[DATA_W-1:0] :
        (rounded_upper_is_sign_extension ?
         rounded_quotient[DATA_W-1:0] :
         (rounded_quotient[QUOT_W-1] ? OUT_MIN : OUT_MAX));

    // 将同步历史RAM和系数BRAM的返回数据，与上一周期发出的有效掩码及
    // 展开系数索引对齐，保证串行MAC消费的是同一抽头事务。
    always @(posedge clk) begin
        if (!rst_n) begin
            read_data_valid <= 1'b0;
            read_mask <= 1'b0;
            read_coeff_index <= {INDEX_W{1'b0}};
        end
        else begin
            read_data_valid <= read_issue_valid;
            if (read_issue_valid) begin
                read_mask <= read_issue_mask;
                read_coeff_index <= issue_index;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            read_addr <= {ADDR_W{1'b0}};
            wr_ptr <= {ADDR_W{1'b0}};
            history_full <= 1'b0;
            phase_cnt <= 1'b1;
            phase_dbg <= 1'b1;
            mac_active <= 1'b0;
`ifndef SYNTHESIS
            filter_ready <= 1'b0;
`endif
            scan_exhausted <= 1'b0;
            read_issue_valid <= 1'b0;
            read_issue_mask <= 1'b0;
            issue_active <= 1'b0;
            issue_index <= {INDEX_W{1'b0}};
            delay_result <= {DATA_W{1'b0}};
            filter_commit_pending <= 1'b0;
            filter_saturation_pending <= 1'b0;
            y_out <= {DATA_W{1'b0}};
            y_out_valid <= 1'b0;
        end
        else begin
            y_out_valid <= 1'b0;
            read_issue_valid <= 1'b0;

            if (filter_saturation_pending) begin
`ifndef SYNTHESIS
                filter_ready <= 1'b1;
`endif
                filter_saturation_pending <= 1'b0;
            end
            else if (filter_commit_pending) begin
                filter_saturation_pending <= 1'b1;
                filter_commit_pending <= 1'b0;
            end

            if (read_data_valid) begin
                // delay_result复位为0，中心抽头历史有效性在下次复位前单调成立。
                // 因而启动期抽头无效时保持旧值，与每拍重复写0严格等价；一旦
                // 有效，后续中心抽头始终有效。使用寄存器使能表达该不变量，
                // 可消除DATA_W位宽的“BRAM数据/零”输入MUX。
                if (read_coeff_index == DELAY_INDEX && read_mask)
                    delay_result <= read_data;

                if (read_coeff_index == HISTORY_LEN-1) begin
                    filter_commit_pending <= 1'b1;
                    mac_active <= 1'b0;
                end
            end

            // 首次请求后读地址逐拍递减。历史尚未写满时，地址0表示最后一个
            // 已初始化字；随后回绕地址由scan_exhausted通过DSP CEP屏蔽，
            // 避免使用DATA_W位宽Fabric MUX。issue_index同时承担系数BRAM
            // 实时地址和发射计数器，返回流水已保存对应索引，无需第二计数器。
            if (issue_active) begin
                read_issue_valid <= 1'b1;
                read_addr <= read_addr - {{(ADDR_W-1){1'b0}}, 1'b1};
                read_issue_mask <= history_full || !scan_exhausted;

                if (read_addr == {{(ADDR_W-1){1'b0}}, 1'b1})
                    scan_exhausted <= 1'b1;

                // 本时钟沿送入BRAM端口的地址将由既有返回有效流水消费；
                // 计数从50推进到51后停止，使地址51恰好采样一次，与原
                // next-index计数器的抽头序列严格一致。
                if (issue_index == HISTORY_LEN-2)
                    issue_active <= 1'b0;
                issue_index <= issue_index +
                               {{(INDEX_W-1){1'b0}}, 1'b1};
            end

            if (ce_out) begin
                phase_dbg <= phase_cnt;
                y_out_valid <= 1'b1;

                if (phase_cnt == 1'b0) begin
                    y_out <= delay_result;

                    wr_ptr <= wr_ptr + {{(ADDR_W-1){1'b0}}, 1'b1};
                    if (wr_ptr == HISTORY_LEN-1)
                        history_full <= 1'b1;

`ifndef SYNTHESIS
                    filter_ready <= 1'b0;
`endif
                    mac_active <= 1'b1;
                    issue_active <= 1'b1;
                    scan_exhausted <= (wr_ptr == {ADDR_W{1'b0}});
                    read_issue_valid <= 1'b1;
                    read_issue_mask <= 1'b1;
                    issue_index <= {INDEX_W{1'b0}};
                    read_addr <= wr_ptr;
                end
                else begin
                    y_out <= filter_rounded;
`ifndef SYNTHESIS
                    filter_ready <= 1'b0;
`endif
                end

                phase_cnt <= ~phase_cnt;
            end
        end
    end

`ifndef SYNTHESIS
    reg input_seen;

    always @(posedge clk) begin
        if (!rst_n)
            input_seen <= 1'b0;
        else if (ce_out && phase_cnt == 1'b0) begin
            input_seen <= 1'b1;
            if (issue_active || read_issue_valid || read_data_valid ||
                filter_commit_pending || filter_saturation_pending)
                $fatal(1, "Stage1 sequential-tap MAC deadline miss");
        end
        else if (ce_out && phase_cnt == 1'b1 && input_seen &&
                 !filter_ready)
            $fatal(1, "Stage1 sequential-tap result not ready");
    end

    initial begin
        if (DATA_W != 24 || HISTORY_LEN != 52 || PAIR_COUNT != 26 ||
            DELAY_INDEX != 25)
            $fatal(1, "Stage1 sequential-tap schedule requires 24/52/26/25");
        if (USE_DSP48_PREADDER != 0)
            $display("INFO: Stage1 sequential-tap mode replaces the DSP preadder with one MAC per history word");
    end
`endif

endmodule
