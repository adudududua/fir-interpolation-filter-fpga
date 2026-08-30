`timescale 1ns / 1ps

// Fixed 3-DSP candidate for the signed-off 21/20/0 CIC configuration.
// One DSP48E1 TWO24 operation evaluates the active 23-bit comb subtraction
// and the low 24 bits of the first 26-bit integrator in parallel.  Only the
// two upper integrator bits remain in Fabric.  The final 29-bit integrator is
// intentionally implemented with CARRY4, keeping the complete board at
// three DSP48E1 cells and four RAMB18E1 cells.
`ifdef CIC_TWO24_EQUIV
module cic_interp16_n3_hold2_dsp_ce_two24_candidate #(
`else
module cic_interp16_n3_hold2_dsp_ce #(
`endif
    parameter integer DATA_W = 21,
    parameter integer OUTPUT_W = 20,
    parameter integer FINAL_PRUNE_LSB = 0,
    parameter integer BURST_COUNTER_USE_DSP = 0,
    parameter integer INTEGRATOR_DSP_MODE = 1
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
    localparam integer COMB_W = DATA_W + 2;
    localparam integer COMB_DELAY_W = DATA_W + 1;
    localparam integer FIRST_INT_W = DATA_W + 5;
    localparam integer FINAL_W = DATA_W + 8 - FINAL_PRUNE_LSB;
    localparam integer OUTPUT_SHIFT =
        (CIC_ORDER-1)*RATE_LOG2 - FINAL_PRUNE_LSB;

    reg signed [COMB_DELAY_W-1:0] comb_delay0;
    reg signed [COMB_DELAY_W-1:0] comb_delay1;
    reg signed [COMB_W-1:0] comb_operand;
    reg comb_stage_index;
    reg comb_active;
    reg signed [COMB_W-1:0] hold_sample;
    reg signed [FIRST_INT_W-1:0] integrator_state;
    reg signed [FINAL_W-1:0] final_integrator_state;
    reg burst_pending;
    reg [3:0] burst_remaining;

    wire output_event;
    wire first_output_event;
    wire signed [COMB_W-1:0] comb_delay_selected;
    wire signed [FIRST_INT_W-1:0] high_rate_input;
    wire [23:0] comb_operand_lane;
    wire [23:0] comb_neg_delay_lane;
    wire signed [47:0] simd_ab;
    wire signed [47:0] simd_c;
    wire signed [47:0] simd_p;
    wire [3:0] simd_carryout;
    wire signed [COMB_W-1:0] comb_stage_result;
    wire [2:0] integrator_upper_sum;
    wire signed [FIRST_INT_W-1:0] integrator_next;
    wire signed [FINAL_W-1:0] final_input_rounded;
    (* use_dsp = "no" *) wire signed [FINAL_W-1:0]
        final_integrator_next;
    wire signed [OUTPUT_W-1:0] normalized_output;
    (* use_dsp = "no" *) wire [3:0] burst_remaining_decrement;

    assign output_event = ce_out &&
                          (burst_pending || burst_remaining != 4'd0);
    assign first_output_event = ce_out && burst_pending &&
                                burst_remaining == 4'd0;
    assign comb_delay_selected =
        {{(COMB_W-COMB_DELAY_W){comb_delay0[COMB_DELAY_W-1]}},
         comb_delay0};
    assign high_rate_input = first_output_event ?
        {{(FIRST_INT_W-COMB_W){comb_operand[COMB_W-1]}}, comb_operand} :
        {{(FIRST_INT_W-COMB_W){hold_sample[COMB_W-1]}}, hold_sample};

    assign comb_operand_lane =
        {{(24-COMB_W){comb_operand[COMB_W-1]}}, comb_operand};
    assign comb_neg_delay_lane =
        ~{{(24-COMB_W){comb_delay_selected[COMB_W-1]}},
           comb_delay_selected};
    assign simd_ab = {integrator_state[23:0], comb_operand_lane};
    assign simd_c = {high_rate_input[23:0], comb_neg_delay_lane};

    DSP48E1 #(
        .A_INPUT("DIRECT"), .B_INPUT("DIRECT"),
        .USE_DPORT("FALSE"), .USE_MULT("NONE"),
        .USE_PATTERN_DETECT("NO_PATDET"), .USE_SIMD("TWO24"),
        .AREG(0), .ACASCREG(0), .BREG(0), .BCASCREG(0),
        .CREG(0), .DREG(0), .ADREG(0), .MREG(0), .PREG(0),
        .INMODEREG(0), .OPMODEREG(0), .ALUMODEREG(0),
        .CARRYINREG(0), .CARRYINSELREG(0)
    ) u_comb_first_integrator_two24 (
        .P(simd_p), .CARRYOUT(simd_carryout),
        .A(simd_ab[47:18]), .B(simd_ab[17:0]), .C(simd_c),
        .D(25'd0), .INMODE(5'b00000), .OPMODE(7'b0110011),
        .ALUMODE(4'b0000), .CARRYINSEL(3'b000), .CARRYIN(1'b1),
        .ACIN(30'd0), .BCIN(18'd0), .PCIN(48'd0),
        .CARRYCASCIN(1'b0), .MULTSIGNIN(1'b0), .CLK(clk),
        .CEA1(1'b0), .CEA2(1'b0), .CEAD(1'b0),
        .CEALUMODE(1'b0), .CEB1(1'b0), .CEB2(1'b0),
        .CEC(1'b0), .CECARRYIN(1'b0), .CECTRL(1'b0),
        .CED(1'b0), .CEINMODE(1'b0), .CEM(1'b0), .CEP(1'b0),
        .RSTA(1'b0), .RSTALLCARRYIN(1'b0), .RSTALUMODE(1'b0),
        .RSTB(1'b0), .RSTC(1'b0), .RSTCTRL(1'b0), .RSTD(1'b0),
        .RSTINMODE(1'b0), .RSTM(1'b0), .RSTP(1'b0),
        .ACOUT(), .BCOUT(), .CARRYCASCOUT(), .MULTSIGNOUT(),
        .OVERFLOW(), .PATTERNBDETECT(), .PATTERNDETECT(),
        .PCOUT(), .UNDERFLOW()
    );

    assign comb_stage_result = simd_p[COMB_W-1:0];
    assign integrator_upper_sum =
        {1'b0, integrator_state[FIRST_INT_W-1:24]} +
        {1'b0, high_rate_input[FIRST_INT_W-1:24]} +
        simd_carryout[3];
    assign integrator_next =
        {integrator_upper_sum[1:0], simd_p[47:24]};

    generate
        if (FINAL_PRUNE_LSB == 0) begin : gen_no_final_pruning
            assign final_input_rounded = integrator_next;
        end
        else begin : gen_final_pruning
            round_sat_shift_compact #(
                .IN_W(FIRST_INT_W), .OUT_W(FINAL_W),
                .SHIFT_N(FINAL_PRUNE_LSB)
            ) u_round_final_integrator_input (
                .din(integrator_next), .dout(final_input_rounded)
            );
        end
    endgenerate

    assign final_integrator_next =
        final_integrator_state + final_input_rounded;

    round_sat_shift_compact #(
        .IN_W(FINAL_W), .OUT_W(OUTPUT_W), .SHIFT_N(OUTPUT_SHIFT)
    ) u_round_cic_normalized_output (
        .din(final_integrator_next), .dout(normalized_output)
    );

    assign burst_remaining_dbg = {1'b0, burst_remaining};
    assign pending_dbg = burst_pending;
    assign comb_busy_dbg = comb_active || comb_stage_index;
    assign burst_remaining_decrement = burst_remaining - 4'd1;

    always @(posedge clk) begin
        if (!rst_n) begin
            comb_delay0 <= {COMB_DELAY_W{1'b0}};
            comb_delay1 <= {COMB_DELAY_W{1'b0}};
            comb_operand <= {COMB_W{1'b0}};
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
                comb_operand <=
                    {{(COMB_W-DATA_W){x_in[DATA_W-1]}}, x_in};
                comb_stage_index <= 1'b0;
                comb_active <= 1'b1;
            end
            if (comb_active) begin
                comb_delay0 <= comb_delay1;
                comb_delay1 <= comb_operand[COMB_DELAY_W-1:0];
                comb_operand <= comb_stage_result;
                if (comb_stage_index)
                    comb_active <= 1'b0;
                else
                    comb_stage_index <= 1'b1;
            end
            else if (comb_stage_index) begin
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
                else if (burst_remaining == 4'd1)
                    burst_remaining <= 4'd0;
                else
                    burst_remaining <= burst_remaining_decrement;
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && (DATA_W != 21 || OUTPUT_W != 20 ||
                      FINAL_PRUNE_LSB != 0 || INTEGRATOR_DSP_MODE != 1 ||
                      BURST_COUNTER_USE_DSP != 0))
            $fatal(1, "TWO24 mode-1 CIC requires 21/20/0/1/0 parameters");
        if (rst_n && x_in_valid && (comb_active || comb_stage_index ||
                                    burst_pending))
            $fatal(1, "TWO24 mode-1 CIC input overwrite");
    end
`endif
endmodule
