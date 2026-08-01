`timescale 1ns / 1ps

// Exact serial rewrite of the national-finals equalizer plus the two
// low-rate comb stages used by the N=3 Hold16 CIC:
//
//   q[n]  = x[n-1] + ((2*x[n-1] - x[n] - x[n-2]) >>> 3)
//   d0[n] = q[n] - q[n-1]
//   d1[n] = d0[n] - d0[n-1]
//
// One signed 23-bit add/sub datapath performs the five operations.  The
// equalizer result is deliberately narrowed to its original lossless
// 21-bit interface before the comb stages, preserving bit-true behaviour.
module cic_interp16_n3_comp_hold2_shared_alu_ce #(
    parameter integer INPUT_W = 20,
    parameter integer OUTPUT_W = 20,
    parameter integer FINAL_PRUNE_LSB = 0,
    parameter integer BURST_COUNTER_USE_DSP = 0,
    parameter integer INTEGRATOR_DSP_MODE = 2
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ce_out,
    input  wire signed [INPUT_W-1:0]    x_in,
    input  wire                         x_in_valid,
    output reg  signed [OUTPUT_W-1:0]   y_out,
    output reg                          y_out_valid,
    output wire [4:0]                   burst_remaining_dbg,
    output wire                         pending_dbg,
    output wire                         front_busy_dbg
);

    localparam integer DATA_W = INPUT_W + 1;
    localparam integer ALU_W = INPUT_W + 3;
    localparam integer COMB_DELAY_W = DATA_W + 1;
    localparam integer FIRST_INT_W = DATA_W + 5;
    localparam integer FINAL_W = DATA_W + 8 - FINAL_PRUNE_LSB;
    localparam integer OUTPUT_SHIFT = 8 - FINAL_PRUNE_LSB;

    localparam [2:0] FRONT_IDLE = 3'd0;
    localparam [2:0] FRONT_EQ_SUB_X0 = 3'd1;
    localparam [2:0] FRONT_EQ_SUB_X2 = 3'd2;
    localparam [2:0] FRONT_EQ_ADD = 3'd3;
    localparam [2:0] FRONT_COMB0 = 3'd4;
    localparam [2:0] FRONT_COMB1 = 3'd5;

    reg signed [INPUT_W-1:0] eq_x_z1;
    reg signed [INPUT_W-1:0] eq_x_z2;
    reg signed [INPUT_W-1:0] eq_x_now;
    reg signed [ALU_W-1:0] alu_state;
    reg signed [COMB_DELAY_W-1:0] q_delay;
    reg signed [COMB_DELAY_W-1:0] d0_delay;
    reg [2:0] front_state;
    reg front_active;

    reg signed [ALU_W-1:0] hold_sample;
    reg signed [FIRST_INT_W-1:0] integrator_state;
    reg signed [FINAL_W-1:0] final_integrator_state;
    reg burst_pending;
    reg [3:0] burst_remaining;

    reg signed [ALU_W-1:0] alu_lhs;
    reg signed [ALU_W-1:0] alu_rhs;
    reg alu_subtract;

    wire signed [ALU_W-1:0] x_z1_extended;
    wire signed [ALU_W-1:0] x_z2_extended;
    wire signed [ALU_W-1:0] x_now_extended;
    wire signed [ALU_W-1:0] q_truncated_extended;
    wire signed [ALU_W-1:0] q_delay_extended;
    wire signed [ALU_W-1:0] d0_delay_extended;
    (* use_dsp = "no" *) wire signed [ALU_W-1:0] shared_alu_result;

    wire output_event;
    wire first_output_event;
    wire signed [FIRST_INT_W-1:0] high_rate_input;
    wire signed [FIRST_INT_W-1:0] integrator_next;
    wire signed [FINAL_W-1:0] final_input_rounded;
    wire signed [FINAL_W-1:0] final_integrator_next;
    wire signed [OUTPUT_W-1:0] normalized_output;
    (* use_dsp = "no" *) wire [3:0] burst_remaining_decrement;

    assign x_z1_extended = {{(ALU_W-INPUT_W){eq_x_z1[INPUT_W-1]}},
                            eq_x_z1};
    assign x_z2_extended = {{(ALU_W-INPUT_W){eq_x_z2[INPUT_W-1]}},
                            eq_x_z2};
    assign x_now_extended = {{(ALU_W-INPUT_W){eq_x_now[INPUT_W-1]}},
                             eq_x_now};
    // This slice is the original 21-bit equalizer interface.  The value is
    // analytically in range, so the slice is a lossless signed narrowing.
    assign q_truncated_extended =
        {{(ALU_W-DATA_W){alu_state[DATA_W-1]}},
         alu_state[DATA_W-1:0]};
    assign q_delay_extended =
        {{(ALU_W-COMB_DELAY_W){q_delay[COMB_DELAY_W-1]}}, q_delay};
    assign d0_delay_extended =
        {{(ALU_W-COMB_DELAY_W){d0_delay[COMB_DELAY_W-1]}}, d0_delay};

    always @* begin
        alu_lhs = {ALU_W{1'b0}};
        alu_rhs = {ALU_W{1'b0}};
        alu_subtract = 1'b0;
        case (front_state)
            FRONT_EQ_SUB_X0: begin
                alu_lhs = x_z1_extended <<< 1;
                alu_rhs = x_now_extended;
                alu_subtract = 1'b1;
            end
            FRONT_EQ_SUB_X2: begin
                alu_lhs = alu_state;
                alu_rhs = x_z2_extended;
                alu_subtract = 1'b1;
            end
            FRONT_EQ_ADD: begin
                alu_lhs = x_z1_extended;
                alu_rhs = alu_state >>> 3;
            end
            FRONT_COMB0: begin
                alu_lhs = q_truncated_extended;
                alu_rhs = q_delay_extended;
                alu_subtract = 1'b1;
            end
            FRONT_COMB1: begin
                alu_lhs = alu_state;
                alu_rhs = d0_delay_extended;
                alu_subtract = 1'b1;
            end
            default: begin
                alu_lhs = {ALU_W{1'b0}};
                alu_rhs = {ALU_W{1'b0}};
            end
        endcase
    end

    assign shared_alu_result = alu_subtract ?
                               (alu_lhs - alu_rhs) :
                               (alu_lhs + alu_rhs);

    assign output_event = ce_out &&
                          (burst_pending || burst_remaining != 4'd0);
    assign first_output_event = ce_out && burst_pending &&
                                burst_remaining == 4'd0;
    assign high_rate_input = first_output_event ?
        {{(FIRST_INT_W-ALU_W){alu_state[ALU_W-1]}}, alu_state} :
        {{(FIRST_INT_W-ALU_W){hold_sample[ALU_W-1]}}, hold_sample};

    generate
        if (INTEGRATOR_DSP_MODE >= 2) begin : gen_first_integrator_dsp
            (* use_dsp = "yes" *) wire signed [FIRST_INT_W-1:0]
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

    generate
        if (FINAL_PRUNE_LSB == 0) begin : gen_no_final_pruning
            assign final_input_rounded = integrator_next;
        end
        else begin : gen_final_pruning
            round_sat_shift_compact #(
                .IN_W(FIRST_INT_W),
                .OUT_W(FINAL_W),
                .SHIFT_N(FINAL_PRUNE_LSB)
            ) u_round_final_integrator_input (
                .din(integrator_next),
                .dout(final_input_rounded)
            );
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
    assign front_busy_dbg = front_active;
    assign burst_remaining_decrement = burst_remaining - 4'd1;

    always @(posedge clk) begin
        if (!rst_n) begin
            eq_x_z1 <= {INPUT_W{1'b0}};
            eq_x_z2 <= {INPUT_W{1'b0}};
            eq_x_now <= {INPUT_W{1'b0}};
            alu_state <= {ALU_W{1'b0}};
            q_delay <= {COMB_DELAY_W{1'b0}};
            d0_delay <= {COMB_DELAY_W{1'b0}};
            front_state <= FRONT_IDLE;
            front_active <= 1'b0;
            hold_sample <= {ALU_W{1'b0}};
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
                eq_x_now <= x_in;
                front_state <= FRONT_EQ_SUB_X0;
                front_active <= 1'b1;
            end

            if (front_active) begin
                alu_state <= shared_alu_result;
                case (front_state)
                    FRONT_EQ_SUB_X0:
                        front_state <= FRONT_EQ_SUB_X2;
                    FRONT_EQ_SUB_X2:
                        front_state <= FRONT_EQ_ADD;
                    FRONT_EQ_ADD: begin
                        // Keep the old x[n-1] visible through the equalizer
                        // addition; rotate history only after q[n] is formed.
                        eq_x_z2 <= eq_x_z1;
                        eq_x_z1 <= eq_x_now;
                        front_state <= FRONT_COMB0;
                    end
                    FRONT_COMB0: begin
                        q_delay <= q_truncated_extended[COMB_DELAY_W-1:0];
                        front_state <= FRONT_COMB1;
                    end
                    FRONT_COMB1: begin
                        d0_delay <= alu_state[COMB_DELAY_W-1:0];
                        front_state <= FRONT_IDLE;
                        front_active <= 1'b0;
                        burst_pending <= 1'b1;
                    end
                    default: begin
                        front_state <= FRONT_IDLE;
                        front_active <= 1'b0;
                    end
                endcase
            end

            if (output_event) begin
                integrator_state <= integrator_next;
                final_integrator_state <= final_integrator_next;
                y_out <= normalized_output;
                y_out_valid <= 1'b1;

                if (first_output_event) begin
                    hold_sample <= alu_state;
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
        if (rst_n && x_in_valid && (front_active || burst_pending))
            $fatal(1, "Shared front ALU input overwrite");
        if (rst_n && BURST_COUNTER_USE_DSP != 0)
            $fatal(1, "Shared front ALU only supports LUT burst counter");
        if (rst_n && (INTEGRATOR_DSP_MODE < 0 ||
                      INTEGRATOR_DSP_MODE > 2))
            $fatal(1, "Shared front ALU DSP mode must be 0, 1, or 2");
        if (rst_n && OUTPUT_SHIFT < 1)
            $fatal(1, "Shared front ALU output shift is invalid");
    end
`endif

endmodule
