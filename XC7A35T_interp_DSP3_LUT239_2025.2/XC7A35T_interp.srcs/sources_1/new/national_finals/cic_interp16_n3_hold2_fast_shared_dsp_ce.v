`timescale 1ns / 1ps

// High-clock exact R=16, N=3 CIC rewrite.
//
// The mathematical transform is identical to cic_interp16_n3_hold2_dsp_ce:
//
//   comb^3 -> up16 -> integrator^3
//     == comb^2 -> Hold16 -> integrator^2
//
// ce_out must be separated by at least two clk cycles.  That timing margin
// allows one DSP48 adder to execute the two recursive integrators on adjacent
// clocks.  A second DSP48 executes the two low-rate comb subtractions.  Thus
// the CIC still uses two DSP blocks, but no wide fabric add/subtract data path.
module cic_interp16_n3_hold2_fast_shared_dsp_ce #(
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
    output wire                         comb_busy_dbg,
    output wire                         integrator_busy_dbg
);

    localparam integer CIC_ORDER = 3;
    localparam integer RATE_LOG2 = 4;
    localparam integer COMB_W = DATA_W + 2;
    localparam integer COMB_DELAY_W = DATA_W + 1;
    localparam integer FIRST_INT_W = DATA_W + 5;
    localparam integer FINAL_W = DATA_W + 8;
    localparam integer OUTPUT_SHIFT =
        (CIC_ORDER-1)*RATE_LOG2 - FINAL_PRUNE_LSB;

    reg signed [COMB_DELAY_W-1:0] comb_delay0;
    reg signed [COMB_DELAY_W-1:0] comb_delay1;
    reg signed [COMB_W-1:0] comb_operand;
    reg comb_stage_index;
    reg comb_active;
    reg align_pending;
    reg signed [COMB_W-1:0] hold_sample;

    reg signed [FIRST_INT_W-1:0] integrator_state;
    reg signed [FINAL_W-1:0] final_integrator_state;
    reg integrator_second_phase;

    reg burst_pending;
    reg [3:0] burst_remaining;

    wire signed [COMB_W-1:0] x_comb_extended;
    wire signed [COMB_W-1:0] comb_delay_selected;
    (* use_dsp = "yes" *) wire signed [COMB_W-1:0]
        comb_stage_result;

    wire output_event;
    wire first_output_event;
    wire signed [FIRST_INT_W-1:0] high_rate_input;
    wire signed [FINAL_W-1:0] shared_integrator_a;
    wire signed [FINAL_W-1:0] shared_integrator_b;
    (* use_dsp = "yes" *) wire signed [FINAL_W-1:0]
        shared_integrator_sum;
    wire signed [OUTPUT_W-1:0] normalized_output;
    (* use_dsp = "no" *) wire [3:0] burst_remaining_decrement;

    assign x_comb_extended =
        {{(COMB_W-DATA_W){x_in[DATA_W-1]}}, x_in};
    assign comb_delay_selected =
        {{(COMB_W-COMB_DELAY_W){comb_delay0[COMB_DELAY_W-1]}},
         comb_delay0};
    assign comb_stage_result = comb_operand - comb_delay_selected;

    assign output_event = ce_out && !integrator_second_phase &&
                          (burst_pending || burst_remaining != 4'd0);
    assign first_output_event = output_event && burst_pending &&
                                burst_remaining == 4'd0;
    assign high_rate_input = first_output_event ?
        {{(FIRST_INT_W-COMB_W){comb_operand[COMB_W-1]}}, comb_operand} :
        {{(FIRST_INT_W-COMB_W){hold_sample[COMB_W-1]}}, hold_sample};

    assign shared_integrator_a = integrator_second_phase ?
        final_integrator_state :
        {{(FINAL_W-FIRST_INT_W){integrator_state[FIRST_INT_W-1]}},
         integrator_state};
    assign shared_integrator_b = integrator_second_phase ?
        {{(FINAL_W-FIRST_INT_W){integrator_state[FIRST_INT_W-1]}},
         integrator_state} :
        {{(FINAL_W-FIRST_INT_W){high_rate_input[FIRST_INT_W-1]}},
         high_rate_input};
    assign shared_integrator_sum =
        shared_integrator_a + shared_integrator_b;

    round_sat_shift_compact #(
        .IN_W    (FINAL_W),
        .OUT_W   (OUTPUT_W),
        .SHIFT_N (OUTPUT_SHIFT)
    ) u_round_cic_normalized_output (
        .din  (shared_integrator_sum),
        .dout (normalized_output)
    );

    assign burst_remaining_dbg = {1'b0, burst_remaining};
    assign pending_dbg = burst_pending;
    assign comb_busy_dbg = comb_active || align_pending;
    assign integrator_busy_dbg = integrator_second_phase;
    assign burst_remaining_decrement = burst_remaining - 4'd1;

    always @(posedge clk) begin
        if (!rst_n) begin
            comb_delay0 <= {COMB_DELAY_W{1'b0}};
            comb_delay1 <= {COMB_DELAY_W{1'b0}};
            comb_operand <= {COMB_W{1'b0}};
            comb_stage_index <= 1'b0;
            comb_active <= 1'b0;
            align_pending <= 1'b0;
            hold_sample <= {COMB_W{1'b0}};

            integrator_state <= {FIRST_INT_W{1'b0}};
            final_integrator_state <= {FINAL_W{1'b0}};
            integrator_second_phase <= 1'b0;
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
                integrator_state <=
                    shared_integrator_sum[FIRST_INT_W-1:0];
                integrator_second_phase <= 1'b1;

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
            else if (integrator_second_phase) begin
                final_integrator_state <= shared_integrator_sum;
                y_out <= normalized_output;
                y_out_valid <= 1'b1;
                integrator_second_phase <= 1'b0;
            end
        end
    end

`ifndef SYNTHESIS
    reg ce_out_previous;

    always @(posedge clk) begin
        if (!rst_n)
            ce_out_previous <= 1'b0;
        else begin
            if (ce_out && ce_out_previous)
                $fatal(1, "Fast shared CIC requires a gap between ce_out pulses");
            if (x_in_valid && (comb_active || align_pending || burst_pending))
                $fatal(1, "Fast shared CIC input overwrite");
            if (FINAL_PRUNE_LSB != 0)
                $fatal(1, "Fast shared CIC currently supports FINAL_PRUNE_LSB=0");
            ce_out_previous <= ce_out;
        end
    end
`endif

endmodule
