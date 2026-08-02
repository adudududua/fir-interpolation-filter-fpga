`timescale 1ns / 1ps

// National-finals route-1 unified coefficient plane.
//
// One physical RAMB18E1 services both FIR DSP lanes:
//   port A, addresses 64..89: Stage1 strict-halfband coefficients;
//   port B, addresses   0..63: Stage2 + flat Stage3 coefficients;
//   port B, addresses 96..127: P3 compensated Stage3 coefficients.
//
// Port B exposes the complete signed-18 RAMB18 word.  Bits 15:0 use the
// normal data plane and bits 17:16 use the parity plane, allowing the P3
// center coefficient 35584 without another BRAM or a LUT decoder.
module nf_unified_fir_coeff_bram #(
    parameter integer USE_P3_NINE_TAP_STAGE3 = 0
) (
    input  wire                         clk,
    input  wire [4:0]                   stage1_addr,
    output wire signed [15:0]           stage1_coeff,
    input  wire [6:0]                   stage23_addr,
    output wire signed [17:0]           stage23_coeff
);

`ifdef SYNTHESIS
    localparam [255:0] P3_INIT_06 =
        (USE_P3_NINE_TAP_STAGE3 != 0) ?
        256'h00000000000000000000000000000000000000000000FC510966749B0966FC51 :
        256'h00000000000000000000000000000000000000000231EF784E4E4E4EEF780231;
    localparam [255:0] P3_INIT_07 =
        (USE_P3_NINE_TAP_STAGE3 != 0) ?
        256'h000000000000000000000000000000000000000000000000F5174AD94AD9F517 :
        256'h000000000000000000000000000000000000000000000089F9EE8B00F9EE0089;
    localparam [255:0] P3_INITP_00 =
        (USE_P3_NINE_TAP_STAGE3 != 0) ?
        256'h000000C3000003030003333333333333000003030000030C0000CC3300033033 :
        256'h000000CC0000030C0003333333333333000003030000030C0000CC3300033033;
    wire [15:0] doa;
    wire [1:0] dopa;
    wire [15:0] dob;
    wire [1:0] dopb;

    RAMB18E1 #(
        .RAM_MODE("TDP"),
        .READ_WIDTH_A(18),
        .READ_WIDTH_B(18),
        .WRITE_WIDTH_A(18),
        .WRITE_WIDTH_B(18),
        .DOA_REG(0),
        .DOB_REG(0),
        .WRITE_MODE_A("READ_FIRST"),
        .WRITE_MODE_B("READ_FIRST"),
        .INIT_00(256'h0000000000000000000000000000FF8D0216FAEA0844765A0844FAEA0216FF8D),
        .INIT_01(256'h00000000000000000000000000000000FF3504D1EE0D4DE94DE9EE0D04D1FF35),
        .INIT_02(256'h00000000000000000000000000000000000000000194F3384B324B32F3380194),
        .INIT_03(256'h00000000000000000000000000000000000000000000FF6C020A7D10020AFF6C),
        .INIT_04(256'h0232FE39016FFEDB00E9FF4A008DFF950050FFC5002AFFE30013FFF40007FFFB),
        .INIT_05(256'h0000000000000000000000005164E5240FCCF50D082EF9A30510FBEB0351FD4D),
        .INIT_06(P3_INIT_06),
        .INIT_07(P3_INIT_07),
        .INITP_00(P3_INITP_00)
    ) u_unified_coeff_ramb18e1 (
        .DOADO(doa),
        .DOPADOP(dopa),
        .DOBDO(dob),
        .DOPBDOP(dopb),
        .ADDRARDADDR({3'b000, 2'b10, stage1_addr, 4'b0000}),
        .ADDRBWRADDR({3'b000, stage23_addr, 4'b0000}),
        .CLKARDCLK(clk),
        .CLKBWRCLK(clk),
        .ENARDEN(1'b1),
        .ENBWREN(1'b1),
        .REGCEAREGCE(1'b1),
        .REGCEB(1'b1),
        .RSTRAMARSTRAM(1'b0),
        .RSTRAMB(1'b0),
        .RSTREGARSTREG(1'b0),
        .RSTREGB(1'b0),
        .WEA(2'b00),
        .WEBWE(4'b0000),
        .DIADI(16'd0),
        .DIPADIP(2'd0),
        .DIBDI(16'd0),
        .DIPBDIP(2'd0)
    );

    assign stage1_coeff = doa;
    assign stage23_coeff = {dopb, dob};
`else
    reg signed [17:0] coeff_mem [0:127];
    reg signed [15:0] stage1_coeff_q;
    reg signed [17:0] stage23_coeff_q;
    integer idx;

    initial begin
        for (idx = 0; idx < 128; idx = idx + 1)
            coeff_mem[idx] = 18'sd0;

        coeff_mem[0] = -16'sd115;
        coeff_mem[1] = 16'sd534;
        coeff_mem[2] = -16'sd1302;
        coeff_mem[3] = 16'sd2116;
        coeff_mem[4] = 16'sd30298;
        coeff_mem[5] = 16'sd2116;
        coeff_mem[6] = -16'sd1302;
        coeff_mem[7] = 16'sd534;
        coeff_mem[8] = -16'sd115;

        coeff_mem[16] = -16'sd203;
        coeff_mem[17] = 16'sd1233;
        coeff_mem[18] = -16'sd4595;
        coeff_mem[19] = 16'sd19945;
        coeff_mem[20] = 16'sd19945;
        coeff_mem[21] = -16'sd4595;
        coeff_mem[22] = 16'sd1233;
        coeff_mem[23] = -16'sd203;

        // Stage3 is represented consistently as signed Q15.  Each
        // polyphase branch sums to approximately one, so the complete
        // interpolation filter has DC gain two before zero insertion.
        coeff_mem[32] = 16'sd404;
        coeff_mem[33] = -16'sd3272;
        coeff_mem[34] = 16'sd19250;
        coeff_mem[35] = 16'sd19250;
        coeff_mem[36] = -16'sd3272;
        coeff_mem[37] = 16'sd404;

        coeff_mem[48] = -16'sd148;
        coeff_mem[49] = 16'sd522;
        coeff_mem[50] = 16'sd32016;
        coeff_mem[51] = 16'sd522;
        coeff_mem[52] = -16'sd148;

        coeff_mem[64] = -16'sd5;
        coeff_mem[65] = 16'sd7;
        coeff_mem[66] = -16'sd12;
        coeff_mem[67] = 16'sd19;
        coeff_mem[68] = -16'sd29;
        coeff_mem[69] = 16'sd42;
        coeff_mem[70] = -16'sd59;
        coeff_mem[71] = 16'sd80;
        coeff_mem[72] = -16'sd107;
        coeff_mem[73] = 16'sd141;
        coeff_mem[74] = -16'sd182;
        coeff_mem[75] = 16'sd233;
        coeff_mem[76] = -16'sd293;
        coeff_mem[77] = 16'sd367;
        coeff_mem[78] = -16'sd455;
        coeff_mem[79] = 16'sd562;
        coeff_mem[80] = -16'sd691;
        coeff_mem[81] = 16'sd849;
        coeff_mem[82] = -16'sd1045;
        coeff_mem[83] = 16'sd1296;
        coeff_mem[84] = -16'sd1629;
        coeff_mem[85] = 16'sd2094;
        coeff_mem[86] = -16'sd2803;
        coeff_mem[87] = 16'sd4044;
        coeff_mem[88] = -16'sd6876;
        coeff_mem[89] = 16'sd20836;

        // P3 compensated Stage3, Q15/signed-18.  The two polyphase
        // sequences are expanded in MAC order, matching the existing
        // one-cycle coefficient prefetch contract.
        if (USE_P3_NINE_TAP_STAGE3 != 0) begin
            coeff_mem[96]  = -18'sd943;
            coeff_mem[97]  = 18'sd2406;
            coeff_mem[98]  = 18'sd29851;
            coeff_mem[99]  = 18'sd2406;
            coeff_mem[100] = -18'sd943;
            coeff_mem[112] = -18'sd2793;
            coeff_mem[113] = 18'sd19161;
            coeff_mem[114] = 18'sd19161;
            coeff_mem[115] = -18'sd2793;
        end
        else begin
            coeff_mem[96]  = 18'sd561;
            coeff_mem[97]  = -18'sd4232;
            coeff_mem[98]  = 18'sd20046;
            coeff_mem[99]  = 18'sd20046;
            coeff_mem[100] = -18'sd4232;
            coeff_mem[101] = 18'sd561;
            coeff_mem[112] = 18'sd137;
            coeff_mem[113] = -18'sd1554;
            coeff_mem[114] = 18'sd35584;
            coeff_mem[115] = -18'sd1554;
            coeff_mem[116] = 18'sd137;
        end
    end

    always @(posedge clk) begin
        stage1_coeff_q <= coeff_mem[{2'b10, stage1_addr}];
        stage23_coeff_q <= coeff_mem[stage23_addr];
    end

    assign stage1_coeff = stage1_coeff_q;
    assign stage23_coeff = stage23_coeff_q;
`endif

endmodule
