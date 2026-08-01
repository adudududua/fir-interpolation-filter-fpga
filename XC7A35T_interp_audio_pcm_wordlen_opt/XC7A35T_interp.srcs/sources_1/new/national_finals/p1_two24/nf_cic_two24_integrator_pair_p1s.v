`timescale 1ns / 1ps

// P1-S exact two-integrator state transform:
//   A_n = A_(n-1) + u_n          (signed-26 modulo state)
//   Q_n = Q_(n-1) + A_(n-1)      (signed-29 modulo state)
//   B_n = Q_n + A_n               (signed-29 modulo output)
//
// The 24-bit low limbs share one DSP48E1 in TWO24 mode.  PREG and its
// registered segmented carry retire event n while the same edge accepts
// event n+1, so the block sustains II=1 with one clock of output latency.
module nf_cic_two24_integrator_pair_p1s (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   event_ce,
    input  wire signed [25:0]     u_in,
    output reg  signed [25:0]     a_out,
    output reg  signed [28:0]     q_out,
    output reg  signed [28:0]     b_out,
    output reg                    out_valid,
    output wire [47:0]            p_low_limb_dbg,
    output wire [3:0]             carryout_dbg,
    output wire                   pending_dbg
);

    wire [47:0] dsp_p;
    wire [3:0] dsp_carryout;
    wire [47:0] dsp_c;

    reg signed [1:0] a_high;
    reg signed [4:0] q_high;
    reg signed [1:0] pending_u_high;
    reg pending;

    wire signed [2:0] a_high_sum;
    wire signed [5:0] q_high_sum;
    wire signed [25:0] a_commit;
    wire signed [28:0] q_commit;
    wire signed [29:0] b_commit_extended;
    wire signed [28:0] b_commit;

    // C[23:0] updates A low; C[47:24] sees the old A low and updates Q low.
    assign dsp_c = {dsp_p[23:0], u_in[23:0]};
    assign a_high_sum =
        $signed({a_high[1], a_high}) +
        $signed({pending_u_high[1], pending_u_high}) +
        $signed({2'b00, dsp_carryout[1]});
    assign q_high_sum =
        $signed({q_high[4], q_high}) +
        $signed({{4{a_high[1]}}, a_high}) +
        $signed({5'b00000, dsp_carryout[3]});

    assign a_commit = $signed({a_high_sum[1:0], dsp_p[23:0]});
    assign q_commit = $signed({q_high_sum[4:0], dsp_p[47:24]});
    assign b_commit_extended =
        $signed({q_commit[28], q_commit}) +
        $signed({{4{a_commit[25]}}, a_commit});
    assign b_commit = b_commit_extended[28:0];

    assign p_low_limb_dbg = dsp_p;
    assign carryout_dbg = dsp_carryout;
    assign pending_dbg = pending;

    DSP48E1 #(
        .A_INPUT("DIRECT"),
        .B_INPUT("DIRECT"),
        .USE_DPORT("FALSE"),
        .USE_MULT("NONE"),
        .USE_SIMD("TWO24"),
        .AREG(0), .ACASCREG(0),
        .BREG(0), .BCASCREG(0),
        .CREG(0), .DREG(0), .ADREG(0), .MREG(0),
        .PREG(1),
        .INMODEREG(0), .OPMODEREG(0), .ALUMODEREG(0),
        .CARRYINREG(0), .CARRYINSELREG(0)
    ) u_two24_integrator_dsp48e1 (
        .P(dsp_p),
        .A(30'd0),
        .B(18'd0),
        .C(dsp_c),
        .D(25'd0),
        .INMODE(5'b00000),
        .OPMODE(7'b0001110),
        .ALUMODE(4'b0000),
        .CARRYINSEL(3'b000),
        .CARRYIN(1'b0),
        .ACIN(30'd0), .BCIN(18'd0), .PCIN(48'd0),
        .CARRYCASCIN(1'b0), .MULTSIGNIN(1'b0),
        .CLK(clk),
        .CEA1(1'b0), .CEA2(1'b0), .CEAD(1'b0),
        .CEALUMODE(1'b0), .CEB1(1'b0), .CEB2(1'b0),
        .CEC(1'b0), .CECARRYIN(1'b0), .CECTRL(1'b0),
        .CED(1'b0), .CEINMODE(1'b0), .CEM(1'b0),
        .CEP(event_ce),
        .RSTA(1'b0), .RSTALLCARRYIN(1'b0),
        .RSTALUMODE(1'b0), .RSTB(1'b0), .RSTC(1'b0),
        .RSTCTRL(1'b0), .RSTD(1'b0), .RSTINMODE(1'b0),
        .RSTM(1'b0), .RSTP(!rst_n),
        .ACOUT(), .BCOUT(), .CARRYCASCOUT(),
        .CARRYOUT(dsp_carryout), .MULTSIGNOUT(),
        .OVERFLOW(), .PATTERNBDETECT(), .PATTERNDETECT(),
        .PCOUT(), .UNDERFLOW()
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            a_high <= 2'sd0;
            q_high <= 5'sd0;
            pending_u_high <= 2'sd0;
            pending <= 1'b0;
            a_out <= 26'sd0;
            q_out <= 29'sd0;
            b_out <= 29'sd0;
            out_valid <= 1'b0;
        end
        else begin
            out_valid <= pending;
            if (pending) begin
                a_high <= a_high_sum[1:0];
                q_high <= q_high_sum[4:0];
                a_out <= a_commit;
                q_out <= q_commit;
                b_out <= b_commit;
            end
            if (event_ce)
                pending_u_high <= u_in[25:24];
            pending <= event_ce;
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && event_ce && (^u_in === 1'bx))
            $fatal(1, "P1 TWO24 input contains X");
        if (rst_n && pending &&
            (dsp_carryout[1] === 1'bx || dsp_carryout[3] === 1'bx))
            $fatal(1, "P1 TWO24 segmented carry is X");
    end
`endif

endmodule
