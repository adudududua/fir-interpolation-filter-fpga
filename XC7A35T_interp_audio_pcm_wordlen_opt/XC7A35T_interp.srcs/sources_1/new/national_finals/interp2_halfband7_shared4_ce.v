`timescale 1ns / 1ps

// Four dyadically scheduled 2x halfband stages with one shared even-phase
// shift/add datapath.  With ce16/32/64/128 derived from the same seven-bit
// counter, the even phases are mutually exclusive:
//   stage 7: odd counter values
//   stage 6: counter == 2 (mod 4)
//   stage 5: counter == 4 (mod 8)
//   stage 4: counter == 8 (mod 16)
// Odd phases are delay-only and can occur together without using the shared
// arithmetic.  The direct stage hand-offs are safe because every upstream
// result is registered one half-period before the downstream even phase.
module interp2_halfband7_shared4_ce #(
    parameter integer DATA_W = 18,
    parameter integer USE_DSP48_PREADDER = 0
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ce16_out,
    input  wire                         ce32_out,
    input  wire                         ce64_out,
    input  wire                         ce128_out,
    input  wire signed [DATA_W-1:0]     x8_quantized,
    output reg  signed [DATA_W-1:0]     y16,
    output reg                          y16_valid,
    output reg  signed [DATA_W-1:0]     y32,
    output reg                          y32_valid,
    output reg  signed [DATA_W-1:0]     y64,
    output reg                          y64_valid,
    output reg  signed [DATA_W-1:0]     y128,
    output reg                          y128_valid
);

    localparam integer PAIR_W = DATA_W + 1;
    localparam integer ACC_W = DATA_W + 5;

    reg phase4;
    reg phase5;
    reg phase6;
    reg phase7;

    reg signed [DATA_W-1:0] s4_d1;
    reg signed [DATA_W-1:0] s4_d2;
    reg signed [DATA_W-1:0] s4_d3;
    reg signed [DATA_W-1:0] s5_d1;
    reg signed [DATA_W-1:0] s5_d2;
    reg signed [DATA_W-1:0] s5_d3;
    reg signed [DATA_W-1:0] s6_d1;
    reg signed [DATA_W-1:0] s6_d2;
    reg signed [DATA_W-1:0] s6_d3;
    reg signed [DATA_W-1:0] s7_d1;
    reg signed [DATA_W-1:0] s7_d2;
    reg signed [DATA_W-1:0] s7_d3;

    wire compute4 = ce16_out && !phase4;
    wire compute5 = ce32_out && !phase5;
    wire compute6 = ce64_out && !phase6;
    wire compute7 = ce128_out && !phase7;

    reg signed [DATA_W-1:0] selected_x;
    reg signed [DATA_W-1:0] selected_d1;
    reg signed [DATA_W-1:0] selected_d2;
    reg signed [DATA_W-1:0] selected_d3;

    wire signed [PAIR_W-1:0] pair_edge;
    wire signed [PAIR_W-1:0] pair_inner;
    wire signed [ACC_W-1:0] pair_edge_ext;
    wire signed [ACC_W-1:0] pair_inner_ext;
    wire signed [ACC_W-1:0] even_acc_lut;
    wire signed [47:0] even_acc_dsp;
    wire signed [ACC_W-1:0] even_acc;
    wire signed [DATA_W-1:0] even_rounded;

    always @(*) begin
        selected_x = x8_quantized;
        selected_d1 = s4_d1;
        selected_d2 = s4_d2;
        selected_d3 = s4_d3;
        if (compute5) begin
            selected_x = y16;
            selected_d1 = s5_d1;
            selected_d2 = s5_d2;
            selected_d3 = s5_d3;
        end
        else if (compute6) begin
            selected_x = y32;
            selected_d1 = s6_d1;
            selected_d2 = s6_d2;
            selected_d3 = s6_d3;
        end
        else if (compute7) begin
            selected_x = y64;
            selected_d1 = s7_d1;
            selected_d2 = s7_d2;
            selected_d3 = s7_d3;
        end
    end

    assign pair_edge =
        $signed({selected_x[DATA_W-1], selected_x}) +
        $signed({selected_d3[DATA_W-1], selected_d3});
    assign pair_inner =
        $signed({selected_d1[DATA_W-1], selected_d1}) +
        $signed({selected_d2[DATA_W-1], selected_d2});
    assign pair_edge_ext =
        {{(ACC_W-PAIR_W){pair_edge[PAIR_W-1]}}, pair_edge};
    assign pair_inner_ext =
        {{(ACC_W-PAIR_W){pair_inner[PAIR_W-1]}}, pair_inner};
    assign even_acc_lut =
        -pair_edge_ext + pair_inner_ext + (pair_inner_ext <<< 3);
    assign even_acc = (USE_DSP48_PREADDER != 0) ?
        even_acc_dsp[ACC_W-1:0] : even_acc_lut;

    generate
        if (USE_DSP48_PREADDER != 0) begin : gen_tail_dsp48
            wire signed [24:0] dsp_a =
                {{(25-DATA_W){selected_d1[DATA_W-1]}}, selected_d1};
            wire signed [24:0] dsp_d =
                {{(25-DATA_W){selected_d2[DATA_W-1]}}, selected_d2};
            wire signed [47:0] dsp_c =
                {{(48-PAIR_W){pair_edge[PAIR_W-1]}}, pair_edge};

            // P = 9 * (selected_d1 + selected_d2)
            //     - (selected_x + selected_d3).
            // ALUMODE=0001 with CARRYIN=1 forms X+Y-Z in ONE48 mode.
            DSP48E1 #(
                .A_INPUT("DIRECT"),
                .B_INPUT("DIRECT"),
                .USE_DPORT("TRUE"),
                .USE_MULT("MULTIPLY"),
                .USE_SIMD("ONE48"),
                .AREG(0), .ACASCREG(0),
                .BREG(0), .BCASCREG(0),
                .CREG(0), .DREG(0), .ADREG(0),
                .MREG(0), .PREG(0),
                .INMODEREG(0), .OPMODEREG(0),
                .ALUMODEREG(0), .CARRYINREG(0),
                .CARRYINSELREG(0)
            ) u_tail_dsp48e1 (
                .P(even_acc_dsp),
                .A({{5{dsp_a[24]}}, dsp_a}),
                .B(18'sd9),
                .C(dsp_c),
                .D(dsp_d),
                .INMODE(5'b00100),
                .OPMODE(7'b0110101),
                .ALUMODE(4'b0001),
                .CARRYINSEL(3'b000),
                .CARRYIN(1'b1),
                .ACIN(30'd0), .BCIN(18'd0), .PCIN(48'd0),
                .CARRYCASCIN(1'b0), .MULTSIGNIN(1'b0),
                .CLK(clk),
                .CEA1(1'b0), .CEA2(1'b0), .CEAD(1'b0),
                .CEALUMODE(1'b0), .CEB1(1'b0), .CEB2(1'b0),
                .CEC(1'b0), .CECARRYIN(1'b0), .CECTRL(1'b0),
                .CED(1'b0), .CEINMODE(1'b0), .CEM(1'b0), .CEP(1'b0),
                .RSTA(1'b0), .RSTALLCARRYIN(1'b0),
                .RSTALUMODE(1'b0), .RSTB(1'b0), .RSTC(1'b0),
                .RSTCTRL(1'b0), .RSTD(1'b0), .RSTINMODE(1'b0),
                .RSTM(1'b0), .RSTP(1'b0),
                .ACOUT(), .BCOUT(), .CARRYCASCOUT(), .CARRYOUT(),
                .MULTSIGNOUT(), .OVERFLOW(), .PATTERNBDETECT(),
                .PATTERNDETECT(), .PCOUT(), .UNDERFLOW()
            );
        end
        else begin : gen_tail_lut
            assign even_acc_dsp = 48'sd0;
        end
    endgenerate

    round_sat_shift_compact #(
        .IN_W(ACC_W),
        .OUT_W(DATA_W),
        .SHIFT_N(4)
    ) u_round_sat_q4_to_data (
        .din(even_acc),
        .dout(even_rounded)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase4 <= 1'b1;
            phase5 <= 1'b1;
            phase6 <= 1'b1;
            phase7 <= 1'b1;
            s4_d1 <= {DATA_W{1'b0}};
            s4_d2 <= {DATA_W{1'b0}};
            s4_d3 <= {DATA_W{1'b0}};
            s5_d1 <= {DATA_W{1'b0}};
            s5_d2 <= {DATA_W{1'b0}};
            s5_d3 <= {DATA_W{1'b0}};
            s6_d1 <= {DATA_W{1'b0}};
            s6_d2 <= {DATA_W{1'b0}};
            s6_d3 <= {DATA_W{1'b0}};
            s7_d1 <= {DATA_W{1'b0}};
            s7_d2 <= {DATA_W{1'b0}};
            s7_d3 <= {DATA_W{1'b0}};
            y16 <= {DATA_W{1'b0}};
            y32 <= {DATA_W{1'b0}};
            y64 <= {DATA_W{1'b0}};
            y128 <= {DATA_W{1'b0}};
            y16_valid <= 1'b0;
            y32_valid <= 1'b0;
            y64_valid <= 1'b0;
            y128_valid <= 1'b0;
        end
        else begin
            y16_valid <= 1'b0;
            y32_valid <= 1'b0;
            y64_valid <= 1'b0;
            y128_valid <= 1'b0;

            if (ce16_out) begin
                y16_valid <= 1'b1;
                if (!phase4) begin
                    y16 <= even_rounded;
                    s4_d3 <= s4_d2;
                    s4_d2 <= s4_d1;
                    s4_d1 <= x8_quantized;
                end
                else begin
                    y16 <= s4_d2;
                end
                phase4 <= ~phase4;
            end

            if (ce32_out) begin
                y32_valid <= 1'b1;
                if (!phase5) begin
                    y32 <= even_rounded;
                    s5_d3 <= s5_d2;
                    s5_d2 <= s5_d1;
                    s5_d1 <= y16;
                end
                else begin
                    y32 <= s5_d2;
                end
                phase5 <= ~phase5;
            end

            if (ce64_out) begin
                y64_valid <= 1'b1;
                if (!phase6) begin
                    y64 <= even_rounded;
                    s6_d3 <= s6_d2;
                    s6_d2 <= s6_d1;
                    s6_d1 <= y32;
                end
                else begin
                    y64 <= s6_d2;
                end
                phase6 <= ~phase6;
            end

            if (ce128_out) begin
                y128_valid <= 1'b1;
                if (!phase7) begin
                    y128 <= even_rounded;
                    s7_d3 <= s7_d2;
                    s7_d2 <= s7_d1;
                    s7_d1 <= y64;
                end
                else begin
                    y128 <= s7_d2;
                end
                phase7 <= ~phase7;
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && ((compute4 && (compute5 || compute6 || compute7)) ||
                      (compute5 && (compute6 || compute7)) ||
                      (compute6 && compute7)))
            $fatal(1, "Shared halfband arithmetic schedule collision");
    end
`endif

endmodule
