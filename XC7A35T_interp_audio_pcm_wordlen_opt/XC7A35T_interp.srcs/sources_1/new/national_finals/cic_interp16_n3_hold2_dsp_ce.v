`timescale 1ns / 1ps

// Exact R=16, N=3 CIC interpolation rewrite:
//
//   comb^3 -> zero stuffing -> integrator^3
//     == comb^2 -> hold each sample for 16 enables -> integrator^2
//
// One low-rate comb/high-rate integrator pair is replaced by the exact
// length-16 hold response.  The full 33-bit modulo width and the original
// right-shift-by-8 output normalization are retained.
(* use_dsp = "yes" *)
module cic_interp16_n3_hold2_dsp_ce #(
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
    output reg  signed [OUTPUT_W-1:0]   y_out,
    output reg                          y_out_valid,
    output wire [4:0]                   burst_remaining_dbg,
    output wire                         pending_dbg,
    output wire                         comb_busy_dbg
);

    localparam integer CIC_ORDER = 3;
    localparam integer RATE_LOG2 = 4;
    localparam integer FULL_W = DATA_W + CIC_ORDER*RATE_LOG2;
    localparam integer COMB_W = DATA_W + 2;
    localparam integer COMB_DELAY_W = DATA_W + 1;
    localparam integer FINAL_W = FULL_W - FINAL_PRUNE_LSB;
    localparam integer OUTPUT_SHIFT =
        (CIC_ORDER-1)*RATE_LOG2 - FINAL_PRUNE_LSB;

    // Rotate two uniformly sized histories.  At stage zero delay0 stores
    // the previous input; after the rotation it stores the previous first
    // difference for stage one.  No wide stage-select mux is required.
    reg signed [COMB_DELAY_W-1:0] comb_delay0;
    reg signed [COMB_DELAY_W-1:0] comb_delay1;
    reg signed [COMB_W-1:0] comb_operand;
    reg comb_stage_index;
    reg comb_active;
    reg align_pending;
    reg signed [COMB_W-1:0] hold_sample;

    // One hidden high-rate integrator plus the externally visible final
    // integrator gives the two integrators required after the Hold16 block.
    reg signed [FULL_W-1:0] integrator_state;
    reg signed [FINAL_W-1:0] final_integrator_state;

    reg burst_pending;
    reg [3:0] burst_remaining;

    wire signed [COMB_W-1:0] x_comb_extended;
    wire signed [COMB_W-1:0] comb_delay_selected;
    (* use_dsp = "no" *) wire signed [COMB_W-1:0] comb_stage_result;
    wire output_event;
    wire first_output_event;
    wire signed [FULL_W-1:0] high_rate_input;
    wire signed [FULL_W-1:0] integrator_next;
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

    assign output_event = ce_out &&
                          (burst_pending || burst_remaining != 4'd0);
    assign first_output_event = ce_out && burst_pending &&
                                burst_remaining == 4'd0;
    // A new low-rate comb result is ready before the preceding 16-sample
    // hold burst has finished.  Keep hold_sample as the active burst value
    // and use comb_operand only on the first output of the next burst.
    assign high_rate_input = first_output_event ?
        {{(FULL_W-COMB_W){comb_operand[COMB_W-1]}}, comb_operand} :
        {{(FULL_W-COMB_W){hold_sample[COMB_W-1]}}, hold_sample};
    assign integrator_next = integrator_state + high_rate_input;
    assign final_integrator_next = final_integrator_state +
                                   final_input_rounded;

    assign burst_remaining_dbg = {1'b0, burst_remaining};
    assign pending_dbg = burst_pending;
    assign comb_busy_dbg = comb_active || align_pending;
    assign burst_remaining_decrement = burst_remaining - 4'd1;

    generate
        if (FINAL_PRUNE_LSB == 0) begin : gen_no_final_pruning
            assign final_input_rounded = integrator_next;
        end
        else begin : gen_final_pruning
            round_sat_shift_compact #(
                .IN_W    (FULL_W),
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
            comb_operand <= {COMB_W{1'b0}};
            comb_stage_index <= 1'b0;
            comb_active <= 1'b0;
            align_pending <= 1'b0;
            hold_sample <= {COMB_W{1'b0}};

            integrator_state <= {FULL_W{1'b0}};
            final_integrator_state <= {FINAL_W{1'b0}};
            burst_pending <= 1'b0;
            burst_remaining <= 4'd0;
            y_out <= {OUTPUT_W{1'b0}};
            y_out_valid <= 1'b0;
        end
        else begin
            y_out_valid <= 1'b0;

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
                    // Preserve the legacy serial-comb fixed latency so the
                    // valid streams can be compared cycle by cycle.
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
        if (rst_n && x_in_valid && (comb_active || align_pending ||
                                    burst_pending))
            $fatal(1, "N3 Hold CIC input overwrite");
        if (rst_n && BURST_COUNTER_USE_DSP != 0)
            $fatal(1, "N3 Hold CIC only supports LUT burst counter");
        if (rst_n && OUTPUT_SHIFT < 1)
            $fatal(1, "N3 Hold CIC output normalization shift is invalid");
    end
`endif

endmodule
