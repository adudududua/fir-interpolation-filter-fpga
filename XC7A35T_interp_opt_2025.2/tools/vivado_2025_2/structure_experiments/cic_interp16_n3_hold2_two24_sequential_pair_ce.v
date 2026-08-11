`timescale 1ns / 1ps

// Fixed-resource CIC candidate for the Vivado 2025.2 national-finals path.
//
// DSP0 keeps the signed 23-bit serial comb exactly as the signed-off design.
// DSP1 uses TWO24 lanes for the low 24 bits of both integrators.  An output
// event updates A; the following idle clock updates B from the new A.  Only
// A[25:24] and B[28:24] remain in Fabric.  y_out_valid is delayed two clocks,
// but the valid sample stream is bit-identical to the reference CIC.
module cic_interp16_n3_hold2_two24_sequential_pair_ce #(
    parameter integer DATA_W = 21,
    parameter integer OUTPUT_W = 20,
    parameter integer FINAL_PRUNE_LSB = 0
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ce_out,
    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,
    output reg  signed [OUTPUT_W-1:0]   y_out,
    output reg                          y_out_valid,
    output wire [4:0]                   burst_remaining_dbg,
    output wire                         pending_dbg,
    output wire                         comb_busy_dbg
);
    localparam integer COMB_W = DATA_W + 2;
    localparam integer COMB_DELAY_W = DATA_W + 1;
    localparam integer FIRST_INT_W = DATA_W + 5;
    localparam integer FINAL_W = DATA_W + 8;
    localparam integer OUTPUT_SHIFT = 8;

    reg signed [COMB_DELAY_W-1:0] comb_delay0;
    reg signed [COMB_DELAY_W-1:0] comb_delay1;
    reg comb_stage_index;
    reg comb_active;
    reg signed [COMB_W-1:0] hold_sample;
    reg burst_pending;
    reg [3:0] burst_remaining;

    wire signed [COMB_W-1:0] x_comb_extended;
    wire signed [COMB_W-1:0] comb_delay_selected;
    wire signed [COMB_W-1:0] comb_operand;
    wire signed [47:0] comb_dsp_p;
    wire signed [47:0] comb_dsp_ab;
    wire signed [47:0] comb_dsp_c;
    wire [6:0] comb_dsp_opmode;
    wire [3:0] comb_dsp_alumode;

    wire output_event;
    wire first_output_event;
    wire signed [FIRST_INT_W-1:0] high_rate_input;
    (* use_dsp = "no" *) wire [3:0] burst_remaining_decrement;

    assign x_comb_extended =
        {{(COMB_W-DATA_W){x_in[DATA_W-1]}}, x_in};
    assign comb_delay_selected =
        {{(COMB_W-COMB_DELAY_W){comb_delay0[COMB_DELAY_W-1]}},
         comb_delay0};
    assign comb_operand = comb_dsp_p[COMB_W-1:0];
    assign comb_dsp_ab =
        {{(48-COMB_W){comb_delay_selected[COMB_W-1]}},
         comb_delay_selected};
    assign comb_dsp_c =
        {{(48-COMB_W){x_comb_extended[COMB_W-1]}},
         x_comb_extended};
    assign comb_dsp_opmode = x_in_valid ? 7'b0110000 : 7'b0100011;
    assign comb_dsp_alumode = x_in_valid ? 4'b0000 : 4'b0011;

    DSP48E1 #(
        .A_INPUT("DIRECT"), .B_INPUT("DIRECT"),
        .USE_DPORT("FALSE"), .USE_MULT("NONE"),
        .USE_PATTERN_DETECT("NO_PATDET"), .USE_SIMD("ONE48"),
        .AREG(0), .ACASCREG(0), .BREG(0), .BCASCREG(0),
        .CREG(0), .DREG(0), .ADREG(0), .MREG(0), .PREG(1),
        .INMODEREG(0), .OPMODEREG(0), .ALUMODEREG(0),
        .CARRYINREG(0), .CARRYINSELREG(0)
    ) u_serial_comb_dsp48e1 (
        .P(comb_dsp_p),
        .A(comb_dsp_ab[47:18]), .B(comb_dsp_ab[17:0]),
        .C(comb_dsp_c), .D(25'd0),
        .INMODE(5'b00000), .OPMODE(comb_dsp_opmode),
        .ALUMODE(comb_dsp_alumode), .CARRYINSEL(3'b000),
        .CARRYIN(1'b0), .ACIN(30'd0), .BCIN(18'd0),
        .PCIN(48'd0), .CARRYCASCIN(1'b0), .MULTSIGNIN(1'b0),
        .CLK(clk),
        .CEA1(1'b0), .CEA2(1'b0), .CEAD(1'b0),
        .CEALUMODE(1'b0), .CEB1(1'b0), .CEB2(1'b0),
        .CEC(1'b0), .CECARRYIN(1'b0), .CECTRL(1'b0),
        .CED(1'b0), .CEINMODE(1'b0), .CEM(1'b0),
        .CEP(x_in_valid || comb_active),
        .RSTA(1'b0), .RSTALLCARRYIN(1'b0),
        .RSTALUMODE(1'b0), .RSTB(1'b0), .RSTC(1'b0),
        .RSTCTRL(1'b0), .RSTD(1'b0), .RSTINMODE(1'b0),
        .RSTM(1'b0), .RSTP(!rst_n),
        .ACOUT(), .BCOUT(), .CARRYCASCOUT(), .CARRYOUT(),
        .MULTSIGNOUT(), .OVERFLOW(), .PATTERNBDETECT(),
        .PATTERNDETECT(), .PCOUT(), .UNDERFLOW()
    );

    assign output_event = ce_out &&
                          (burst_pending || burst_remaining != 4'd0);
    assign first_output_event = ce_out && burst_pending &&
                                burst_remaining == 4'd0;
    assign high_rate_input = first_output_event ?
        {{(FIRST_INT_W-COMB_W){comb_operand[COMB_W-1]}}, comb_operand} :
        {{(FIRST_INT_W-COMB_W){hold_sample[COMB_W-1]}}, hold_sample};
    assign burst_remaining_decrement = burst_remaining - 4'd1;

    reg signed [1:0] first_integrator_high;
    reg signed [4:0] final_integrator_high;
    reg        [1:0] input_high_pending;
    reg first_update_pending;
    reg final_update_pending;

    wire pair_do_first;
    wire pair_do_final;
    wire signed [47:0] pair_ab;
    wire signed [47:0] pair_c;
    wire [6:0] pair_opmode;
    wire signed [47:0] pair_dsp_p;
    wire [3:0] pair_dsp_carryout;
    wire [2:0] first_high_sum;
    wire [4:0] first_high_sign_extended;
    wire [5:0] final_high_sum;
    wire signed [FINAL_W-1:0] final_integrator_commit;
    wire signed [FINAL_W-1:0] final_integrator_state;
    wire signed [OUTPUT_W-1:0] normalized_output;

    assign pair_do_first = output_event;
    assign pair_do_final = first_update_pending;
    // Keep both wide operands statically wired.  OPMODE selects P+C for the
    // first-integrator clock and P+A:B for the final-integrator clock.  This
    // avoids a 48-bit Fabric mux in front of the DSP.
    assign pair_ab = {pair_dsp_p[23:0], 24'd0};
    assign pair_c = {24'd0, high_rate_input[23:0]};
    assign pair_opmode = pair_do_first ? 7'b0001110 : 7'b0100011;

    DSP48E1 #(
        .A_INPUT("DIRECT"), .B_INPUT("DIRECT"),
        .USE_DPORT("FALSE"), .USE_MULT("NONE"),
        .USE_PATTERN_DETECT("NO_PATDET"), .USE_SIMD("TWO24"),
        .AREG(0), .ACASCREG(0), .BREG(0), .BCASCREG(0),
        .CREG(0), .DREG(0), .ADREG(0), .MREG(0), .PREG(1),
        .INMODEREG(0), .OPMODEREG(0), .ALUMODEREG(0),
        .CARRYINREG(0), .CARRYINSELREG(0)
    ) u_two24_sequential_integrators (
        .P(pair_dsp_p), .CARRYOUT(pair_dsp_carryout),
        .A(pair_ab[47:18]), .B(pair_ab[17:0]),
        .C(pair_c), .D(25'd0),
        .INMODE(5'b00000), .OPMODE(pair_opmode),
        .ALUMODE(4'b0000), .CARRYINSEL(3'b000),
        .CARRYIN(1'b0), .ACIN(30'd0), .BCIN(18'd0),
        .PCIN(48'd0), .CARRYCASCIN(1'b0), .MULTSIGNIN(1'b0),
        .CLK(clk),
        .CEA1(1'b0), .CEA2(1'b0), .CEAD(1'b0),
        .CEALUMODE(1'b0), .CEB1(1'b0), .CEB2(1'b0),
        .CEC(1'b0), .CECARRYIN(1'b0), .CECTRL(1'b0),
        .CED(1'b0), .CEINMODE(1'b0), .CEM(1'b0),
        .CEP(pair_do_first || pair_do_final),
        .RSTA(1'b0), .RSTALLCARRYIN(1'b0),
        .RSTALUMODE(1'b0), .RSTB(1'b0), .RSTC(1'b0),
        .RSTCTRL(1'b0), .RSTD(1'b0), .RSTINMODE(1'b0),
        .RSTM(1'b0), .RSTP(!rst_n),
        .ACOUT(), .BCOUT(), .CARRYCASCOUT(), .MULTSIGNOUT(),
        .OVERFLOW(), .PATTERNBDETECT(), .PATTERNDETECT(),
        .PCOUT(), .UNDERFLOW()
    );

    assign first_high_sum =
        {1'b0, first_integrator_high} +
        {1'b0, input_high_pending} + pair_dsp_carryout[1];
    assign first_high_sign_extended =
        {{3{first_integrator_high[1]}}, first_integrator_high};
    assign final_high_sum =
        {1'b0, final_integrator_high} +
        {1'b0, first_high_sign_extended} + pair_dsp_carryout[3];
    assign final_integrator_commit =
        {final_high_sum[4:0], pair_dsp_p[47:24]};
    assign final_integrator_state =
        {final_integrator_high, pair_dsp_p[47:24]};

    round_sat_shift_compact #(
        .IN_W(FINAL_W), .OUT_W(OUTPUT_W), .SHIFT_N(OUTPUT_SHIFT)
    ) u_round_cic_normalized_output (
        .din(final_integrator_commit), .dout(normalized_output)
    );

    assign burst_remaining_dbg = {1'b0, burst_remaining};
    assign pending_dbg = burst_pending;
    assign comb_busy_dbg = comb_active || comb_stage_index;

    always @(posedge clk) begin
        if (!rst_n) begin
            comb_delay0 <= {COMB_DELAY_W{1'b0}};
            comb_delay1 <= {COMB_DELAY_W{1'b0}};
            comb_stage_index <= 1'b0;
            comb_active <= 1'b0;
            hold_sample <= {COMB_W{1'b0}};
            burst_pending <= 1'b0;
            burst_remaining <= 4'd0;
            first_integrator_high <= 2'sd0;
            final_integrator_high <= 5'sd0;
            input_high_pending <= 2'd0;
            first_update_pending <= 1'b0;
            final_update_pending <= 1'b0;
            y_out <= {OUTPUT_W{1'b0}};
            y_out_valid <= 1'b0;
        end
        else begin
            y_out_valid <= 1'b0;

            if (x_in_valid) begin
                comb_stage_index <= 1'b0;
                comb_active <= 1'b1;
            end
            if (comb_active) begin
                comb_delay0 <= comb_delay1;
                comb_delay1 <= comb_operand[COMB_DELAY_W-1:0];
                if (comb_stage_index)
                    comb_active <= 1'b0;
                else
                    comb_stage_index <= 1'b1;
            end
            else if (comb_stage_index) begin
                comb_stage_index <= 1'b0;
                burst_pending <= 1'b1;
            end

            if (first_update_pending) begin
                first_integrator_high <= first_high_sum[1:0];
                first_update_pending <= 1'b0;
                final_update_pending <= 1'b1;
            end
            if (final_update_pending) begin
                final_integrator_high <= final_high_sum[4:0];
                final_update_pending <= 1'b0;
                y_out <= normalized_output;
                y_out_valid <= 1'b1;
            end
            if (output_event) begin
                input_high_pending <= high_rate_input[FIRST_INT_W-1:24];
                first_update_pending <= 1'b1;
                if (first_output_event) begin
                    hold_sample <= comb_operand;
                    burst_pending <= 1'b0;
                    burst_remaining <= 4'd15;
                end
                else if (burst_remaining == 4'd1) begin
                    burst_remaining <= 4'd0;
                end
                else begin
                    burst_remaining <= burst_remaining_decrement;
                end
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && (DATA_W != 21 || OUTPUT_W != 20 ||
                      FINAL_PRUNE_LSB != 0))
            $fatal(1, "Sequential TWO24 candidate requires 21/20/0 widths");
        if (rst_n && x_in_valid &&
            (comb_active || comb_stage_index || burst_pending))
            $fatal(1, "Sequential TWO24 CIC input overwrite");
        if (rst_n && output_event && first_update_pending)
            $fatal(1, "Sequential TWO24 CIC requires two-clock event spacing");
    end
`endif
endmodule
