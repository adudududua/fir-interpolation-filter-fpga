`timescale 1ns / 1ps

`include "../all2x_v3/all2x_v3_stage1_coeff_pkg.vh"

// Stage1 sequential-tap BRAM microengine.
//
// The signed-off implementation read Lk/Rk pairs and used the DSP48E1
// preadder.  This implementation expands the symmetric 26-coefficient table
// to 52 entries in otherwise unused locations of the existing coefficient
// RAMB18E1.  History is scanned newest-to-oldest and one exact product is
// accumulated every clock.  Therefore
//
//   (Lk + Rk) * Ck == Lk * Ck + Rk * Ck
//
// in the same two's-complement modular accumulator, while the left/right
// metadata, second address equation and preadder controls disappear.  The
// center delay sample is captured during the same scan, so it no longer needs
// a separate BRAM prefetch.
module interp2_stage1_single_bram_serial_ce #(
    parameter integer DATA_W      = 24,
    parameter integer COEFF_W     = `V3_S1_COEFF_W,
    parameter integer ACC_W       = `V3_S1_ACC_W,
    parameter integer FRAC_W      = `V3_S1_FRAC_W,
    parameter integer HISTORY_LEN = `V3_S1_HISTORY_LEN,
    parameter integer PAIR_COUNT  = `V3_S1_PAIR_COUNT,
    parameter integer DELAY_INDEX = `V3_S1_DELAY_INDEX,
    // Retained for source compatibility.  Sequential-tap mode deliberately
    // uses the multiplier directly rather than the DSP preadder.
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
    // Kept as an observable schedule mirror for the reset/deadline
    // regression.  Functional control uses issue_active and the tail flags.
    reg mac_active;
`ifndef SYNTHESIS
    // Fixed-latency schedule mirror used only by deadline assertions.  The
    // hardware output path does not need a redundant ready state because all
    // 52 reads plus the two DSP tail cycles finish before the next odd phase.
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

    // Internal-table compatibility for standalone tests.  The board build
    // constant-folds this path away and reads the expanded table from BRAM.
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

    // Align the synchronous history and coefficient BRAM outputs with the
    // mask and expanded coefficient index issued on the preceding cycle.
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
                // delay_result is reset to zero, and the center-tap history
                // validity is monotonic until the next reset.  Keeping the
                // previous value while this tap is invalid is therefore
                // exactly equivalent to repeatedly writing zero during
                // startup.  Once valid, every later center-tap read remains
                // valid.  Expressing that invariant as a register enable
                // removes the DATA_W-wide BRAM-data/zero input mux.
                if (read_coeff_index == DELAY_INDEX && read_mask)
                    delay_result <= read_data;

                if (read_coeff_index == HISTORY_LEN-1) begin
                    filter_commit_pending <= 1'b1;
                    mac_active <= 1'b0;
                end
            end

            // After the first request, the address simply decrements.  Before
            // the history is full, address zero marks the last initialized
            // word; scan_exhausted masks all later wrapped addresses through
            // DSP CEP rather than a DATA_W-wide Fabric mux.  issue_index is
            // both the live coefficient-BRAM address and the issue counter;
            // the return pipeline already retains the corresponding index,
            // so a second schedule counter would be redundant.
            if (issue_active) begin
                read_issue_valid <= 1'b1;
                read_addr <= read_addr - {{(ADDR_W-1){1'b0}}, 1'b1};
                read_issue_mask <= history_full || !scan_exhausted;

                if (read_addr == {{(ADDR_W-1){1'b0}}, 1'b1})
                    scan_exhausted <= 1'b1;

                // The address placed on the BRAM port at this edge is
                // consumed by the existing return-valid pipeline.  Stop
                // after advancing 50 -> 51 so address 51 is sampled once,
                // matching the former next-index counter exactly.
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
