`timescale 1ns / 1ps

// CIC16 N=3 implementation for the 2/3-DSP national-finals Pareto points.
// The three low-rate comb stages share one progressively sized LUT subtractor.
// The first two high-rate integrators are explicitly kept in LUT/carry logic.
// The final integrator can either remain in LUTs (whole chain = 2 DSP) or be
// mapped to one DSP48E1 (whole chain = 3 DSP). Arithmetic, modulo wrap,
// rounding, saturation and output sample order match the signed reference.
module cic_interp16_serial_comb_lowdsp_ce #(
    parameter integer DATA_W = 20,
    parameter integer FINAL_PRUNE_LSB = 0,
    parameter integer USE_FINAL_INTEGRATOR_DSP = 0
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ce_out,
    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,
    output reg  signed [DATA_W-1:0]     y_out,
    output reg                          y_out_valid,
    output wire [4:0]                   burst_remaining_dbg,
    output wire                         pending_dbg,
    output wire                         comb_busy_dbg
);

    localparam integer CIC_ORDER = 3;
    localparam integer RATE_LOG2 = 4;
    localparam integer FULL_W = DATA_W + CIC_ORDER*RATE_LOG2;
    localparam integer COMB_W = DATA_W + CIC_ORDER;
    localparam integer FINAL_W = FULL_W - FINAL_PRUNE_LSB;
    localparam integer OUTPUT_SHIFT =
        (CIC_ORDER-1)*RATE_LOG2 - FINAL_PRUNE_LSB;

    reg signed [DATA_W-1:0] comb_delay0;
    reg signed [DATA_W:0] comb_delay1;
    reg signed [DATA_W+1:0] comb_delay2;
    reg signed [COMB_W-1:0] comb_operand;
    reg [1:0] comb_stage_index;
    reg comb_active;

    reg signed [FULL_W-1:0] integrator0_state;
    reg signed [FULL_W-1:0] integrator1_state;
    reg signed [FINAL_W-1:0] final_integrator_state;
    reg burst_pending;
    reg [4:0] burst_remaining;

    wire signed [COMB_W-1:0] x_comb_extended;
    wire signed [COMB_W-1:0] comb_delay_selected;
    (* use_dsp = "no" *) wire signed [COMB_W-1:0] comb_stage_result;
    wire output_event;
    wire first_output_event;
    wire signed [FULL_W-1:0] high_rate_input;
    (* use_dsp = "no" *) wire signed [FULL_W-1:0] integrator0_next;
    (* use_dsp = "no" *) wire signed [FULL_W-1:0] integrator1_next;
    wire signed [FINAL_W-1:0] final_input_rounded;
    wire signed [FINAL_W-1:0] final_integrator_next;
    wire signed [DATA_W-1:0] normalized_output;
    (* use_dsp = "no" *) wire [4:0] burst_remaining_decrement;
    (* use_dsp = "no" *) wire [1:0] comb_stage_index_increment;

    assign x_comb_extended =
        {{(COMB_W-DATA_W){x_in[DATA_W-1]}}, x_in};
    assign comb_delay_selected =
        (comb_stage_index == 2'd0) ?
            {{(COMB_W-DATA_W){comb_delay0[DATA_W-1]}}, comb_delay0} :
        (comb_stage_index == 2'd1) ?
            {{(COMB_W-DATA_W-1){comb_delay1[DATA_W]}}, comb_delay1} :
            {{(COMB_W-DATA_W-2){comb_delay2[DATA_W+1]}}, comb_delay2};
    assign comb_stage_result = comb_operand - comb_delay_selected;

    assign output_event = ce_out &&
                          (burst_pending || burst_remaining != 5'd0);
    assign first_output_event = ce_out && burst_pending &&
                                burst_remaining == 5'd0;
    assign high_rate_input = first_output_event ?
        {{(FULL_W-COMB_W){comb_operand[COMB_W-1]}}, comb_operand} :
        {FULL_W{1'b0}};

    // These two adders intentionally use carry chains for both profiles.
    assign integrator0_next = integrator0_state + high_rate_input;
    assign integrator1_next = integrator1_state + integrator0_next;

    assign burst_remaining_dbg = burst_remaining;
    assign pending_dbg = burst_pending;
    assign comb_busy_dbg = comb_active;
    assign burst_remaining_decrement = burst_remaining - 5'd1;
    assign comb_stage_index_increment = comb_stage_index + 2'd1;

    generate
        if (FINAL_PRUNE_LSB == 0) begin : gen_no_final_pruning
            assign final_input_rounded = integrator1_next;
        end
        else begin : gen_final_pruning
            round_sat_shift_compact #(
                .IN_W(FULL_W), .OUT_W(FINAL_W),
                .SHIFT_N(FINAL_PRUNE_LSB)
            ) u_round_final_integrator_input (
                .din(integrator1_next), .dout(final_input_rounded)
            );
        end

        if (USE_FINAL_INTEGRATOR_DSP != 0) begin : gen_final_dsp
            (* use_dsp = "yes" *)
            wire signed [FINAL_W-1:0] final_add_impl;
            assign final_add_impl = final_integrator_state +
                                    final_input_rounded;
            assign final_integrator_next = final_add_impl;
        end
        else begin : gen_final_lut
            (* use_dsp = "no" *)
            wire signed [FINAL_W-1:0] final_add_impl;
            assign final_add_impl = final_integrator_state +
                                    final_input_rounded;
            assign final_integrator_next = final_add_impl;
        end
    endgenerate

    round_sat_shift_compact #(
        .IN_W(FINAL_W), .OUT_W(DATA_W), .SHIFT_N(OUTPUT_SHIFT)
    ) u_round_cic_normalized_output (
        .din(final_integrator_next), .dout(normalized_output)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            comb_delay0 <= {DATA_W{1'b0}};
            comb_delay1 <= {(DATA_W+1){1'b0}};
            comb_delay2 <= {(DATA_W+2){1'b0}};
            comb_operand <= {COMB_W{1'b0}};
            comb_stage_index <= 2'd0;
            comb_active <= 1'b0;
            integrator0_state <= {FULL_W{1'b0}};
            integrator1_state <= {FULL_W{1'b0}};
            final_integrator_state <= {FINAL_W{1'b0}};
            burst_pending <= 1'b0;
            burst_remaining <= 5'd0;
            y_out <= {DATA_W{1'b0}};
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
                case (comb_stage_index)
                    2'd0: comb_delay0 <= comb_operand[DATA_W-1:0];
                    2'd1: comb_delay1 <= comb_operand[DATA_W:0];
                    default: comb_delay2 <= comb_operand[DATA_W+1:0];
                endcase
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
                integrator0_state <= integrator0_next;
                integrator1_state <= integrator1_next;
                final_integrator_state <= final_integrator_next;
                y_out <= normalized_output;
                y_out_valid <= 1'b1;

                if (first_output_event) begin
                    burst_pending <= 1'b0;
                    burst_remaining <= 5'd15;
                end
                else if (burst_remaining == 5'd1) begin
                    burst_remaining <= 5'd0;
                end
                else begin
                    burst_remaining <= burst_remaining_decrement;
                end
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && x_in_valid && comb_active)
            $fatal(1, "Low-DSP CIC comb input overwrite");
        if (rst_n && x_in_valid && burst_pending)
            $fatal(1, "Low-DSP CIC burst pending overwrite");
        if (rst_n && comb_stage_index >= CIC_ORDER)
            $fatal(1, "Low-DSP CIC comb stage index out of range");
        if (rst_n && USE_FINAL_INTEGRATOR_DSP != 0 &&
            USE_FINAL_INTEGRATOR_DSP != 1)
            $fatal(1, "USE_FINAL_INTEGRATOR_DSP must be 0 or 1");
        if (rst_n && OUTPUT_SHIFT < 1)
            $fatal(1, "Low-DSP CIC normalization shift is invalid");
    end
`endif

endmodule
