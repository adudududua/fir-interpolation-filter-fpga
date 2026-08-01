`timescale 1ns / 1ps

// Two independent read planes replace the unified TDP coefficient RAMB18.
// Both variants preserve its one-clock address-to-data contract:
//   REGISTER_OUTPUT=0: register each address, then read distributed ROM.
//   REGISTER_OUTPUT=1: read each ROM and register both 16-bit outputs.
// The first form trades 11 address FF for lower register cost; the second is
// retained as a controlled A/B point for placement and timing comparison.
module nf_dual_distributed_fir_coeff_rom #(
    parameter integer REGISTER_OUTPUT = 0
)(
    input  wire                         clk,
    input  wire [4:0]                   stage1_addr,
    output wire signed [15:0]           stage1_coeff,
    input  wire [5:0]                   stage23_addr,
    output wire signed [15:0]           stage23_coeff
);

    (* rom_style = "distributed" *) reg signed [15:0] stage1_rom [0:31];
    (* rom_style = "distributed" *) reg signed [15:0] stage23_rom [0:63];
    integer idx;

    initial begin
        for (idx = 0; idx < 32; idx = idx + 1)
            stage1_rom[idx] = 16'sd0;
        for (idx = 0; idx < 64; idx = idx + 1)
            stage23_rom[idx] = 16'sd0;

        stage1_rom[0]  = -16'sd5;
        stage1_rom[1]  =  16'sd7;
        stage1_rom[2]  = -16'sd12;
        stage1_rom[3]  =  16'sd19;
        stage1_rom[4]  = -16'sd29;
        stage1_rom[5]  =  16'sd42;
        stage1_rom[6]  = -16'sd59;
        stage1_rom[7]  =  16'sd80;
        stage1_rom[8]  = -16'sd107;
        stage1_rom[9]  =  16'sd141;
        stage1_rom[10] = -16'sd182;
        stage1_rom[11] =  16'sd233;
        stage1_rom[12] = -16'sd293;
        stage1_rom[13] =  16'sd367;
        stage1_rom[14] = -16'sd455;
        stage1_rom[15] =  16'sd562;
        stage1_rom[16] = -16'sd691;
        stage1_rom[17] =  16'sd849;
        stage1_rom[18] = -16'sd1045;
        stage1_rom[19] =  16'sd1296;
        stage1_rom[20] = -16'sd1629;
        stage1_rom[21] =  16'sd2094;
        stage1_rom[22] = -16'sd2803;
        stage1_rom[23] =  16'sd4044;
        stage1_rom[24] = -16'sd6876;
        stage1_rom[25] =  16'sd20836;

        stage23_rom[0]  = -16'sd115;
        stage23_rom[1]  =  16'sd534;
        stage23_rom[2]  = -16'sd1302;
        stage23_rom[3]  =  16'sd2116;
        stage23_rom[4]  =  16'sd30298;
        stage23_rom[5]  =  16'sd2116;
        stage23_rom[6]  = -16'sd1302;
        stage23_rom[7]  =  16'sd534;
        stage23_rom[8]  = -16'sd115;
        stage23_rom[16] = -16'sd203;
        stage23_rom[17] =  16'sd1233;
        stage23_rom[18] = -16'sd4595;
        stage23_rom[19] =  16'sd19945;
        stage23_rom[20] =  16'sd19945;
        stage23_rom[21] = -16'sd4595;
        stage23_rom[22] =  16'sd1233;
        stage23_rom[23] = -16'sd203;
        stage23_rom[32] =  16'sd404;
        stage23_rom[33] = -16'sd3272;
        stage23_rom[34] =  16'sd19250;
        stage23_rom[35] =  16'sd19250;
        stage23_rom[36] = -16'sd3272;
        stage23_rom[37] =  16'sd404;
        stage23_rom[48] = -16'sd148;
        stage23_rom[49] =  16'sd522;
        stage23_rom[50] =  16'sd32016;
        stage23_rom[51] =  16'sd522;
        stage23_rom[52] = -16'sd148;
    end

    generate
        if (REGISTER_OUTPUT == 0) begin : gen_registered_address
            reg [4:0] stage1_addr_q;
            reg [5:0] stage23_addr_q;
            always @(posedge clk) begin
                stage1_addr_q <= stage1_addr;
                stage23_addr_q <= stage23_addr;
            end
            assign stage1_coeff = stage1_rom[stage1_addr_q];
            assign stage23_coeff = stage23_rom[stage23_addr_q];
        end
        else begin : gen_registered_output
            reg signed [15:0] stage1_coeff_q;
            reg signed [15:0] stage23_coeff_q;
            always @(posedge clk) begin
                stage1_coeff_q <= stage1_rom[stage1_addr];
                stage23_coeff_q <= stage23_rom[stage23_addr];
            end
            assign stage1_coeff = stage1_coeff_q;
            assign stage23_coeff = stage23_coeff_q;
        end
    endgenerate

`ifndef SYNTHESIS
    initial begin
        if (REGISTER_OUTPUT != 0 && REGISTER_OUTPUT != 1)
            $fatal(1, "REGISTER_OUTPUT must be 0 or 1");
    end
`endif

endmodule
