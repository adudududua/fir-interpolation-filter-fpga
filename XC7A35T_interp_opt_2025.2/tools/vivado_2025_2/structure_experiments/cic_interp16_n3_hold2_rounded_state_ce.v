`timescale 1ns / 1ps

// Exact fixed-2-DSP CIC candidate with a quotient/residual final state.
//
// The reference final state S is represented as S = 256*Q + R, where Q is
// the signed round-to-nearest/away-from-zero value and -128 <= R <= 128.
// Updating Q directly folds the output rounding increment into its adder and
// removes the separate wide rounding carry chain.  Throughput, valid timing,
// and output samples remain identical to mode 0 of the reference module.
module cic_interp16_n3_hold2_rounded_state_ce #(
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
    localparam integer RESIDUAL_W = 9;
    localparam integer QUOTIENT_W = FINAL_W - 8 + 1;
    localparam integer RESIDUAL_SUM_W = FIRST_INT_W + 1;

    reg signed [COMB_DELAY_W-1:0] comb_delay0;
    reg signed [COMB_DELAY_W-1:0] comb_delay1;
    reg signed [COMB_W-1:0] comb_operand;
    reg comb_stage_index;
    reg comb_active;
    reg signed [COMB_W-1:0] hold_sample;

    reg signed [FIRST_INT_W-1:0] integrator_state;
    reg signed [QUOTIENT_W-1:0] final_quotient_state;
    reg signed [RESIDUAL_W-1:0] final_residual_state;

    reg burst_pending;
    reg [3:0] burst_remaining;

    wire signed [COMB_W-1:0] x_comb_extended;
    wire signed [COMB_W-1:0] comb_delay_selected;
    (* use_dsp = "no" *) wire signed [COMB_W-1:0] comb_stage_result;
    wire output_event;
    wire first_output_event;
    wire signed [FIRST_INT_W-1:0] high_rate_input;
    (* use_dsp = "no" *) wire signed [FIRST_INT_W-1:0] integrator_next;

    (* use_dsp = "no" *) wire signed [RESIDUAL_SUM_W-1:0]
        residual_input_sum;
    wire quotient_round_increment;
    wire signed [QUOTIENT_W-1:0] quotient_delta_floor;
    (* use_dsp = "no" *) wire signed [QUOTIENT_W-1:0]
        tentative_quotient_floor;
    (* use_dsp = "no" *) wire signed [QUOTIENT_W-1:0]
        final_quotient_next;
    wire signed [RESIDUAL_W-1:0] final_residual_next;
    wire quotient_is_sign_extension;
    wire signed [OUTPUT_W-1:0] normalized_output;
    (* use_dsp = "no" *) wire [3:0] burst_remaining_decrement;

    localparam signed [OUTPUT_W-1:0] OUTPUT_MAX =
        {1'b0, {(OUTPUT_W-1){1'b1}}};
    localparam signed [OUTPUT_W-1:0] OUTPUT_MIN =
        {1'b1, {(OUTPUT_W-1){1'b0}}};

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
    assign high_rate_input = first_output_event ?
        {{(FIRST_INT_W-COMB_W){comb_operand[COMB_W-1]}}, comb_operand} :
        {{(FIRST_INT_W-COMB_W){hold_sample[COMB_W-1]}}, hold_sample};
    assign integrator_next = integrator_state + high_rate_input;

    assign residual_input_sum =
        {{(RESIDUAL_SUM_W-RESIDUAL_W){final_residual_state[RESIDUAL_W-1]}},
         final_residual_state} +
        {{(RESIDUAL_SUM_W-FIRST_INT_W){integrator_next[FIRST_INT_W-1]}},
         integrator_next};
    assign quotient_delta_floor =
        {{(QUOTIENT_W-(RESIDUAL_SUM_W-8)){
            residual_input_sum[RESIDUAL_SUM_W-1]}},
         residual_input_sum[RESIDUAL_SUM_W-1:8]};
    assign tentative_quotient_floor = final_quotient_state +
                                      quotient_delta_floor;
    // At an exact half-LSB, ties move away from zero.  The sign of the
    // complete updated state equals the floor quotient sign, not the sign of
    // the local residual-plus-input term.
    assign quotient_round_increment = residual_input_sum[7] &&
        (!tentative_quotient_floor[QUOTIENT_W-1] ||
         (|residual_input_sum[6:0]));
    assign final_quotient_next = tentative_quotient_floor +
                                 quotient_round_increment;
    assign final_residual_next =
        {quotient_round_increment, residual_input_sum[7:0]};

    assign quotient_is_sign_extension =
        final_quotient_next[QUOTIENT_W-1:OUTPUT_W] ==
        {(QUOTIENT_W-OUTPUT_W){final_quotient_next[OUTPUT_W-1]}};
    assign normalized_output = quotient_is_sign_extension ?
        final_quotient_next[OUTPUT_W-1:0] :
        (final_quotient_next[QUOTIENT_W-1] ? OUTPUT_MIN : OUTPUT_MAX);

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
            final_quotient_state <= {QUOTIENT_W{1'b0}};
            final_residual_state <= {RESIDUAL_W{1'b0}};
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
                final_quotient_state <= final_quotient_next;
                final_residual_state <= final_residual_next;
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
        if (rst_n && (DATA_W != 21 || OUTPUT_W != 20 ||
                      FINAL_PRUNE_LSB != 0))
            $fatal(1, "Rounded-state CIC requires 21/20/0 widths");
        if (rst_n && x_in_valid &&
            (comb_active || comb_stage_index || burst_pending))
            $fatal(1, "Rounded-state CIC input overwrite");
    end
`endif

endmodule
