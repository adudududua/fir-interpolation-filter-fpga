`timescale 1ns / 1ps

// Experimental 4-DSP-system CIC candidate.
//
// One DSP48E1 in TWO24 mode keeps the 23-bit serial-comb operand in its low
// lane and the low 24 bits of the first 26-bit integrator in its high lane.
// The comb uses idle clocks; high-rate output events use the other lane.  The
// upper two integrator bits and the lane carry stay in Fabric.  A second DSP
// remains dedicated to the final 29-bit integrator, so the CIC and complete
// system DSP counts remain 2 and 4 respectively.
module cic_interp16_n3_hold2_two24_comb_integrator_ce #(
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
    reg comb_load_pending;
    reg comb_stage_index;
    reg comb_active;
    reg signed [COMB_W-1:0] hold_sample;

    reg signed [1:0] integrator_top;
    reg        [1:0] integrator_top_operand_pending;
    reg signed [FINAL_W-1:0] final_integrator_state;
    reg final_pending;

    reg burst_pending;
    reg [3:0] burst_remaining;

    wire output_event;
    wire first_output_event;
    wire signed [COMB_W-1:0] comb_operand;
    wire signed [COMB_W-1:0] comb_delay_selected;
    wire signed [FIRST_INT_W-1:0] integrator_state_for_final;
    wire signed [FIRST_INT_W-1:0] high_rate_input;

    wire dsp_do_integrator;
    wire dsp_do_load;
    wire dsp_do_comb;
    wire [23:0] dsp_ab_low_lane;
    wire [23:0] dsp_ab_high_lane;
    wire signed [47:0] dsp_ab;
    wire signed [47:0] dsp_c;
    wire [6:0] dsp_opmode;
    wire [3:0] dsp_alumode;
    wire signed [47:0] dsp_p;
    wire [3:0] dsp_carryout;
    wire [2:0] integrator_top_sum_pending;

    wire signed [FINAL_W-1:0] final_integrator_input;
    wire signed [FINAL_W-1:0] final_integrator_next;
    wire signed [OUTPUT_W-1:0] normalized_output;
    (* use_dsp = "no" *) wire [3:0] burst_remaining_decrement;

    assign output_event = ce_out &&
                          (burst_pending || burst_remaining != 4'd0);
    assign first_output_event = ce_out && burst_pending &&
                                burst_remaining == 4'd0;

    assign comb_operand = dsp_p[COMB_W-1:0];
    assign comb_delay_selected =
        {{(COMB_W-COMB_DELAY_W){comb_delay0[COMB_DELAY_W-1]}},
         comb_delay0};
    assign high_rate_input = first_output_event ?
        {{(FIRST_INT_W-COMB_W){comb_operand[COMB_W-1]}}, comb_operand} :
        {{(FIRST_INT_W-COMB_W){hold_sample[COMB_W-1]}}, hold_sample};

    // Output integration has priority.  The two low-rate comb operations may
    // pause on an output event and resume on the following idle clock.
    assign dsp_do_integrator = output_event;
    // The formal chain's Stage3 output register holds x_in until the next
    // x_in_valid.  Load directly when the DSP is idle, or remember only the
    // one-bit request when a high-rate output event occupies this clock.
    assign dsp_do_load = !dsp_do_integrator &&
                         (comb_load_pending || x_in_valid);
    assign dsp_do_comb = !dsp_do_integrator && !dsp_do_load && comb_active;

    assign dsp_ab_low_lane = dsp_do_comb ?
        {{(24-COMB_W){comb_delay_selected[COMB_W-1]}},
         comb_delay_selected} : 24'd0;
    assign dsp_ab_high_lane = dsp_do_integrator ?
        high_rate_input[23:0] : 24'd0;
    assign dsp_ab = {dsp_ab_high_lane, dsp_ab_low_lane};

    // Load only replaces the low comb lane.  Feeding the registered high lane
    // back through C preserves the first-integrator state without a wide mux.
    assign dsp_c = {
        dsp_p[47:24],
        {{(24-DATA_W){x_in[DATA_W-1]}}, x_in}
    };
    assign dsp_opmode = dsp_do_load ? 7'b0110000 : 7'b0100011;
    assign dsp_alumode = dsp_do_comb ? 4'b0011 : 4'b0000;

    DSP48E1 #(
        .A_INPUT("DIRECT"),
        .B_INPUT("DIRECT"),
        .USE_DPORT("FALSE"),
        .USE_MULT("NONE"),
        .USE_PATTERN_DETECT("NO_PATDET"),
        .USE_SIMD("TWO24"),
        .AREG(0), .ACASCREG(0),
        .BREG(0), .BCASCREG(0),
        .CREG(0), .DREG(0), .ADREG(0), .MREG(0), .PREG(1),
        .INMODEREG(0), .OPMODEREG(0), .ALUMODEREG(0),
        .CARRYINREG(0), .CARRYINSELREG(0)
    ) u_comb_first_integrator_two24 (
        .P(dsp_p),
        .CARRYOUT(dsp_carryout),
        .A(dsp_ab[47:18]),
        .B(dsp_ab[17:0]),
        .C(dsp_c),
        .D(25'd0),
        .INMODE(5'b00000),
        .OPMODE(dsp_opmode),
        .ALUMODE(dsp_alumode),
        .CARRYINSEL(3'b000),
        .CARRYIN(1'b0),
        .ACIN(30'd0), .BCIN(18'd0), .PCIN(48'd0),
        .CARRYCASCIN(1'b0), .MULTSIGNIN(1'b0),
        .CLK(clk),
        .CEA1(1'b0), .CEA2(1'b0), .CEAD(1'b0),
        .CEALUMODE(1'b0), .CEB1(1'b0), .CEB2(1'b0),
        .CEC(1'b0), .CECARRYIN(1'b0), .CECTRL(1'b0),
        .CED(1'b0), .CEINMODE(1'b0), .CEM(1'b0),
        .CEP(dsp_do_integrator || dsp_do_load || dsp_do_comb),
        .RSTA(1'b0), .RSTALLCARRYIN(1'b0),
        .RSTALUMODE(1'b0), .RSTB(1'b0), .RSTC(1'b0),
        .RSTCTRL(1'b0), .RSTD(1'b0), .RSTINMODE(1'b0),
        .RSTM(1'b0), .RSTP(!rst_n),
        .ACOUT(), .BCOUT(), .CARRYCASCOUT(), .MULTSIGNOUT(),
        .OVERFLOW(), .PATTERNBDETECT(), .PATTERNDETECT(),
        .PCOUT(), .UNDERFLOW()
    );

    // TWO24 exposes the high-lane carry on CARRYOUT[3].  Only the upper two
    // bits remain in Fabric; overflow beyond bit 25 is intentionally modulo,
    // exactly matching the signed 26-bit reference integrator.
    // PREG registers both P and CARRYOUT.  Capture the operand upper bits on
    // the output event, then consume them together with the registered lane
    // carry on the following clock.  This keeps the Fabric upper bits aligned
    // with the low 24 bits held in the DSP P register.
    assign integrator_top_sum_pending =
        {1'b0, integrator_top} +
        {1'b0, integrator_top_operand_pending} +
        dsp_carryout[3];

    assign integrator_state_for_final =
        {integrator_top_sum_pending[1:0], dsp_p[47:24]};

    assign final_integrator_input =
        {{(FINAL_W-FIRST_INT_W){integrator_state_for_final[FIRST_INT_W-1]}},
         integrator_state_for_final};
    generate
        if (FINAL_PRUNE_LSB == 0) begin : gen_final_integrator_dsp
            (* use_dsp = "yes" *) wire signed [FINAL_W-1:0]
                final_sum;
            assign final_sum = final_integrator_state +
                               final_integrator_input;
            assign final_integrator_next = final_sum;
        end
        else begin : gen_unsupported_prune
            assign final_integrator_next = {FINAL_W{1'b0}};
        end
    endgenerate

    round_sat_shift_compact #(
        .IN_W(FINAL_W),
        .OUT_W(OUTPUT_W),
        .SHIFT_N(OUTPUT_SHIFT)
    ) u_round_cic_normalized_output (
        .din(final_integrator_next),
        .dout(normalized_output)
    );

    assign burst_remaining_dbg = {1'b0, burst_remaining};
    assign pending_dbg = burst_pending;
    assign comb_busy_dbg = comb_load_pending || comb_active ||
                           comb_stage_index;
    assign burst_remaining_decrement = burst_remaining - 4'd1;

    always @(posedge clk) begin
        if (!rst_n) begin
            comb_delay0 <= {COMB_DELAY_W{1'b0}};
            comb_delay1 <= {COMB_DELAY_W{1'b0}};
            comb_load_pending <= 1'b0;
            comb_stage_index <= 1'b0;
            comb_active <= 1'b0;
            hold_sample <= {COMB_W{1'b0}};
            integrator_top <= 2'sd0;
            integrator_top_operand_pending <= 2'd0;
            final_integrator_state <= {FINAL_W{1'b0}};
            final_pending <= 1'b0;
            burst_pending <= 1'b0;
            burst_remaining <= 4'd0;
            y_out <= {OUTPUT_W{1'b0}};
            y_out_valid <= 1'b0;
        end
        else begin
            y_out_valid <= 1'b0;

            if (x_in_valid) begin
                comb_load_pending <= 1'b1;
            end

            if (dsp_do_load) begin
                comb_load_pending <= 1'b0;
                comb_stage_index <= 1'b0;
                comb_active <= 1'b1;
            end
            else if (dsp_do_comb) begin
                comb_delay0 <= comb_delay1;
                comb_delay1 <= comb_operand[COMB_DELAY_W-1:0];
                if (comb_stage_index) begin
                    comb_active <= 1'b0;
                end
                else begin
                    comb_stage_index <= 1'b1;
                end
            end
            else if (!dsp_do_integrator && comb_stage_index) begin
                comb_stage_index <= 1'b0;
                burst_pending <= 1'b1;
            end

            if (final_pending) begin
                integrator_top <= integrator_top_sum_pending[1:0];
                final_integrator_state <= final_integrator_next;
                y_out <= normalized_output;
                y_out_valid <= 1'b1;
                final_pending <= 1'b0;
            end

            if (output_event) begin
                integrator_top_operand_pending <=
                    high_rate_input[FIRST_INT_W-1:24];
                final_pending <= 1'b1;

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
        if (rst_n && DATA_W != 21)
            $fatal(1, "TWO24 CIC candidate requires DATA_W=21");
        if (rst_n && OUTPUT_W != 20)
            $fatal(1, "TWO24 CIC candidate requires OUTPUT_W=20");
        if (rst_n && FINAL_PRUNE_LSB != 0)
            $fatal(1, "TWO24 CIC candidate requires FINAL_PRUNE_LSB=0");
        if (rst_n && x_in_valid && (comb_load_pending || comb_active ||
                                    comb_stage_index || burst_pending))
            $fatal(1, "TWO24 CIC input overwrite");
        if (rst_n && output_event && final_pending)
            $fatal(1, "TWO24 CIC requires a gap between output events");
    end
`endif
endmodule
