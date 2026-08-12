`timescale 1ns / 1ps

// Fixed 3-DSP experiment.  The two low-rate comb differences are scheduled
// only when no high-rate output event is active.  This makes them mutually
// exclusive with the first integrator, so all three operations can share one
// 26-bit Fabric CARRY datapath.  The final integrator remains in one DSP48E1.
module cic_interp16_n3_hold2_shared_carry_mode1_candidate #(
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
    reg signed [COMB_W-1:0] hold_sample;
    reg signed [FIRST_INT_W-1:0] integrator_state;
    reg signed [FINAL_W-1:0] final_integrator_state;
    reg burst_pending;
    reg [3:0] burst_remaining;

    wire signed [COMB_W-1:0] x_comb_extended;
    wire signed [COMB_W-1:0] comb_delay_selected;
    wire output_event;
    wire first_output_event;
    wire comb_step;
    wire signed [FIRST_INT_W-1:0] high_rate_input;
    wire signed [FIRST_INT_W-1:0] comb_operand_extended;
    wire signed [FIRST_INT_W-1:0] comb_delay_extended;
    wire signed [FIRST_INT_W-1:0] shared_operand_a;
    wire signed [FIRST_INT_W-1:0] shared_operand_b;
    wire signed [FIRST_INT_W-1:0] shared_operand_b_xor;
    (* use_dsp = "no" *) wire signed [FIRST_INT_W-1:0] shared_sum;
    wire signed [COMB_W-1:0] comb_stage_result;
    wire signed [FIRST_INT_W-1:0] integrator_next;
    wire signed [FINAL_W-1:0] final_integrator_next;
    wire signed [OUTPUT_W-1:0] normalized_output;
    (* use_dsp = "no" *) wire [3:0] burst_remaining_decrement;

    assign x_comb_extended =
        {{(COMB_W-DATA_W){x_in[DATA_W-1]}}, x_in};
    assign comb_delay_selected =
        {{(COMB_W-COMB_DELAY_W){comb_delay0[COMB_DELAY_W-1]}},
         comb_delay0};
    assign output_event = ce_out &&
                          (burst_pending || burst_remaining != 4'd0);
    assign first_output_event = ce_out && burst_pending &&
                                burst_remaining == 4'd0;
    assign comb_step = comb_active && !output_event;
    assign high_rate_input = first_output_event ?
        {{(FIRST_INT_W-COMB_W){comb_operand[COMB_W-1]}}, comb_operand} :
        {{(FIRST_INT_W-COMB_W){hold_sample[COMB_W-1]}}, hold_sample};
    assign comb_operand_extended =
        {{(FIRST_INT_W-COMB_W){comb_operand[COMB_W-1]}}, comb_operand};
    assign comb_delay_extended =
        {{(FIRST_INT_W-COMB_W){comb_delay_selected[COMB_W-1]}},
         comb_delay_selected};

    // output_event=1 selects addition.  Otherwise invert B and inject carry
    // to perform the serial comb subtraction on the same CARRY chain.
    assign shared_operand_a = output_event ?
        integrator_state : comb_operand_extended;
    assign shared_operand_b = output_event ?
        high_rate_input : comb_delay_extended;
    assign shared_operand_b_xor = shared_operand_b ^
        {FIRST_INT_W{!output_event}};
    assign shared_sum = shared_operand_a + shared_operand_b_xor +
                        {{(FIRST_INT_W-1){1'b0}}, !output_event};
    assign comb_stage_result = shared_sum[COMB_W-1:0];
    assign integrator_next = shared_sum;

    (* use_dsp = "yes" *) wire signed [FINAL_W-1:0]
        final_integrator_sum;
    assign final_integrator_sum = final_integrator_state + integrator_next;
    assign final_integrator_next = final_integrator_sum;

    assign burst_remaining_dbg = {1'b0, burst_remaining};
    assign pending_dbg = burst_pending;
    assign comb_busy_dbg = comb_active || comb_stage_index;
    assign burst_remaining_decrement = burst_remaining-4'd1;

    round_sat_shift_compact #(
        .IN_W(FINAL_W),
        .OUT_W(OUTPUT_W),
        .SHIFT_N(OUTPUT_SHIFT)
    ) u_round_cic_normalized_output (
        .din(final_integrator_next),
        .dout(normalized_output)
    );

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
                comb_operand <= x_comb_extended;
                comb_stage_index <= 1'b0;
                comb_active <= 1'b1;
            end

            if (comb_step) begin
                comb_delay0 <= comb_delay1;
                comb_delay1 <= comb_operand[COMB_DELAY_W-1:0];
                comb_operand <= comb_stage_result;
                if (comb_stage_index)
                    comb_active <= 1'b0;
                else
                    comb_stage_index <= 1'b1;
            end
            else if (!comb_active && comb_stage_index) begin
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
            $fatal(1, "Shared-CARRY CIC input overwrite");
        if (rst_n && BURST_COUNTER_USE_DSP != 0)
            $fatal(1, "Shared-CARRY CIC only supports LUT burst counter");
        if (rst_n && FINAL_PRUNE_LSB != 0)
            $fatal(1, "Shared-CARRY candidate requires FINAL_PRUNE_LSB=0");
        if (rst_n && comb_active && output_event && ce_out !== 1'b1)
            $fatal(1, "Shared-CARRY scheduling invariant failed");
    end
`endif
endmodule
