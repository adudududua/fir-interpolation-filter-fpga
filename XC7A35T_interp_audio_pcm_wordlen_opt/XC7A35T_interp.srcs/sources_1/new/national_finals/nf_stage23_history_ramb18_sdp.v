`timescale 1ns / 1ps

// One physical RAMB18E1 stores both Stage2 and Stage3 circular histories.
// The 5-bit logical address is {stage_bank, history_index}; each signed
// 22-bit word occupies one 36-bit SDP location.  Port A is synchronous read,
// port B is synchronous write, so the shared MAC can read while the small
// write arbiter commits one history update.
module nf_stage23_history_ramb18_sdp #(
    parameter integer DATA_W = 22,
    parameter integer ADDR_W = 5,
    parameter integer SIM_USE_PRIMITIVE = 0
)(
    input  wire                         clk,
    input  wire [ADDR_W-1:0]            read_addr,
    output wire signed [DATA_W-1:0]     read_data,
    input  wire                         write_enable,
    input  wire [ADDR_W-1:0]            write_addr,
    input  wire signed [DATA_W-1:0]     write_data
);

`ifdef SYNTHESIS
    localparam integer USE_PRIMITIVE = 1;
`else
    localparam integer USE_PRIMITIVE = SIM_USE_PRIMITIVE;
`endif

generate
if (USE_PRIMITIVE != 0) begin : gen_primitive
    wire [15:0] doa;
    wire [1:0] dopa;
    wire [15:0] dob;
    wire [1:0] dopb;

    RAMB18E1 #(
        .RAM_MODE("SDP"),
        .READ_WIDTH_A(36),
        .READ_WIDTH_B(0),
        .WRITE_WIDTH_A(0),
        .WRITE_WIDTH_B(36),
        .DOA_REG(0),
        .DOB_REG(0),
        .WRITE_MODE_A("READ_FIRST"),
        .WRITE_MODE_B("READ_FIRST"),
        .SIM_DEVICE("7SERIES")
    ) u_stage23_history_ramb18e1 (
        .DOADO(doa),
        .DOPADOP(dopa),
        .DOBDO(dob),
        .DOPBDOP(dopb),
        .ADDRARDADDR({4'b0000, read_addr, 5'b00000}),
        .ADDRBWRADDR({4'b0000, write_addr, 5'b00000}),
        .CLKARDCLK(clk),
        .CLKBWRCLK(clk),
        .ENARDEN(1'b1),
        .ENBWREN(write_enable),
        .REGCEAREGCE(1'b1),
        .REGCEB(1'b1),
        .RSTRAMARSTRAM(1'b0),
        .RSTRAMB(1'b0),
        .RSTREGARSTREG(1'b0),
        .RSTREGB(1'b0),
        .WEA(2'b00),
        .WEBWE({4{write_enable}}),
        .DIADI(write_data[15:0]),
        .DIPADIP(2'b00),
        .DIBDI({{(32-DATA_W){1'b0}}, write_data[DATA_W-1:16]}),
        .DIPBDIP(2'b00)
    );

    assign read_data = {dob[DATA_W-17:0], doa};
end else begin : gen_behavioral
    reg signed [DATA_W-1:0] memory [0:(1<<ADDR_W)-1];
    reg signed [DATA_W-1:0] read_data_q;

    always @(posedge clk) begin
        read_data_q <= memory[read_addr];
        if (write_enable)
            memory[write_addr] <= write_data;
    end

    assign read_data = read_data_q;
end
endgenerate

`ifndef SYNTHESIS
    initial begin
        if (DATA_W < 17 || DATA_W > 32)
            $fatal(1, "Stage2/3 RAMB18 SDP DATA_W must be 17..32");
        if (ADDR_W != 5)
            $fatal(1, "Stage2/3 RAMB18 SDP expects 32 logical words");
        if (SIM_USE_PRIMITIVE != 0 && SIM_USE_PRIMITIVE != 1)
            $fatal(1, "SIM_USE_PRIMITIVE must be 0 or 1");
    end
`endif

endmodule
