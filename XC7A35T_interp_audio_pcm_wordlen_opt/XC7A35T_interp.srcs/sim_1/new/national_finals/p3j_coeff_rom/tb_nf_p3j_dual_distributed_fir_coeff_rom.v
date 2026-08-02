`timescale 1ns / 1ps

module tb_nf_p3j_dual_distributed_fir_coeff_rom;
    reg clk = 1'b0;
    reg [4:0] stage1_addr = 5'd0;
    reg [6:0] stage23_addr = 7'd0;
    wire signed [15:0] s1_addr_q;
    wire signed [17:0] s23_addr_q;
    wire signed [15:0] s1_data_q;
    wire signed [17:0] s23_data_q;
    integer address_index;
    integer errors = 0;

    always #5 clk = ~clk;

    nf_p3j_dual_distributed_fir_coeff_rom #(.REGISTER_OUTPUT(0)) dut_addr_q (
        .clk(clk), .stage1_addr(stage1_addr), .stage1_coeff(s1_addr_q),
        .stage23_addr(stage23_addr), .stage23_coeff(s23_addr_q)
    );
    nf_p3j_dual_distributed_fir_coeff_rom #(.REGISTER_OUTPUT(1)) dut_data_q (
        .clk(clk), .stage1_addr(stage1_addr), .stage1_coeff(s1_data_q),
        .stage23_addr(stage23_addr), .stage23_coeff(s23_data_q)
    );

    function signed [15:0] expected_stage1;
        input [4:0] a;
        begin
            case (a)
                0:expected_stage1=-16'sd5; 1:expected_stage1=16'sd7;
                2:expected_stage1=-16'sd12; 3:expected_stage1=16'sd19;
                4:expected_stage1=-16'sd29; 5:expected_stage1=16'sd42;
                6:expected_stage1=-16'sd59; 7:expected_stage1=16'sd80;
                8:expected_stage1=-16'sd107; 9:expected_stage1=16'sd141;
                10:expected_stage1=-16'sd182; 11:expected_stage1=16'sd233;
                12:expected_stage1=-16'sd293; 13:expected_stage1=16'sd367;
                14:expected_stage1=-16'sd455; 15:expected_stage1=16'sd562;
                16:expected_stage1=-16'sd691; 17:expected_stage1=16'sd849;
                18:expected_stage1=-16'sd1045; 19:expected_stage1=16'sd1296;
                20:expected_stage1=-16'sd1629; 21:expected_stage1=16'sd2094;
                22:expected_stage1=-16'sd2803; 23:expected_stage1=16'sd4044;
                24:expected_stage1=-16'sd6876; 25:expected_stage1=16'sd20836;
                default:expected_stage1=16'sd0;
            endcase
        end
    endfunction

    function signed [17:0] expected_stage23;
        input [6:0] a;
        begin
            case (a)
                0:expected_stage23=-18'sd115; 1:expected_stage23=18'sd534;
                2:expected_stage23=-18'sd1302; 3:expected_stage23=18'sd2116;
                4:expected_stage23=18'sd30298; 5:expected_stage23=18'sd2116;
                6:expected_stage23=-18'sd1302; 7:expected_stage23=18'sd534;
                8:expected_stage23=-18'sd115;
                16:expected_stage23=-18'sd203; 17:expected_stage23=18'sd1233;
                18:expected_stage23=-18'sd4595; 19:expected_stage23=18'sd19945;
                20:expected_stage23=18'sd19945; 21:expected_stage23=-18'sd4595;
                22:expected_stage23=18'sd1233; 23:expected_stage23=-18'sd203;
                32:expected_stage23=18'sd404; 33:expected_stage23=-18'sd3272;
                34:expected_stage23=18'sd19250; 35:expected_stage23=18'sd19250;
                36:expected_stage23=-18'sd3272; 37:expected_stage23=18'sd404;
                48:expected_stage23=-18'sd148; 49:expected_stage23=18'sd522;
                50:expected_stage23=18'sd32016; 51:expected_stage23=18'sd522;
                52:expected_stage23=-18'sd148;
                96:expected_stage23=18'sd561; 97:expected_stage23=-18'sd4232;
                98:expected_stage23=18'sd20046; 99:expected_stage23=18'sd20046;
                100:expected_stage23=-18'sd4232; 101:expected_stage23=18'sd561;
                112:expected_stage23=18'sd137; 113:expected_stage23=-18'sd1554;
                114:expected_stage23=18'sd35584; 115:expected_stage23=-18'sd1554;
                116:expected_stage23=18'sd137;
                default:expected_stage23=18'sd0;
            endcase
        end
    endfunction

    initial begin
        for (address_index = 0; address_index < 128;
                address_index = address_index + 1) begin
            @(negedge clk);
            stage1_addr = address_index[4:0];
            stage23_addr = address_index[6:0];
            @(posedge clk); #1;
            if (s1_addr_q !== expected_stage1(stage1_addr) ||
                s1_data_q !== expected_stage1(stage1_addr) ||
                s23_addr_q !== expected_stage23(stage23_addr) ||
                s23_data_q !== expected_stage23(stage23_addr))
                errors = errors + 1;
        end
        if (errors != 0)
            $fatal(1, "P3-J dual distributed coefficient ROM FAIL errors=%0d", errors);
        $display("P3-J DUAL DISTRIBUTED COEFFICIENT ROM PASS: 32 Stage1 + 128 Stage23 addresses, two register modes equivalent");
        $finish;
    end
endmodule
