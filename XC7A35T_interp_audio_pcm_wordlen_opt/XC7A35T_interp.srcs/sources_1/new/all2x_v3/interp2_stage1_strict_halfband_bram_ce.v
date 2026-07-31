`timescale 1ns / 1ps

`include "all2x_v3_stage1_coeff_pkg.vh"

//=============================================================
// 文件名       : interp2_stage1_strict_halfband_bram_ce.v
// 模块名       : interp2_stage1_strict_halfband_bram_ce
// 功能简述     : Stage 1 strict-halfband true-polyphase BRAM 版本。
//                使用 64x24bit true dual-port 循环缓冲保存真实输入，
//                两个读端口逐周期读取对称样点，26 次 MAC 完成滤波相。
//                纯延迟相在前一相位预读，并在下一次 ce_out 输出。
//
//                BRAM 内容不做运行时复位。fill_count 对尚未写入的
//                历史样点进行零值屏蔽，只复位指针、状态机和 valid。
//
// 当前默认配置：
//                  存储深度      ：64
//                  有效历史长度  ：52
//                  对称 MAC 对数 ：26
//                  系数格式      ：17bit signed Q15
//                  累加器位宽    ：42bit signed
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-11
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-11：新增 Stage 1 strict-halfband BRAM 版本。
//                2026-07-17：通用宽位偏置舍入改为紧凑余数进位结构，
//                            保持可达累加范围内逐位等价并缩短进位链。
//=============================================================

module interp2_stage1_strict_halfband_bram_ce #(
    parameter integer DATA_W      = 24,
    parameter integer COEFF_W     = `V3_S1_COEFF_W,
    parameter integer ACC_W       = `V3_S1_ACC_W,
    parameter integer FRAC_W      = `V3_S1_FRAC_W,
    parameter integer HISTORY_LEN = `V3_S1_HISTORY_LEN,
    parameter integer PAIR_COUNT  = `V3_S1_PAIR_COUNT,
    parameter integer DELAY_INDEX = `V3_S1_DELAY_INDEX,
    parameter integer RAM_DEPTH   = 64,
    parameter integer USE_DSP48_PREADDER = 0,
    parameter integer USE_ROUTE2_COEFF = 0
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
    output wire                         fir_in_valid_dbg
);

    localparam integer ADDR_W = 6;
    localparam integer PAIR_W = DATA_W + 1;
    localparam integer QUOT_W = ACC_W - FRAC_W;
    localparam integer UPPER_W = QUOT_W - DATA_W;
    localparam signed [47:0] ROUND_BIAS =
        (48'sd1 <<< (FRAC_W-1))-48'sd1;
    localparam signed [DATA_W-1:0] OUT_MAX =
        {1'b0, {(DATA_W-1){1'b1}}};
    localparam signed [DATA_W-1:0] OUT_MIN =
        {1'b1, {(DATA_W-1){1'b0}}};

    (* ram_style = "block" *)
    reg signed [DATA_W-1:0] sample_mem [0:RAM_DEPTH-1];

    reg signed [DATA_W-1:0] read_data_a;
    reg signed [DATA_W-1:0] read_data_b;
    reg [ADDR_W-1:0] read_addr_a;
    reg [ADDR_W-1:0] read_addr_b;
    reg [ADDR_W-1:0] wr_ptr;
    reg [ADDR_W-1:0] base_ptr;
    reg [5:0] fill_count;
    reg [5:0] active_fill_count;

    reg phase_cnt;
    reg mac_active;
    reg filter_ready;
    reg delay_ready;
    reg issue_active;
    reg read_issue_valid;
    reg issue_is_delay;
    reg issue_mask_a;
    reg issue_mask_b;
    reg [4:0] issue_index;

    reg read_data_valid;
    reg read_is_delay;
    reg read_mask_a;
    reg read_mask_b;
    reg [4:0] read_coeff_index;

    reg signed [DATA_W-1:0] delay_result;
    reg filter_commit_pending;

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
    wire dsp_round_carryin;
    wire signed [QUOT_W-1:0] rounded_quotient;
    wire rounded_upper_is_sign_extension;

    assign x_current = x_in_valid ? x_in : {DATA_W{1'b0}};
    assign fir_in_dbg = x_current;
    assign fir_in_valid_dbg = ce_out && (phase_cnt == 1'b0);

    assign dsp_preadd_a = read_mask_a ?
        {{(25-DATA_W){read_data_a[DATA_W-1]}}, read_data_a} : 25'sd0;
    assign dsp_preadd_d = read_mask_b ?
        {{(25-DATA_W){read_data_b[DATA_W-1]}}, read_data_b} : 25'sd0;
    assign dsp_input_a = (USE_DSP48_PREADDER != 0) ?
        {{5{dsp_preadd_a[24]}}, dsp_preadd_a} :
        {{(30-PAIR_W){pair_sum_comb[PAIR_W-1]}}, pair_sum_comb};
    assign dsp_coeff_b =
        {{(18-COEFF_W){coeff_comb[COEFF_W-1]}}, coeff_comb};
    assign dsp_inmode = (USE_DSP48_PREADDER != 0) ?
        5'b00100 : 5'b00000;
    assign dsp_p_reset = !rst_n ||
        (ce_out && phase_cnt == 1'b0);
    assign dsp_p_ce =
        (read_data_valid && !read_is_delay) || filter_commit_pending;
    // Exact symmetric rounding is 2^(FRAC_W-1)-1 plus one carry for a
    // non-negative sum.  Keeping the expression parameterized is required
    // by the Route2 Q16 Stage1 as well as the original Q15 Stage1.
    // Keeping C constant and using the DSP carry input avoids a sign-driven
    // 48-bit constant selector.
    assign dsp_round_bias = ROUND_BIAS;
    assign dsp_round_carryin =
        filter_commit_pending && !mac_sum_comb[ACC_W-1];
    assign dsp_opmode = filter_commit_pending ?
        7'b0001110 : 7'b0100101;

    // PREG holds both the running sum and the completed filter result.  The
    // phase interval is hundreds of clocks, so one result-commit cycle is
    // available after the final MAC without changing the output cadence.
    DSP48E1 #(
        .A_INPUT("DIRECT"),
        .B_INPUT("DIRECT"),
        .USE_DPORT("TRUE"),
        .USE_MULT("MULTIPLY"),
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
    ) u_stage1_dsp48e1 (
        .P(dsp_mac_full),
        .A(dsp_input_a),
        .B(dsp_coeff_b),
        .C(dsp_round_bias),
        .D((USE_DSP48_PREADDER != 0) ? dsp_preadd_d : 25'sd0),
        .INMODE(dsp_inmode),
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
        .CEP(dsp_p_ce),
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
        .PATTERNBDETECT(),
        .PATTERNDETECT(),
        .PCOUT(),
        .UNDERFLOW()
    );

    assign mac_sum_comb = dsp_mac_full[ACC_W-1:0];

    always @(*) begin
        pair_sum_comb =
            $signed({(read_mask_a ? read_data_a[DATA_W-1] : 1'b0),
                     (read_mask_a ? read_data_a : {DATA_W{1'b0}})}) +
            $signed({(read_mask_b ? read_data_b[DATA_W-1] : 1'b0),
                     (read_mask_b ? read_data_b : {DATA_W{1'b0}})});
    end

    generate
        if (USE_ROUTE2_COEFF != 0) begin : gen_route2_stage1_coeff
            always @(*) begin
                case (read_coeff_index)
                    5'd0:  coeff_comb = `R2_S1_C00;
                    5'd1:  coeff_comb = `R2_S1_C01;
                    5'd2:  coeff_comb = `R2_S1_C02;
                    5'd3:  coeff_comb = `R2_S1_C03;
                    5'd4:  coeff_comb = `R2_S1_C04;
                    5'd5:  coeff_comb = `R2_S1_C05;
                    5'd6:  coeff_comb = `R2_S1_C06;
                    5'd7:  coeff_comb = `R2_S1_C07;
                    5'd8:  coeff_comb = `R2_S1_C08;
                    5'd9:  coeff_comb = `R2_S1_C09;
                    5'd10: coeff_comb = `R2_S1_C10;
                    5'd11: coeff_comb = `R2_S1_C11;
                    5'd12: coeff_comb = `R2_S1_C12;
                    5'd13: coeff_comb = `R2_S1_C13;
                    5'd14: coeff_comb = `R2_S1_C14;
                    5'd15: coeff_comb = `R2_S1_C15;
                    5'd16: coeff_comb = `R2_S1_C16;
                    5'd17: coeff_comb = `R2_S1_C17;
                    5'd18: coeff_comb = `R2_S1_C18;
                    5'd19: coeff_comb = `R2_S1_C19;
                    5'd20: coeff_comb = `R2_S1_C20;
                    5'd21: coeff_comb = `R2_S1_C21;
                    5'd22: coeff_comb = `R2_S1_C22;
                    5'd23: coeff_comb = `R2_S1_C23;
                    default: coeff_comb = {COEFF_W{1'b0}};
                endcase
            end
        end
        else begin : gen_baseline_stage1_coeff
            always @(*) begin
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
    endgenerate

    // The result-commit DSP cycle has already added the exact signed Q15
    // rounding bias.  Saturation therefore needs no external carry chain.
    assign rounded_quotient = mac_sum_comb >>> FRAC_W;
    assign rounded_upper_is_sign_extension =
        rounded_quotient[QUOT_W-1:DATA_W] ==
        {UPPER_W{rounded_quotient[DATA_W-1]}};
    assign filter_rounded = rounded_upper_is_sign_extension ?
        rounded_quotient[DATA_W-1:0] :
        (rounded_quotient[QUOT_W-1] ? OUT_MIN : OUT_MAX);

    // Port A：phase0 写入，其余周期作为第一个同步读端口。
    always @(posedge clk) begin
        if (rst_n && ce_out && phase_cnt == 1'b0)
            sample_mem[wr_ptr] <= x_current;
        else if (read_issue_valid)
            read_data_a <= sample_mem[read_addr_a];
    end

    // Port B：第二个同步读端口。
    always @(posedge clk) begin
        if (read_issue_valid)
            read_data_b <= sample_mem[read_addr_b];
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            read_data_valid <= 1'b0;
            read_is_delay <= 1'b0;
            read_mask_a <= 1'b0;
            read_mask_b <= 1'b0;
            read_coeff_index <= 5'd0;
        end
        else begin
            read_data_valid <= read_issue_valid;
            if (read_issue_valid) begin
                read_is_delay <= issue_is_delay;
                read_mask_a <= issue_mask_a;
                read_mask_b <= issue_mask_b;
                read_coeff_index <= issue_index;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= {ADDR_W{1'b0}};
            base_ptr <= {ADDR_W{1'b0}};
            fill_count <= 6'd0;
            active_fill_count <= 6'd0;
            phase_cnt <= 1'b1;
            phase_dbg <= 1'b1;
            mac_active <= 1'b0;
            filter_ready <= 1'b0;
            delay_ready <= 1'b0;
            issue_active <= 1'b0;
            read_issue_valid <= 1'b0;
            issue_is_delay <= 1'b0;
            issue_mask_a <= 1'b0;
            issue_mask_b <= 1'b0;
            issue_index <= 5'd0;
            read_addr_a <= {ADDR_W{1'b0}};
            read_addr_b <= {ADDR_W{1'b0}};
            delay_result <= {DATA_W{1'b0}};
            filter_commit_pending <= 1'b0;
            y_out <= {DATA_W{1'b0}};
            y_out_valid <= 1'b0;
        end
        else begin
            y_out_valid <= 1'b0;
            read_issue_valid <= 1'b0;

            if (filter_commit_pending) begin
                filter_ready <= 1'b1;
                filter_commit_pending <= 1'b0;
            end

            if (read_data_valid) begin
                if (read_is_delay) begin
                    delay_result <= read_mask_a ? read_data_a :
                                    {DATA_W{1'b0}};
                    delay_ready <= 1'b1;
                end
                else if (read_coeff_index == PAIR_COUNT-1) begin
                    filter_commit_pending <= 1'b1;
                    mac_active <= 1'b0;
                end
            end

            if (issue_active) begin
                issue_is_delay <= 1'b0;

                if (issue_index < PAIR_COUNT-1) begin
                    read_issue_valid <= 1'b1;
                    issue_index <= issue_index + 5'd1;
                    read_addr_a <= base_ptr - (issue_index + 5'd1);
                    read_addr_b <= base_ptr -
                        (HISTORY_LEN-1-(issue_index + 5'd1));
                    issue_mask_a <= (issue_index + 5'd1) <
                                    active_fill_count;
                    issue_mask_b <=
                        (HISTORY_LEN-1-(issue_index + 5'd1)) <
                        active_fill_count;
                end
                else begin
                    read_issue_valid <= 1'b0;
                    issue_active <= 1'b0;
                end
            end

            if (ce_out) begin
                phase_dbg <= phase_cnt;
                y_out_valid <= 1'b1;

                if (phase_cnt == 1'b0) begin
                    y_out <= delay_ready ? delay_result :
                             {DATA_W{1'b0}};
                    delay_ready <= 1'b0;

                    base_ptr <= wr_ptr;
                    wr_ptr <= wr_ptr + 6'd1;
                    if (fill_count < HISTORY_LEN)
                        fill_count <= fill_count + 6'd1;
                    active_fill_count <=
                        (fill_count < HISTORY_LEN) ?
                        (fill_count + 6'd1) : fill_count;

                    mac_active <= 1'b1;
                    filter_ready <= 1'b0;
                    issue_active <= 1'b1;
                    read_issue_valid <= 1'b1;
                    issue_is_delay <= 1'b0;
                    issue_index <= 5'd0;
                    read_addr_a <= wr_ptr;
                    read_addr_b <= wr_ptr - (HISTORY_LEN-1);
                    issue_mask_a <= 1'b1;
                    issue_mask_b <= (HISTORY_LEN-1) <
                        ((fill_count < HISTORY_LEN) ?
                         (fill_count + 6'd1) : fill_count);
                end
                else begin
                    y_out <= filter_ready ? filter_rounded :
                             {DATA_W{1'b0}};
                    filter_ready <= 1'b0;

                    read_issue_valid <= 1'b1;
                    issue_is_delay <= 1'b1;
                    issue_index <= 5'd0;
                    read_addr_a <= wr_ptr - (DELAY_INDEX + 1);
                    read_addr_b <= {ADDR_W{1'b0}};
                    issue_mask_a <= fill_count > DELAY_INDEX;
                    issue_mask_b <= 1'b0;
                end

                phase_cnt <= ~phase_cnt;
            end
        end
    end

`ifndef SYNTHESIS
    reg input_seen;

    initial begin
        if (USE_ROUTE2_COEFF != 0 &&
            (COEFF_W != `R2_S1_COEFF_W ||
             FRAC_W != `R2_S1_FRAC_W ||
             HISTORY_LEN != `R2_S1_HISTORY_LEN ||
             PAIR_COUNT != `R2_S1_PAIR_COUNT ||
             DELAY_INDEX != `R2_S1_DELAY_INDEX))
            $fatal(1, "Route2 Stage1 parameters do not match coefficients");
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            input_seen <= 1'b0;
        end
        else if (ce_out && phase_cnt == 1'b0) begin
            input_seen <= 1'b1;
            if (mac_active || issue_active)
                $fatal(1, "Stage 1 BRAM MAC deadline miss");
        end
        else if (ce_out && phase_cnt == 1'b1 && input_seen &&
                 !filter_ready) begin
            $fatal(1, "Stage 1 BRAM filter result not ready");
        end
    end
`endif

endmodule
