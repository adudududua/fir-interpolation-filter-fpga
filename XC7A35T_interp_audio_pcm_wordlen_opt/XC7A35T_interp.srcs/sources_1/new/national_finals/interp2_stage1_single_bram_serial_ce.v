`timescale 1ns / 1ps

`include "../all2x_v3/all2x_v3_stage1_coeff_pkg.vh"

// Bit-true Stage1 replacement using one 64x24 RAMB18E1.
//
// The legacy core reads both members of a symmetric pair in one clock and
// consumes two RAMB18 primitives.  This core exploits the 64-clock gap between
// adjacent ce_out pulses.  One synchronous RAM read is issued every clock in
// the order L0,R0,L1,R1,...,L25,R25.  The just-written L0 word is read back on
// the next clock, avoiding a 24-bit fabric bypass mux.  In preadder mode the
// left word is retained in the DSP48 A register and history-valid masking is
// performed by INMODE, avoiding a 24-bit fabric left-word register and masks.
module interp2_stage1_single_bram_serial_ce #(
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
    output wire [4:0]                   external_coeff_addr,
    input  wire signed [15:0]           external_coeff_data
);

    localparam integer ADDR_W = 6;
    localparam integer PAIR_W = DATA_W + 1;
    localparam integer QUOT_W = ACC_W - FRAC_W;
    localparam integer UPPER_W = QUOT_W - DATA_W;
    localparam integer PATTERN_SAT_SUPPORTED =
        (DATA_W == 24 && ACC_W == 41 && FRAC_W == 15);
    localparam [1:0] READ_LEFT  = 2'd0;
    localparam [1:0] READ_RIGHT = 2'd1;
    localparam [1:0] READ_DELAY = 2'd2;
    localparam signed [DATA_W-1:0] OUT_MAX =
        {1'b0, {(DATA_W-1){1'b1}}};
    localparam signed [DATA_W-1:0] OUT_MIN =
        {1'b1, {(DATA_W-1){1'b0}}};

    reg [ADDR_W-1:0] read_addr;
    wire signed [DATA_W-1:0] read_data;
    reg [ADDR_W-1:0] wr_ptr;
    wire [ADDR_W-1:0] history_base_ptr;
    // Before the circular pointer wraps, wr_ptr is also the exact number of
    // initialized history words.  One sticky bit preserves that information
    // after the 52-word history becomes full, replacing two 6-bit counters.
    reg history_full;

    reg phase_cnt;
    reg mac_active;
    reg filter_ready;
    reg delay_ready;
    reg issue_active;
    reg next_issue_is_left;
    reg [4:0] schedule_index;

    reg read_issue_valid;
    reg [1:0] read_issue_kind;
    reg read_issue_mask;
    reg [4:0] issue_index;
    reg read_data_valid;
    reg [1:0] read_kind;
    reg read_mask;
    reg [4:0] read_coeff_index;

    // Used only by the non-preadder compatibility configuration.  The signed-
    // off preadder configuration stores the left operand inside DSP48 AREG.
    reg signed [DATA_W-1:0] left_sample;
    reg left_mask;
    reg signed [DATA_W-1:0] delay_result;
    reg filter_commit_pending;
    reg filter_saturation_pending;

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

    assign x_current = x_in_valid ? x_in : {DATA_W{1'b0}};
    // wr_ptr advances after writing the current input and remains stable for
    // the complete serial schedule.  Its predecessor is therefore exactly
    // the former 6-bit base-pointer snapshot, modulo the RAM address space.
    assign history_base_ptr = wr_ptr - {{(ADDR_W-1){1'b0}}, 1'b1};
    assign fir_in_dbg = x_current;
    assign fir_in_valid_dbg = ce_out && (phase_cnt == 1'b0);
    assign external_coeff_addr = issue_index;

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

    assign dsp_preadd_a =
        {{(25-DATA_W){read_data[DATA_W-1]}}, read_data};
    assign dsp_preadd_d =
        {{(25-DATA_W){read_data[DATA_W-1]}}, read_data};
    assign dsp_input_a = (USE_DSP48_PREADDER != 0) ?
        {{5{dsp_preadd_a[24]}}, dsp_preadd_a} :
        {{(30-PAIR_W){pair_sum_comb[PAIR_W-1]}}, pair_sum_comb};
    assign dsp_coeff_b =
        {{(18-COEFF_W){coeff_comb[COEFF_W-1]}}, coeff_comb};
    // INMODE[1] removes an invalid registered A operand; INMODE[2] removes an
    // invalid direct D operand.  A is loaded only on READ_LEFT and held for
    // the immediately following READ_RIGHT MAC.
    assign dsp_inmode = (USE_DSP48_PREADDER != 0) ?
        {2'b00, read_mask, ~left_mask, 1'b0} : 5'b00000;
    assign dsp_p_reset = !rst_n || (ce_out && phase_cnt == 1'b0);
    assign dsp_p_ce =
        (read_data_valid && read_kind == READ_RIGHT) ||
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

    assign mac_sum_comb = dsp_mac_full[ACC_W-1:0];

    always @(*) begin
        pair_sum_comb =
            $signed({left_sample[DATA_W-1], left_sample}) +
            $signed({(read_mask ? read_data[DATA_W-1] : 1'b0),
                     (read_mask ? read_data : {DATA_W{1'b0}})});

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

    assign rounded_quotient = mac_sum_comb >>> FRAC_W;
    assign rounded_upper_is_sign_extension =
        PATTERN_SAT_SUPPORTED ?
        (rounded_quotient[DATA_W-1] ?
         dsp_pattern_ones : dsp_pattern_zero) :
        (rounded_quotient[QUOT_W-1:DATA_W] ==
         {UPPER_W{rounded_quotient[DATA_W-1]}});
    // In the national-finals profile an overflow is replaced by an exactly
    // scaled limit in DSP PREG during the spare saturation tail cycle.  The
    // output then needs only a fixed slice; generic widths retain the original
    // fabric fallback.
    assign filter_rounded = PATTERN_SAT_SUPPORTED ?
        rounded_quotient[DATA_W-1:0] :
        (rounded_upper_is_sign_extension ?
         rounded_quotient[DATA_W-1:0] :
         (rounded_quotient[QUOT_W-1] ? OUT_MIN : OUT_MAX));

    // Metadata is delayed one clock alongside the synchronous RAM output.
    // The controller consumes both on the following active edge, matching the
    // unregistered RAMB18 output and the unified coefficient RAM latency.
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

    always @(posedge clk) begin
        if (!rst_n) begin
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
            y_out_valid <= 1'b0;
            read_issue_valid <= 1'b0;

            if (filter_saturation_pending) begin
                filter_ready <= 1'b1;
                filter_saturation_pending <= 1'b0;
            end
            else if (filter_commit_pending) begin
                filter_saturation_pending <= 1'b1;
                filter_commit_pending <= 1'b0;
            end

            if (read_data_valid) begin
                if (read_kind == READ_LEFT) begin
                    left_sample <= read_mask ? read_data :
                                   {DATA_W{1'b0}};
                    left_mask <= read_mask;
                end
                else if (read_kind == READ_DELAY) begin
                    delay_result <= read_mask ? read_data :
                                    {DATA_W{1'b0}};
                    delay_ready <= 1'b1;
                end
                else if (read_coeff_index == PAIR_COUNT-1) begin
                    filter_commit_pending <= 1'b1;
                    mac_active <= 1'b0;
                end
            end

            if (issue_active) begin
                read_issue_valid <= 1'b1;
                issue_index <= schedule_index;

                if (next_issue_is_left) begin
                    read_issue_kind <= READ_LEFT;
                    read_addr <= history_base_ptr - schedule_index;
                    read_issue_mask <= history_full ||
                                       schedule_index < wr_ptr;
                    next_issue_is_left <= 1'b0;
                end
                else begin
                    read_issue_kind <= READ_RIGHT;
                    read_addr <= history_base_ptr -
                        (HISTORY_LEN-1-schedule_index);
                    read_issue_mask <= history_full ||
                        (HISTORY_LEN-1-schedule_index) < wr_ptr;

                    if (schedule_index == PAIR_COUNT-1) begin
                        issue_active <= 1'b0;
                    end
                    else begin
                        schedule_index <= schedule_index + 5'd1;
                        next_issue_is_left <= 1'b1;
                    end
                end
            end

            if (ce_out) begin
                phase_dbg <= phase_cnt;
                y_out_valid <= 1'b1;

                if (phase_cnt == 1'b0) begin
                    y_out <= delay_ready ? delay_result :
                             {DATA_W{1'b0}};
                    delay_ready <= 1'b0;

                    wr_ptr <= wr_ptr + 6'd1;
                    if (wr_ptr == HISTORY_LEN-1)
                        history_full <= 1'b1;

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
                    y_out <= filter_ready ? filter_rounded :
                             {DATA_W{1'b0}};
                    filter_ready <= 1'b0;

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
    reg input_seen;

    always @(posedge clk) begin
        if (!rst_n) begin
            input_seen <= 1'b0;
        end
        else if (ce_out && phase_cnt == 1'b0) begin
            input_seen <= 1'b1;
            if (mac_active || issue_active)
                $fatal(1, "Stage1 single-BRAM MAC deadline miss");
        end
        else if (ce_out && phase_cnt == 1'b1 && input_seen &&
                 !filter_ready) begin
            $fatal(1, "Stage1 single-BRAM filter result not ready");
        end
    end

    initial begin
        if (DATA_W != 24 || HISTORY_LEN != 52 || PAIR_COUNT != 26)
            $fatal(1, "Stage1 single-BRAM schedule requires 24/52/26");
    end
`endif

endmodule
