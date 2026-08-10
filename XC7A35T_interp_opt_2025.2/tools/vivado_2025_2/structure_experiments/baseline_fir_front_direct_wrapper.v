`timescale 1ns / 1ps

// Direct FIR-front reference used by structural experiments.  It is the same
// Stage1 + two quantized bridges + Stage2/3 configuration as the signed-off
// top, without instantiating the downstream CIC.
module baseline_fir_front_direct_wrapper (
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

    interp2_stage1_single_bram_serial_ce #(
        .DATA_W(24), .ACC_W(41),
        .USE_DSP48_PREADDER(1), .USE_EXTERNAL_COEFF_BRAM(1)
    ) u_stage1 (
        .clk(clk), .rst_n(rst_n), .ce_out(ce2_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(y2_raw), .y_out_valid(y2_raw_valid),
        .phase_dbg(), .fir_in_dbg(), .fir_in_valid_dbg(),
        .external_coeff_addr(stage1_coeff_addr),
        .external_coeff_data(stage1_coeff)
    );

    bridge_valid_quantized_to_interp2_ce #(
        .IN_W(24), .OUT_W(22), .SHIFT_N(2), .USE_EXTERNAL_PHASE(1)
    ) u_bridge_2_to_4 (
        .clk(clk), .rst_n(rst_n),
        .in_data(y2_raw), .in_valid(y2_raw_valid),
        .ce_out_next(ce4_out), .phase_current(stage2_phase),
        .out_data(y2_to_stage2), .out_valid(y2_to_stage2_valid)
    );

    bridge_valid_quantized_to_interp2_ce #(
        .IN_W(22), .OUT_W(20), .SHIFT_N(2), .USE_EXTERNAL_PHASE(1)
    ) u_bridge_4_to_8 (
        .clk(clk), .rst_n(rst_n),
        .in_data(y4_raw), .in_valid(y4_raw_valid),
        .ce_out_next(ce8_out), .phase_current(stage3_phase),
        .out_data(y4_to_stage3), .out_valid(y4_to_stage3_valid)
    );

    interp2_stage23_lutram_cic_dsp_ce #(
        .DATA_W(24), .STAGE2_DATA_W(22), .STAGE3_DATA_W(20),
        .STAGE3_OUTPUT_W(21), .COEFF_W(18), .ACC_W(38),
        .CIC_ORDER(3), .STAGE3_FLAT(1),
        .USE_BRAM_HISTORY(1), .USE_UNIFIED_BRAM_HISTORY(1),
        .USE_BRAM_COEFF(1), .USE_PACKED_BRAM(0),
        .USE_EXTERNAL_COEFF_BRAM(1), .USE_P3_JOINT_STAGE3(1),
        .ASSUME_ALIGNED_POW2_CE(1)
    ) u_stage23 (
        .clk(clk), .rst_n(rst_n),
        .stage2_ce_out(ce4_out),
        .stage2_x_in(y2_to_stage2),
        .stage2_x_in_valid(y2_to_stage2_valid),
        .stage2_y_out(y4_raw), .stage2_y_out_valid(y4_raw_valid),
        .stage3_ce_out(ce8_out),
        .stage3_x_in(y4_to_stage3),
        .stage3_x_in_valid(y4_to_stage3_valid),
        .stage3_compensated_mode(stage3_compensated_mode),
        .stage3_y_out(y8_raw), .stage3_y_out_valid(y8_raw_valid),
        .stage2_phase_dbg(stage2_phase), .stage3_phase_dbg(stage3_phase),
        .scheduler_busy_dbg(), .scheduler_stage_dbg(),
        .scheduler_mac_index_dbg(),
        .external_coeff_addr(stage23_coeff_addr),
        .external_coeff_data(stage23_coeff)
    );

    assign y2 = y2_raw;
    assign y2_valid = y2_raw_valid;
    assign y4 = {y4_raw, 2'b00};
    assign y4_valid = y4_raw_valid;
    assign y8 = {y8_visible, 4'b0000};
    assign y8_valid = y8_raw_valid;
endmodule
