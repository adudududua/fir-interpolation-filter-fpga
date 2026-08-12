`timescale 1ns / 1ps

// Mode-1 candidate: two fabric combs, Hold16, and one TWO24 DSP for both
// high-rate integrators.  Its numeric output sequence matches the reference;
// y_out_valid is delayed by one clock to retire the registered DSP result.
module cic_interp16_n3_hold2_integrator_pair_mode1_candidate #(
    parameter integer DATA_W = 21,
    parameter integer OUTPUT_W = 20,
    parameter integer FINAL_PRUNE_LSB = 0,
    parameter integer BURST_COUNTER_USE_DSP = 0
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ce_out,
    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,
    output wire signed [OUTPUT_W-1:0]   y_out,
    output wire                         y_out_valid,
    output wire [4:0]                   burst_remaining_dbg,
    output wire                         pending_dbg,
    output wire                         comb_busy_dbg
);

    localparam integer CIC_ORDER = 3;
    localparam integer RATE_LOG2 = 4;
    localparam integer COMB_W = DATA_W+2;
    localparam integer COMB_DELAY_W = DATA_W+1;
    localparam integer FIRST_INT_W = DATA_W+5;
    localparam integer FINAL_W = DATA_W+8-FINAL_PRUNE_LSB;
    localparam integer OUTPUT_SHIFT =
        (CIC_ORDER-1)*RATE_LOG2-FINAL_PRUNE_LSB;

    reg signed [COMB_DELAY_W-1:0] comb_delay0;
    reg signed [COMB_DELAY_W-1:0] comb_delay1;
    reg signed [COMB_W-1:0] comb_operand;
    reg comb_stage_index;
    reg comb_active;
    reg align_pending;
    reg signed [COMB_W-1:0] hold_sample;
    reg burst_pending;
    reg [3:0] burst_remaining;

    wire signed [COMB_W-1:0] x_comb_extended;
    wire signed [COMB_W-1:0] comb_delay_selected;
    (* use_dsp = "no" *) wire signed [COMB_W-1:0] comb_stage_result;
    wire output_event;
    wire first_output_event;
    wire signed [FIRST_INT_W-1:0] high_rate_input;
    wire signed [FIRST_INT_W-1:0] pair_a;
    wire signed [FINAL_W-1:0] pair_q;
    wire signed [FINAL_W-1:0] pair_b;
    wire pair_valid;
    wire signed [OUTPUT_W-1:0] normalized_output;
    (* use_dsp = "no" *) wire [3:0] burst_remaining_decrement;

    assign x_comb_extended =
        {{(COMB_W-DATA_W){x_in[DATA_W-1]}}, x_in};
    assign comb_delay_selected =
        {{(COMB_W-COMB_DELAY_W){comb_delay0[COMB_DELAY_W-1]}},
         comb_delay0};
    assign comb_stage_result = comb_operand-comb_delay_selected;
    assign output_event = ce_out &&
                          (burst_pending || burst_remaining != 4'd0);
    assign first_output_event = ce_out && burst_pending &&
                                burst_remaining == 4'd0;
    assign high_rate_input = first_output_event ?
        {{(FIRST_INT_W-COMB_W){comb_operand[COMB_W-1]}}, comb_operand} :
        {{(FIRST_INT_W-COMB_W){hold_sample[COMB_W-1]}}, hold_sample};
    assign burst_remaining_decrement = burst_remaining-4'd1;

    nf_cic_two24_integrator_pair_mode1 u_two24_integrator_pair (
        .clk(clk),
        .rst_n(rst_n),
        .event_ce(output_event),
        .u_in(high_rate_input),
        .a_out(pair_a),
        .q_out(pair_q),
        .b_out(pair_b),
        .out_valid(pair_valid)
    );

    generate
        if (FINAL_PRUNE_LSB == 0) begin : gen_no_final_pruning
            round_sat_shift_compact #(
                .IN_W(FINAL_W), .OUT_W(OUTPUT_W),
                .SHIFT_N(OUTPUT_SHIFT)
            ) u_round_cic_normalized_output (
                .din(pair_b), .dout(normalized_output)
            );
        end
        else begin : gen_unsupported_pruning
            assign normalized_output = {OUTPUT_W{1'bx}};
        end
    endgenerate

    assign y_out = normalized_output;
    assign y_out_valid = pair_valid;
    // Compatibility alias used by the full-chain reset audit hierarchy.
    wire signed [FINAL_W-1:0] final_integrator_state = pair_q;
    assign burst_remaining_dbg = {1'b0, burst_remaining};
    assign pending_dbg = burst_pending;
    assign comb_busy_dbg = comb_active || align_pending;

    always @(posedge clk) begin
        if (!rst_n) begin
            comb_delay0 <= {COMB_DELAY_W{1'b0}};
            comb_delay1 <= {COMB_DELAY_W{1'b0}};
            comb_operand <= {COMB_W{1'b0}};
            comb_stage_index <= 1'b0;
            comb_active <= 1'b0;
            align_pending <= 1'b0;
            hold_sample <= {COMB_W{1'b0}};
            burst_pending <= 1'b0;
            burst_remaining <= 4'd0;
        end
        else begin
            if (x_in_valid) begin
                comb_operand <= x_comb_extended;
                comb_stage_index <= 1'b0;
                comb_active <= 1'b1;
            end
            if (comb_active) begin
                comb_delay0 <= comb_delay1;
                comb_delay1 <= comb_operand[COMB_DELAY_W-1:0];
                comb_operand <= comb_stage_result;
                if (comb_stage_index) begin
                    comb_active <= 1'b0;
                    align_pending <= 1'b1;
                end
                else begin
                    comb_stage_index <= 1'b1;
                end
            end
            if (align_pending) begin
                align_pending <= 1'b0;
                burst_pending <= 1'b1;
            end
            if (output_event) begin
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
        if (rst_n && x_in_valid && (comb_active || align_pending ||
                                    burst_pending))
            $fatal(1, "TWO24 CIC input overwrite");
        if (rst_n && BURST_COUNTER_USE_DSP != 0)
            $fatal(1, "TWO24 CIC only supports a LUT burst counter");
        if (rst_n && FINAL_PRUNE_LSB != 0)
            $fatal(1, "TWO24 candidate requires FINAL_PRUNE_LSB=0");
        if (rst_n && (DATA_W != 21 || FIRST_INT_W != 26 || FINAL_W != 29))
            $fatal(1, "TWO24 candidate requires 21/26/29-bit widths");
    end
`endif
endmodule
