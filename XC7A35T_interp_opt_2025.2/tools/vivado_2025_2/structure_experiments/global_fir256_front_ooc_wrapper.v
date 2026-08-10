`timescale 1ns / 1ps

module global_fir256_front_ooc_wrapper (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    ce2_out,
    input  wire                    ce4_out,
    input  wire                    ce8_out,
    input  wire signed [23:0]      x_in,
    input  wire                    x_in_valid,
    input  wire                    stage3_compensated_mode,
    output wire signed [23:0]      y2,
    output wire                    y2_valid,
    output wire signed [23:0]      y4,
    output wire                    y4_valid,
    output wire signed [23:0]      y8,
    output wire                    y8_valid
);

    wire [5:0] stage1_coeff_addr;
    wire signed [15:0] stage1_coeff;
    wire [6:0] stage23_coeff_addr;
    wire signed [17:0] stage23_coeff;
    wire signed [23:0] y2_raw;
    wire y2_raw_valid;
    wire signed [21:0] y4_raw;
    wire y4_raw_valid;
    wire signed [20:0] y8_raw;
    wire y8_raw_valid;
    wire signed [21:0] y2_to_stage2;
    wire y2_to_stage2_valid;
    wire signed [19:0] y4_to_stage3;
    wire y4_to_stage3_valid;
    wire stage2_phase;
    wire stage3_phase;
    wire y8_overflow = y8_raw[20] != y8_raw[19];
    wire signed [19:0] y8_visible = !y8_overflow ? y8_raw[19:0] :
        (y8_raw[20] ? 20'sh80000 : 20'sh7ffff);

    nf_unified_fir_coeff_bram u_coeff (
        .clk(clk),
        .stage1_addr(stage1_coeff_addr),
        .stage1_coeff(stage1_coeff),
        .stage23_addr(stage23_coeff_addr),
        .stage23_coeff(stage23_coeff)
    );

    bridge_valid_quantized_to_interp2_ce #(
        .IN_W(24), .OUT_W(22), .SHIFT_N(2),
        .USE_EXTERNAL_PHASE(1)
    ) u_bridge_2_to_4 (
        .clk(clk), .rst_n(rst_n),
        .in_data(y2_raw), .in_valid(y2_raw_valid),
        .ce_out_next(ce4_out), .phase_current(stage2_phase),
        .out_data(y2_to_stage2), .out_valid(y2_to_stage2_valid)
    );

    bridge_valid_quantized_to_interp2_ce #(
        .IN_W(22), .OUT_W(20), .SHIFT_N(2),
        .USE_EXTERNAL_PHASE(1)
    ) u_bridge_4_to_8 (
        .clk(clk), .rst_n(rst_n),
        .in_data(y4_raw), .in_valid(y4_raw_valid),
        .ce_out_next(ce8_out), .phase_current(stage3_phase),
        .out_data(y4_to_stage3), .out_valid(y4_to_stage3_valid)
    );

    nf_global_fir_scheduler_256x_ce u_global_fir (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out), .ce8_out(ce8_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .stage2_x_in(y2_to_stage2),
        .stage2_x_in_valid(y2_to_stage2_valid),
        .stage3_x_in(y4_to_stage3),
        .stage3_x_in_valid(y4_to_stage3_valid),
        .stage3_compensated_mode(stage3_compensated_mode),
        .y2_out(y2_raw), .y2_out_valid(y2_raw_valid),
        .y4_out(y4_raw), .y4_out_valid(y4_raw_valid),
        .y8_out(y8_raw), .y8_out_valid(y8_raw_valid),
        .stage2_phase_dbg(stage2_phase),
        .stage3_phase_dbg(stage3_phase),
        .scheduler_state_dbg(), .scheduler_owner_dbg(),
        .stage1_coeff_addr(stage1_coeff_addr),
        .stage1_coeff_data(stage1_coeff),
        .stage23_coeff_addr(stage23_coeff_addr),
        .stage23_coeff_data(stage23_coeff)
    );

    assign y2 = y2_raw;
    assign y2_valid = y2_raw_valid;
    assign y4 = {y4_raw, 2'b00};
    assign y4_valid = y4_raw_valid;
    assign y8 = {y8_visible, 4'b0000};
    assign y8_valid = y8_raw_valid;

endmodule
