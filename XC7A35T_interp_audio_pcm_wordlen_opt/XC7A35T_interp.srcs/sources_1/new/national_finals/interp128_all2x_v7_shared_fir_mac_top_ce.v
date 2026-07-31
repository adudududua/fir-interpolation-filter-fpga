`timescale 1ns / 1ps

// Experimental national-finals 128x chain with one DSP48E1 shared by all
// three FIR stages.  The compensation and serial CIC sections are identical
// to the verified Route1 implementation, which isolates this experiment to
// the front-end FIR scheduler.
module interp128_all2x_v7_shared_fir_mac_top_ce #(
    parameter integer STAGE1_ACC_W = 42,
    parameter integer STAGE23_ACC_W = 38,
    parameter integer CIC_ORDER = 3,
    parameter integer FINAL_PRUNE_LSB = 3,
    parameter integer USE_LUTRAM_STAGE23 = 1,
    parameter integer STAGE3_FLAT = 1,
    parameter integer USE_CIC3_SHIFTADD_COMPENSATOR = 1,
    parameter integer USE_BRAM_STAGE23_HISTORY = 1,
    parameter integer USE_BRAM_STAGE23_COEFF = 1,
    parameter integer USE_PACKED_BRAM_STAGE23 = 0,
    parameter integer CIC_BURST_COUNTER_USE_DSP = 0,
    parameter integer USE_SERIAL_CIC_COMB = 1,
    parameter integer USE_STAGE1_DSP48_PREADDER = 1,
    parameter integer USE_NATIONAL_FINALS_NARROW_STAGE23 = 1,
    parameter integer USE_UNIFIED_FIR_COEFF_BRAM = 1
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ce2_out,
    input  wire                         ce4_out,
    input  wire                         ce8_out,
    input  wire                         ce16_out,
    input  wire                         ce32_out,
    input  wire                         ce64_out,
    input  wire                         ce128_out,
    input  wire signed [23:0]           x_in,
    input  wire                         x_in_valid,
    output wire signed [23:0]           y_out,
    output wire                         y_out_valid,
    output wire signed [23:0]           dbg_y2,
    output wire                         dbg_y2_valid,
    output wire signed [23:0]           dbg_y4,
    output wire                         dbg_y4_valid,
    output wire signed [23:0]           dbg_y8,
    output wire                         dbg_y8_valid,
    output wire signed [23:0]           dbg_y16,
    output wire                         dbg_y16_valid,
    output wire signed [23:0]           dbg_y32,
    output wire                         dbg_y32_valid,
    output wire signed [23:0]           dbg_y64,
    output wire                         dbg_y64_valid
);

    wire signed [23:0] y2_w;
    wire y2_valid_w;
    wire signed [21:0] y4_w;
    wire y4_valid_w;
    wire signed [19:0] y8_w;
    wire y8_valid_w;
    wire signed [20:0] cic_x_w;
    wire cic_x_valid_w;
    wire signed [19:0] y128_w;
    wire y128_valid_w;
    wire [1:0] scheduler_owner_w;
    wire [5:0] scheduler_index_w;
    wire scheduler_pending_w;

    nf_interp_fir3_shared_mac_ce u_nf_interp_fir3_shared_mac_ce (
        .clk(clk),
        .rst_n(rst_n),
        .ce2_out(ce2_out),
        .ce4_out(ce4_out),
        .ce8_out(ce8_out),
        .x_in(x_in),
        .x_in_valid(x_in_valid),
        .y2_out(y2_w),
        .y2_out_valid(y2_valid_w),
        .y4_out(y4_w),
        .y4_out_valid(y4_valid_w),
        .y8_out(y8_w),
        .y8_out_valid(y8_valid_w),
        .scheduler_owner_dbg(scheduler_owner_w),
        .scheduler_index_dbg(scheduler_index_w),
        .stage1_pending_dbg(scheduler_pending_w),
        .stage2_pending_dbg(),
        .stage3_pending_dbg()
    );

    cic3_compensator_shiftadd_ce #(
        .DATA_W(20),
        .OUTPUT_W(21),
        .REGISTER_OUTPUT(0)
    ) u_cic3_compensator_shiftadd_ce (
        .clk(clk),
        .rst_n(rst_n),
        .x_in(y8_w),
        .x_in_valid(y8_valid_w),
        .y_out(cic_x_w),
        .y_out_valid(cic_x_valid_w)
    );

    cic_interp16_serial_comb_dsp_ce #(
        .DATA_W(21),
        .OUTPUT_W(20),
        .FINAL_PRUNE_LSB(FINAL_PRUNE_LSB),
        .BURST_COUNTER_USE_DSP(CIC_BURST_COUNTER_USE_DSP)
    ) u_cic_interp16_serial_comb_dsp_ce (
        .clk(clk),
        .rst_n(rst_n),
        .ce_out(ce128_out),
        .x_in(cic_x_w),
        .x_in_valid(cic_x_valid_w),
        .y_out(y128_w),
        .y_out_valid(y128_valid_w),
        .burst_remaining_dbg(),
        .pending_dbg(),
        .comb_busy_dbg()
    );

    assign y_out = {y128_w, 4'b0};
    assign y_out_valid = y128_valid_w;
    assign dbg_y2 = y2_w;
    assign dbg_y2_valid = y2_valid_w;
    assign dbg_y4 = {y4_w, 2'b0};
    assign dbg_y4_valid = y4_valid_w;
    assign dbg_y8 = {y8_w, 4'b0};
    assign dbg_y8_valid = y8_valid_w;
    assign dbg_y16 = 24'sd0;
    assign dbg_y16_valid = 1'b0;
    assign dbg_y32 = 24'sd0;
    assign dbg_y32_valid = 1'b0;
    assign dbg_y64 = 24'sd0;
    assign dbg_y64_valid = 1'b0;

    // Keep intentionally unused compatibility parameters and CE inputs in
    // the elaborated cone without changing the datapath.
    wire unused_configuration;
    assign unused_configuration = ce16_out ^ ce32_out ^ ce64_out ^
        scheduler_owner_w[0] ^ scheduler_index_w[0] ^ scheduler_pending_w ^
        (STAGE1_ACC_W == 0) ^ (STAGE23_ACC_W == 0) ^
        (USE_LUTRAM_STAGE23 == 0) ^ (STAGE3_FLAT == 0) ^
        (USE_CIC3_SHIFTADD_COMPENSATOR == 0) ^
        (USE_BRAM_STAGE23_HISTORY == 0) ^
        (USE_BRAM_STAGE23_COEFF == 0) ^
        (USE_PACKED_BRAM_STAGE23 != 0) ^
        (USE_SERIAL_CIC_COMB == 0) ^
        (USE_STAGE1_DSP48_PREADDER == 0) ^
        (USE_NATIONAL_FINALS_NARROW_STAGE23 == 0) ^
        (USE_UNIFIED_FIR_COEFF_BRAM == 0);

`ifndef SYNTHESIS
    initial begin
        if (CIC_ORDER != 3)
            $fatal(1, "Shared FIR national-finals top requires CIC_ORDER=3");
    end

    always @(posedge clk) begin
        if (rst_n && unused_configuration === 1'bx)
            $fatal(1, "Shared FIR top compatibility input contains X");
    end
`endif

endmodule
