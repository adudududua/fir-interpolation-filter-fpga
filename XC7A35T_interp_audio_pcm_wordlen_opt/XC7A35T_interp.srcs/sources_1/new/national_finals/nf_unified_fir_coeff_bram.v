`timescale 1ns / 1ps

// National-finals route-1 unified coefficient plane.
//
// One physical RAMB18E1 services both FIR DSP lanes:
//   port A, addresses 64..89: Stage1 strict-halfband coefficients;
//   port B, addresses  0..63: Stage2/3 polyphase coefficients.
//
// All active coefficients fit signed 16 bits.  Keeping the physical memory
// width at 18 bits uses the RAMB18 data field and leaves parity bits zero.
module nf_unified_fir_coeff_bram (
    input  wire                         clk,
    input  wire [4:0]                   stage1_addr,
    output wire signed [15:0]           stage1_coeff,
    input  wire [5:0]                   stage23_addr,
    output wire signed [15:0]           stage23_coeff
);

`ifdef SYNTHESIS
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
        .INIT_02(256'h000000000000000000000000000000000000000000CAF99C25992599F99C00CA),
        .INIT_03(256'h00000000000000000000000000000000000000000000FFB601053E880105FFB6),
        .INIT_04(256'h0232FE39016FFEDB00E9FF4A008DFF950050FFC5002AFFE30013FFF40007FFFB),
        .INIT_05(256'h0000000000000000000000005164E5240FCCF50D082EF9A30510FBEB0351FD4),
        .INIT_06(256'h0),
        .INIT_07(256'h0)
    ) u_unified_coeff_ramb18e1 (
        .DOADO(doa),
        .DOPADOP(dopa),
        .DOBDO(dob),
        .DOPBDOP(dopb),
        .ADDRARDADDR({3'b000, 2'b10, stage1_addr, 4'b0000}),
        .ADDRBWRADDR({3'b000, 1'b0, stage23_addr, 4'b0000}),
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
    assign stage23_coeff = dob;
`else
    reg signed [15:0] coeff_mem [0:127];
    reg signed [15:0] stage1_coeff_q;
    reg signed [15:0] stage23_coeff_q;
    integer idx;

    initial begin
        for (idx = 0; idx < 128; idx = idx + 1)
            coeff_mem[idx] = 16'sd0;

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

        coeff_mem[32] = 16'sd202;
        coeff_mem[33] = -16'sd1636;
        coeff_mem[34] = 16'sd9625;
        coeff_mem[35] = 16'sd9625;
        coeff_mem[36] = -16'sd1636;
        coeff_mem[37] = 16'sd202;

        coeff_mem[48] = -16'sd74;
        coeff_mem[49] = 16'sd261;
        coeff_mem[50] = 16'sd16008;
        coeff_mem[51] = 16'sd261;
        coeff_mem[52] = -16'sd74;

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
    end

    always @(posedge clk) begin
        stage1_coeff_q <= coeff_mem[{2'b10, stage1_addr}];
        stage23_coeff_q <= coeff_mem[{1'b0, stage23_addr}];
    end

    assign stage1_coeff = stage1_coeff_q;
    assign stage23_coeff = stage23_coeff_q;
`endif

endmodule
