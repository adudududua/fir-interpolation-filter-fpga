`timescale 1ns / 1ps

// Exact R=16, N=3 CIC interpolation rewrite:
//
//   comb^3 -> zero stuffing -> integrator^3
//     == comb^2 -> hold each sample for 16 enables -> integrator^2
//
// One low-rate comb/high-rate integrator pair is replaced by the exact
// length-16 hold response.  The first integrator has the exact bound
// 32*max|x| (DATA_W+5 bits); the second integrator is the non-negative
// triangular interpolation kernel with DC gain 16^2 (DATA_W+8 bits).
// These widths preserve the original right-shift-by-8 output exactly while
// avoiding eleven unreachable state bits.  At the 4-DSP national-finals
// point, the former first-integrator DSP is reassigned to the serial comb:
// its P register holds comb_operand and its ALU performs both differences.
// The first 26-bit integrator moves to CARRY4 while the final integrator
// remains in DSP48, preserving the total DSP count but removing the wider
// comb subtract/register-input network from Fabric.  Modes 1/0 keep the
// historical one-DSP/zero-DSP Pareto mappings and therefore use a CARRY comb.
module cic_interp16_n3_hold2_dsp_ce #(
    parameter integer DATA_W = 21,
    parameter integer OUTPUT_W = 20,
    parameter integer FINAL_PRUNE_LSB = 0,
    parameter integer BURST_COUNTER_USE_DSP = 0,
    parameter integer INTEGRATOR_DSP_MODE = 2
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

    localparam integer CIC_ORDER = 3;
    localparam integer RATE_LOG2 = 4;
    localparam integer LEGACY_FULL_W = DATA_W + CIC_ORDER*RATE_LOG2;
    localparam integer COMB_W = DATA_W + 2;
    localparam integer COMB_DELAY_W = DATA_W + 1;
    localparam integer FIRST_INT_W = DATA_W + 5;
    localparam integer FINAL_W = DATA_W + 8 - FINAL_PRUNE_LSB;
    localparam integer OUTPUT_SHIFT =
        (CIC_ORDER-1)*RATE_LOG2 - FINAL_PRUNE_LSB;

    // Rotate two uniformly sized histories.  At stage zero delay0 stores
    // the previous input; after the rotation it stores the previous first
    // difference for stage one.  No wide stage-select mux is required.
    reg signed [COMB_DELAY_W-1:0] comb_delay0;
    reg signed [COMB_DELAY_W-1:0] comb_delay1;
    wire signed [COMB_W-1:0] comb_operand;
    reg signed [COMB_W-1:0] comb_operand_fabric;
    reg comb_stage_index;
    reg comb_active;
    reg signed [COMB_W-1:0] hold_sample;

    // One hidden high-rate integrator plus the externally visible final
    // integrator gives the two integrators required after the Hold16 block.
    reg signed [FIRST_INT_W-1:0] integrator_state;
    reg signed [FINAL_W-1:0] final_integrator_state;

    reg burst_pending;
    reg [3:0] burst_remaining;

    wire signed [COMB_W-1:0] x_comb_extended;
    wire signed [COMB_W-1:0] comb_delay_selected;
    wire signed [47:0] comb_dsp_p;
    wire signed [47:0] comb_dsp_ab;
    wire signed [47:0] comb_dsp_c;
    wire [6:0] comb_dsp_opmode;
    wire [3:0] comb_dsp_alumode;
    (* use_dsp = "no" *) wire signed [COMB_W-1:0] comb_stage_result;
    wire output_event;
    wire first_output_event;
    wire signed [FIRST_INT_W-1:0] high_rate_input;
    wire signed [FIRST_INT_W-1:0] integrator_next;
    wire signed [FINAL_W-1:0] final_input_rounded;
    wire signed [FINAL_W-1:0] final_integrator_next;
    wire signed [OUTPUT_W-1:0] normalized_output;
    (* use_dsp = "no" *) wire [3:0] burst_remaining_decrement;

    assign x_comb_extended =
        {{(COMB_W-DATA_W){x_in[DATA_W-1]}}, x_in};
    assign comb_delay_selected =
        {{(COMB_W-COMB_DELAY_W){comb_delay0[COMB_DELAY_W-1]}},
         comb_delay0};
    assign comb_stage_result = comb_operand - comb_delay_selected;
    assign comb_dsp_ab =
        {{(48-COMB_W){comb_delay_selected[COMB_W-1]}},
         comb_delay_selected};
    assign comb_dsp_c =
        {{(48-COMB_W){x_comb_extended[COMB_W-1]}},
         x_comb_extended};
    // x_in_valid loads C directly into P.  Each active comb cycle then
    // evaluates P-A:B; ALUMODE=0011 is the DSP48E1 Z-X-Y operation.
    assign comb_dsp_opmode = x_in_valid ? 7'b0110000 : 7'b0100011;
    assign comb_dsp_alumode = x_in_valid ? 4'b0000 : 4'b0011;

    generate
        if (INTEGRATOR_DSP_MODE >= 2) begin : gen_comb_dsp_role_exchange
            assign comb_operand = comb_dsp_p[COMB_W-1:0];

            DSP48E1 #(
                .A_INPUT("DIRECT"),
                .B_INPUT("DIRECT"),
                .USE_DPORT("FALSE"),
                .USE_MULT("NONE"),
                .USE_PATTERN_DETECT("NO_PATDET"),
                .USE_SIMD("ONE48"),
                .AREG(0), .ACASCREG(0),
                .BREG(0), .BCASCREG(0),
                .CREG(0), .DREG(0), .ADREG(0), .MREG(0), .PREG(1),
                .INMODEREG(0), .OPMODEREG(0), .ALUMODEREG(0),
                .CARRYINREG(0), .CARRYINSELREG(0)
            ) u_cic_comb_dsp48e1 (
                .P(comb_dsp_p),
                .A(comb_dsp_ab[47:18]),
                .B(comb_dsp_ab[17:0]),
                .C(comb_dsp_c),
                .D(25'd0),
                .INMODE(5'b00000),
                .OPMODE(comb_dsp_opmode),
                .ALUMODE(comb_dsp_alumode),
                .CARRYINSEL(3'b000),
                .CARRYIN(1'b0),
                .ACIN(30'd0), .BCIN(18'd0), .PCIN(48'd0),
                .CARRYCASCIN(1'b0), .MULTSIGNIN(1'b0),
                .CLK(clk),
                .CEA1(1'b0), .CEA2(1'b0), .CEAD(1'b0),
                .CEALUMODE(1'b0), .CEB1(1'b0), .CEB2(1'b0),
                .CEC(1'b0), .CECARRYIN(1'b0), .CECTRL(1'b0),
                .CED(1'b0), .CEINMODE(1'b0), .CEM(1'b0),
                .CEP(x_in_valid || comb_active),
                .RSTA(1'b0), .RSTALLCARRYIN(1'b0),
                .RSTALUMODE(1'b0), .RSTB(1'b0), .RSTC(1'b0),
                .RSTCTRL(1'b0), .RSTD(1'b0), .RSTINMODE(1'b0),
                .RSTM(1'b0), .RSTP(!rst_n)
            );
        end
        else begin : gen_comb_carry_pareto
            assign comb_operand = comb_operand_fabric;
        end
    endgenerate

    assign output_event = ce_out &&
                          (burst_pending || burst_remaining != 4'd0);
    assign first_output_event = ce_out && burst_pending &&
                                burst_remaining == 4'd0;
    // A new low-rate comb result is ready before the preceding 16-sample
    // hold burst has finished.  Keep hold_sample as the active burst value
    // and use comb_operand only on the first output of the next burst.
    assign high_rate_input = first_output_event ?
        {{(FIRST_INT_W-COMB_W){comb_operand[COMB_W-1]}}, comb_operand} :
        {{(FIRST_INT_W-COMB_W){hold_sample[COMB_W-1]}}, hold_sample};

    generate
        if (INTEGRATOR_DSP_MODE >= 2) begin : gen_first_integrator_carry_for_comb_dsp
            (* use_dsp = "no" *) wire signed [FIRST_INT_W-1:0]
                first_integrator_sum;
            assign first_integrator_sum = integrator_state + high_rate_input;
            assign integrator_next = first_integrator_sum;
        end
        else begin : gen_first_integrator_carry
            (* use_dsp = "no" *) wire signed [FIRST_INT_W-1:0]
                first_integrator_sum;
            assign first_integrator_sum = integrator_state + high_rate_input;
            assign integrator_next = first_integrator_sum;
        end
    endgenerate

    generate
        if (INTEGRATOR_DSP_MODE >= 1) begin : gen_final_integrator_dsp
            (* use_dsp = "yes" *) wire signed [FINAL_W-1:0]
                final_integrator_sum;
            assign final_integrator_sum = final_integrator_state +
                                          final_input_rounded;
            assign final_integrator_next = final_integrator_sum;
        end
        else begin : gen_final_integrator_carry
            (* use_dsp = "no" *) wire signed [FINAL_W-1:0]
                final_integrator_sum;
            assign final_integrator_sum = final_integrator_state +
                                          final_input_rounded;
            assign final_integrator_next = final_integrator_sum;
        end
    endgenerate

    assign burst_remaining_dbg = {1'b0, burst_remaining};
    assign pending_dbg = burst_pending;
    // Once the second difference completes, comb_stage_index remains high
    // for the legacy one-cycle alignment slot.  Reusing it as that state
    // removes the separate align_pending flag without changing latency.
    assign comb_busy_dbg = comb_active || comb_stage_index;
    assign burst_remaining_decrement = burst_remaining - 4'd1;

    generate
        if (FINAL_PRUNE_LSB == 0) begin : gen_no_final_pruning
            assign final_input_rounded = integrator_next;
        end
        else begin : gen_final_pruning
            round_sat_shift_compact #(
                .IN_W    (FIRST_INT_W),
                .OUT_W   (FINAL_W),
                .SHIFT_N (FINAL_PRUNE_LSB)
            ) u_round_final_integrator_input (
                .din  (integrator_next),
                .dout (final_input_rounded)
            );
        end
    endgenerate

    round_sat_shift_compact #(
        .IN_W    (FINAL_W),
        .OUT_W   (OUTPUT_W),
        .SHIFT_N (OUTPUT_SHIFT)
    ) u_round_cic_normalized_output (
        .din  (final_integrator_next),
        .dout (normalized_output)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            comb_delay0 <= {COMB_DELAY_W{1'b0}};
            comb_delay1 <= {COMB_DELAY_W{1'b0}};
            comb_operand_fabric <= {COMB_W{1'b0}};
            comb_stage_index <= 1'b0;
            comb_active <= 1'b0;
            hold_sample <= {COMB_W{1'b0}};

            integrator_state <= {FIRST_INT_W{1'b0}};
            final_integrator_state <= {FINAL_W{1'b0}};
            burst_pending <= 1'b0;
            burst_remaining <= 4'd0;
            y_out <= {OUTPUT_W{1'b0}};
            y_out_valid <= 1'b0;
        end
        else begin
            y_out_valid <= 1'b0;

            if (x_in_valid) begin
                if (INTEGRATOR_DSP_MODE < 2)
                    comb_operand_fabric <= x_comb_extended;
                comb_stage_index <= 1'b0;
                comb_active <= 1'b1;
            end

            if (comb_active) begin
                comb_delay0 <= comb_delay1;
                comb_delay1 <= comb_operand[COMB_DELAY_W-1:0];
                if (INTEGRATOR_DSP_MODE < 2)
                    comb_operand_fabric <= comb_stage_result;

                if (comb_stage_index) begin
                    comb_active <= 1'b0;
                end
                else begin
                    comb_stage_index <= 1'b1;
                end
            end
            else if (comb_stage_index) begin
                // Preserve the legacy serial-comb fixed latency so the
                // valid streams can still be compared cycle by cycle.
                comb_stage_index <= 1'b0;
                burst_pending <= 1'b1;
            end

            if (output_event) begin
                integrator_state <= integrator_next;
                final_integrator_state <= final_integrator_next;
                y_out <= normalized_output;
                y_out_valid <= 1'b1;

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
        if (rst_n && x_in_valid && (comb_active || comb_stage_index ||
                                    burst_pending))
            $fatal(1, "N3 Hold CIC input overwrite");
        if (rst_n && BURST_COUNTER_USE_DSP != 0)
            $fatal(1, "N3 Hold CIC only supports LUT burst counter");
        if (rst_n && OUTPUT_SHIFT < 1)
            $fatal(1, "N3 Hold CIC output normalization shift is invalid");
        if (rst_n && (INTEGRATOR_DSP_MODE < 0 ||
                      INTEGRATOR_DSP_MODE > 2))
            $fatal(1, "N3 Hold CIC INTEGRATOR_DSP_MODE must be 0, 1, or 2");
        if (rst_n && LEGACY_FULL_W < FINAL_W)
            $fatal(1, "N3 Hold CIC derived width exceeds legacy width");
    end
`endif

endmodule
