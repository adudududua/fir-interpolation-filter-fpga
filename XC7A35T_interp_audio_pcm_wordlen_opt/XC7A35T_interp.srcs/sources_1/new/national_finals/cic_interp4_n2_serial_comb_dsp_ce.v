`timescale 1ns / 1ps

// Route 2B tail CIC: R=4, M=1, N=2.
// One DSP is shared by the two low-rate comb differences; the two high-rate
// integrators update in parallel and infer two further DSP48E1 blocks.
(* use_dsp = "yes" *)
module cic_interp4_n2_serial_comb_dsp_ce #(
    parameter integer DATA_W = 20,
    parameter integer OUTPUT_W = DATA_W
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ce_out,
    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,
    output reg  signed [OUTPUT_W-1:0]   y_out,
    output reg                          y_out_valid,
    output wire [2:0]                   burst_remaining_dbg,
    output wire                         pending_dbg,
    output wire                         comb_busy_dbg
);

    localparam integer CIC_ORDER = 2;
    localparam integer RATE_LOG2 = 2;
    localparam integer FULL_W = DATA_W + CIC_ORDER*RATE_LOG2;
    localparam integer COMB_W = DATA_W + CIC_ORDER;
    localparam integer COMB_DELAY_W = DATA_W + CIC_ORDER - 1;
    localparam integer OUTPUT_SHIFT = (CIC_ORDER-1)*RATE_LOG2;

    reg signed [COMB_DELAY_W-1:0] comb_delay0;
    reg signed [COMB_DELAY_W-1:0] comb_delay1;
    reg signed [COMB_W-1:0] comb_operand;
    reg comb_stage_index;
    reg comb_active;

    reg signed [FULL_W-1:0] integrator_state;
    reg signed [FULL_W-1:0] final_integrator_state;
    wire signed [FULL_W-1:0] integrator_next;
    wire signed [FULL_W-1:0] final_integrator_next;

    reg burst_pending;
    reg [1:0] burst_remaining;

    wire signed [COMB_W-1:0] x_comb_extended;
    wire signed [COMB_W-1:0] comb_delay_selected;
    wire signed [COMB_W-1:0] comb_stage_result;
    wire output_event;
    wire first_output_event;
    wire signed [FULL_W-1:0] high_rate_input;
    wire signed [OUTPUT_W-1:0] normalized_output;
    (* use_dsp = "no" *) wire [1:0] burst_remaining_decrement;

    assign x_comb_extended =
        {{(COMB_W-DATA_W){x_in[DATA_W-1]}}, x_in};
    assign comb_delay_selected =
        {{(COMB_W-COMB_DELAY_W){comb_delay0[COMB_DELAY_W-1]}},
         comb_delay0};
    assign comb_stage_result = comb_operand-comb_delay_selected;

    assign output_event = ce_out &&
        (burst_pending || burst_remaining != 2'd0);
    assign first_output_event = ce_out && burst_pending &&
        burst_remaining == 2'd0;
    assign high_rate_input = first_output_event ?
        {{(FULL_W-COMB_W){comb_operand[COMB_W-1]}}, comb_operand} :
        {FULL_W{1'b0}};
    assign integrator_next = integrator_state+high_rate_input;
    assign final_integrator_next =
        final_integrator_state+integrator_next;

    round_sat_shift_compact #(
        .IN_W(FULL_W),
        .OUT_W(OUTPUT_W),
        .SHIFT_N(OUTPUT_SHIFT)
    ) u_round_cic_normalized_output (
        .din(final_integrator_next),
        .dout(normalized_output)
    );

    assign burst_remaining_dbg = {1'b0, burst_remaining};
    assign pending_dbg = burst_pending;
    assign comb_busy_dbg = comb_active;
    assign burst_remaining_decrement = burst_remaining-2'd1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            comb_delay0 <= {COMB_DELAY_W{1'b0}};
            comb_delay1 <= {COMB_DELAY_W{1'b0}};
            comb_operand <= {COMB_W{1'b0}};
            comb_stage_index <= 1'b0;
            comb_active <= 1'b0;
            final_integrator_state <= {FULL_W{1'b0}};
            burst_pending <= 1'b0;
            burst_remaining <= 2'd0;
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
                if (comb_stage_index == CIC_ORDER-1) begin
                    burst_pending <= 1'b1;
                    comb_active <= 1'b0;
                end
                else begin
                    comb_stage_index <= 1'b1;
                end
            end

            if (output_event) begin
                final_integrator_state <= final_integrator_next;
                y_out <= normalized_output;
                y_out_valid <= 1'b1;
                if (first_output_event) begin
                    burst_pending <= 1'b0;
                    burst_remaining <= 2'd3;
                end
                else if (burst_remaining == 2'd1) begin
                    burst_remaining <= 2'd0;
                end
                else begin
                    burst_remaining <= burst_remaining_decrement;
                end
            end
        end
    end

    // The hidden first integrator uses synchronous reset to allow absorption
    // into the DSP48 P register.
    always @(posedge clk) begin
        if (!rst_n)
            integrator_state <= {FULL_W{1'b0}};
        else if (output_event)
            integrator_state <= integrator_next;
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && x_in_valid && comb_active)
            $fatal(1, "Route2 CIC comb input overwrite");
        if (rst_n && x_in_valid && burst_pending)
            $fatal(1, "Route2 CIC burst pending overwrite");
    end
`endif

endmodule
