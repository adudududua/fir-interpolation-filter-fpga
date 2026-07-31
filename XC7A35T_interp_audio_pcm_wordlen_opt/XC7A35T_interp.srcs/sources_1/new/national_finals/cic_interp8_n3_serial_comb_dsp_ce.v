`timescale 1ns / 1ps

// Route 2C tail CIC: R=8, M=1, N=3.
// One DSP is time-shared by all three low-rate comb differences.  Three
// high-rate integrators infer three more DSP48E1 blocks.
(* use_dsp = "yes" *)
module cic_interp8_n3_serial_comb_dsp_ce #(
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
    output wire [3:0]                   burst_remaining_dbg,
    output wire                         pending_dbg,
    output wire                         comb_busy_dbg
);

    localparam integer CIC_ORDER = 3;
    localparam integer RATE_LOG2 = 3;
    localparam integer FULL_W = DATA_W+CIC_ORDER*RATE_LOG2;
    localparam integer COMB_W = DATA_W+CIC_ORDER;
    localparam integer COMB_DELAY_W = COMB_W-1;
    localparam integer OUTPUT_SHIFT = (CIC_ORDER-1)*RATE_LOG2;

    reg signed [COMB_DELAY_W-1:0] comb_delay0;
    reg signed [COMB_DELAY_W-1:0] comb_delay1;
    reg signed [COMB_DELAY_W-1:0] comb_delay2;
    reg signed [COMB_W-1:0] comb_operand;
    reg [1:0] comb_stage_index;
    reg comb_active;

    reg signed [FULL_W-1:0] integrator1_state;
    reg signed [FULL_W-1:0] integrator2_state;
    reg signed [FULL_W-1:0] integrator3_state;
    wire signed [FULL_W-1:0] integrator1_next;
    wire signed [FULL_W-1:0] integrator2_next;
    wire signed [FULL_W-1:0] integrator3_next;

    reg burst_pending;
    reg [2:0] burst_remaining;

    wire signed [COMB_W-1:0] x_comb_extended;
    wire signed [COMB_W-1:0] comb_delay_selected;
    wire signed [COMB_W-1:0] comb_stage_result;
    wire output_event;
    wire first_output_event;
    wire signed [FULL_W-1:0] high_rate_input;
    wire signed [OUTPUT_W-1:0] normalized_output;
    (* use_dsp = "no" *) wire [2:0] burst_remaining_decrement;
    (* use_dsp = "no" *) wire [1:0] comb_stage_index_increment;

    assign x_comb_extended =
        {{(COMB_W-DATA_W){x_in[DATA_W-1]}}, x_in};
    assign comb_delay_selected =
        {{(COMB_W-COMB_DELAY_W){comb_delay0[COMB_DELAY_W-1]}},
         comb_delay0};
    assign comb_stage_result = comb_operand-comb_delay_selected;

    assign output_event = ce_out &&
        (burst_pending || burst_remaining != 3'd0);
    assign first_output_event = ce_out && burst_pending &&
        burst_remaining == 3'd0;
    assign high_rate_input = first_output_event ?
        {{(FULL_W-COMB_W){comb_operand[COMB_W-1]}}, comb_operand} :
        {FULL_W{1'b0}};
    assign integrator1_next = integrator1_state+high_rate_input;
    assign integrator2_next = integrator2_state+integrator1_next;
    assign integrator3_next = integrator3_state+integrator2_next;

    round_sat_shift_compact #(
        .IN_W(FULL_W),
        .OUT_W(OUTPUT_W),
        .SHIFT_N(OUTPUT_SHIFT)
    ) u_round_cic_normalized_output (
        .din(integrator3_next),
        .dout(normalized_output)
    );

    assign burst_remaining_dbg = {1'b0, burst_remaining};
    assign pending_dbg = burst_pending;
    assign comb_busy_dbg = comb_active;
    assign burst_remaining_decrement = burst_remaining-3'd1;
    assign comb_stage_index_increment = comb_stage_index+2'd1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            comb_delay0 <= {COMB_DELAY_W{1'b0}};
            comb_delay1 <= {COMB_DELAY_W{1'b0}};
            comb_delay2 <= {COMB_DELAY_W{1'b0}};
            comb_operand <= {COMB_W{1'b0}};
            comb_stage_index <= 2'd0;
            comb_active <= 1'b0;
            burst_pending <= 1'b0;
            burst_remaining <= 3'd0;
            y_out <= {OUTPUT_W{1'b0}};
            y_out_valid <= 1'b0;
        end
        else begin
            y_out_valid <= 1'b0;

            if (x_in_valid) begin
                comb_operand <= x_comb_extended;
                comb_stage_index <= 2'd0;
                comb_active <= 1'b1;
            end

            if (comb_active) begin
                comb_delay0 <= comb_delay1;
                comb_delay1 <= comb_delay2;
                comb_delay2 <= comb_operand[COMB_DELAY_W-1:0];
                comb_operand <= comb_stage_result;
                if (comb_stage_index == CIC_ORDER-1) begin
                    burst_pending <= 1'b1;
                    comb_active <= 1'b0;
                end
                else begin
                    comb_stage_index <= comb_stage_index_increment;
                end
            end

            if (output_event) begin
                y_out <= normalized_output;
                y_out_valid <= 1'b1;
                if (first_output_event) begin
                    burst_pending <= 1'b0;
                    burst_remaining <= 3'd7;
                end
                else if (burst_remaining == 3'd1) begin
                    burst_remaining <= 3'd0;
                end
                else begin
                    burst_remaining <= burst_remaining_decrement;
                end
            end
        end
    end

    // Synchronous resets let Vivado absorb all three accumulators into DSP P
    // registers.  Each state consumes the newly computed preceding stage.
    always @(posedge clk) begin
        if (!rst_n) begin
            integrator1_state <= {FULL_W{1'b0}};
            integrator2_state <= {FULL_W{1'b0}};
            integrator3_state <= {FULL_W{1'b0}};
        end
        else if (output_event) begin
            integrator1_state <= integrator1_next;
            integrator2_state <= integrator2_next;
            integrator3_state <= integrator3_next;
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && x_in_valid && comb_active)
            $fatal(1, "Route2C CIC8 comb input overwrite");
        if (rst_n && x_in_valid && burst_pending)
            $fatal(1, "Route2C CIC8 burst pending overwrite");
    end
`endif

endmodule
