`timescale 1ns / 1ps

// One RAMB18E1 stores both the board PCM test-tone ROM and Stage1 history.
// Physical map in 512x36 SDP mode:
//   0..162   : existing dual-family PCM ROM image (read only)
//   256..319 : 64-word Stage1 circular history (read/write)
//
// Port A is the single synchronous read port.  Valid Stage1 reads always win;
// a PCM prefetch request remains pending until the first idle read slot.  Port
// B is dedicated to Stage1 writes, so there is no write-side arbitration.
module nf_pcm_stage1_shared_ramb18_sdp #(
    parameter MEM_FILE = "nf_sine_15k_dual_rate_24bit_256.mem",
    parameter integer SIM_USE_PRIMITIVE = 0
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         history_read_enable,
    input  wire [5:0]                   history_read_addr,
    output wire signed [23:0]           history_read_data,
    input  wire                         history_write_enable,
    input  wire [5:0]                   history_write_addr,
    input  wire signed [23:0]           history_write_data,
    input  wire                         pcm_sample_ce,
    input  wire                         family_48k,
    output reg  signed [23:0]           pcm_sample_out,
    output reg                          pcm_sample_update,
    output reg  [7:0]                   pcm_sample_addr_dbg,
    output reg                          pcm_deadline_miss_dbg,
    output wire                         pcm_request_pending_dbg
);

    localparam [7:0] ADDR_44K1_FIRST = 8'd0;
    localparam [7:0] ADDR_44K1_LAST  = 8'd146;
    localparam [7:0] ADDR_48K_FIRST  = 8'd147;
    localparam [7:0] ADDR_48K_LAST   = 8'd162;

`ifdef SYNTHESIS
    localparam integer USE_PRIMITIVE = 1;
`else
    localparam integer USE_PRIMITIVE = SIM_USE_PRIMITIVE;
`endif

    reg [7:0] pcm_addr;
    reg pcm_request_pending;
    reg pcm_prefetch_ready;
    reg read_owner_pcm_q;

    wire issue_pcm_read;
    wire [8:0] selected_read_addr;
    wire [8:0] physical_history_write_addr;
    wire signed [23:0] shared_read_data;

    assign issue_pcm_read = !history_read_enable && pcm_request_pending;
    assign selected_read_addr = history_read_enable ?
        {3'b100, history_read_addr} : {1'b0, pcm_addr};
    assign physical_history_write_addr = {3'b100, history_write_addr};
    assign history_read_data = shared_read_data;
    assign pcm_request_pending_dbg = pcm_request_pending;

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
                .INIT_FILE(MEM_FILE),
                .SIM_DEVICE("7SERIES")
            ) u_pcm_stage1_shared_ramb18e1 (
                .DOADO(doa),
                .DOPADOP(dopa),
                .DOBDO(dob),
                .DOPBDOP(dopb),
                .ADDRARDADDR({selected_read_addr, 5'b00000}),
                .ADDRBWRADDR({physical_history_write_addr, 5'b00000}),
                .CLKARDCLK(clk),
                .CLKBWRCLK(clk),
                .ENARDEN(history_read_enable || issue_pcm_read),
                .ENBWREN(history_write_enable),
                .REGCEAREGCE(1'b1),
                .REGCEB(1'b1),
                .RSTRAMARSTRAM(1'b0),
                .RSTRAMB(1'b0),
                .RSTREGARSTREG(1'b0),
                .RSTREGB(1'b0),
                .WEA(2'b00),
                .WEBWE({4{history_write_enable}}),
                .DIADI(history_write_data[15:0]),
                .DIPADIP(2'b00),
                .DIBDI({8'b0, history_write_data[23:16]}),
                .DIPBDIP(2'b00)
            );

            assign shared_read_data = {dob[7:0], doa};
        end
        else begin : gen_behavioral
            reg signed [23:0] memory [0:511];
            reg signed [23:0] read_data_q;
            integer init_index;

            initial begin
                for (init_index = 0; init_index < 512;
                     init_index = init_index + 1)
                    memory[init_index] = 24'sd0;
                $readmemh(MEM_FILE, memory);
            end

            always @(posedge clk) begin
                if (history_read_enable || issue_pcm_read)
                    read_data_q <= memory[selected_read_addr];
                if (history_write_enable)
                    memory[physical_history_write_addr] <=
                        history_write_data;
            end

            assign shared_read_data = read_data_q;
        end
    endgenerate

    always @(posedge clk) begin
        if (!rst_n) begin
            pcm_addr <= family_48k ? ADDR_48K_FIRST : ADDR_44K1_FIRST;
            pcm_request_pending <= 1'b1;
            pcm_prefetch_ready <= 1'b0;
            read_owner_pcm_q <= 1'b0;
            pcm_sample_out <= 24'sd0;
            pcm_sample_update <= 1'b0;
            pcm_sample_addr_dbg <= 8'd0;
            pcm_deadline_miss_dbg <= 1'b0;
        end
        else begin
            pcm_sample_update <= 1'b0;
            read_owner_pcm_q <= issue_pcm_read;

            if (read_owner_pcm_q) begin
                // sample_out doubles as the prefetch buffer.  It changes in
                // the Stage1 idle window and is stable well before the next
                // sample_ce/DAC edge, avoiding a duplicate 24-bit register.
                pcm_sample_out <= shared_read_data;
                pcm_prefetch_ready <= 1'b1;
                pcm_request_pending <= 1'b0;
            end

            if (pcm_sample_ce) begin
                if (pcm_prefetch_ready) begin
                    pcm_sample_update <= 1'b1;
                    pcm_sample_addr_dbg <= pcm_addr;
                end
                else begin
                    pcm_deadline_miss_dbg <= 1'b1;
                end

                if (family_48k) begin
                    if (pcm_addr < ADDR_48K_FIRST ||
                        pcm_addr >= ADDR_48K_LAST)
                        pcm_addr <= ADDR_48K_FIRST;
                    else
                        pcm_addr <= pcm_addr + 8'd1;
                end
                else begin
                    if (pcm_addr >= ADDR_44K1_LAST)
                        pcm_addr <= ADDR_44K1_FIRST;
                    else
                        pcm_addr <= pcm_addr + 8'd1;
                end
                pcm_prefetch_ready <= 1'b0;
                pcm_request_pending <= 1'b1;
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && pcm_sample_ce && !pcm_prefetch_ready)
            $fatal(1, "PCM/Stage1 shared RAM prefetch deadline miss");
    end

    initial begin
        if (SIM_USE_PRIMITIVE != 0 && SIM_USE_PRIMITIVE != 1)
            $fatal(1, "SIM_USE_PRIMITIVE must be 0 or 1");
    end
`endif

endmodule
