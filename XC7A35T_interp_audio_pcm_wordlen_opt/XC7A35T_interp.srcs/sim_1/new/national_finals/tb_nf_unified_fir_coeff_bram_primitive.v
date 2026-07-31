`timescale 1ns / 1ps

// Verifies the actual RAMB18E1 INIT/address mapping used in bitstream builds.
// The regression compiles this test with SYNTHESIS defined, so it exercises
// the primitive branch rather than the behavioral coefficient array.
module tb_nf_unified_fir_coeff_bram_primitive;
    reg clk = 1'b0;
    reg [4:0] stage1_addr = 5'd0;
    reg [5:0] stage23_addr = 6'd0;
    wire signed [15:0] stage1_coeff;
    wire signed [15:0] stage23_coeff;

    integer addr;
    integer errors = 0;

    always #5 clk = ~clk;

    nf_unified_fir_coeff_bram dut (
        .clk(clk),
        .stage1_addr(stage1_addr),
        .stage1_coeff(stage1_coeff),
        .stage23_addr(stage23_addr),
        .stage23_coeff(stage23_coeff)
    );

    function signed [15:0] expected_stage1;
        input [4:0] index;
        begin
            case (index)
                5'd0:  expected_stage1 = -16'sd5;
                5'd1:  expected_stage1 =  16'sd7;
                5'd2:  expected_stage1 = -16'sd12;
                5'd3:  expected_stage1 =  16'sd19;
                5'd4:  expected_stage1 = -16'sd29;
                5'd5:  expected_stage1 =  16'sd42;
                5'd6:  expected_stage1 = -16'sd59;
                5'd7:  expected_stage1 =  16'sd80;
                5'd8:  expected_stage1 = -16'sd107;
                5'd9:  expected_stage1 =  16'sd141;
                5'd10: expected_stage1 = -16'sd182;
                5'd11: expected_stage1 =  16'sd233;
                5'd12: expected_stage1 = -16'sd293;
                5'd13: expected_stage1 =  16'sd367;
                5'd14: expected_stage1 = -16'sd455;
                5'd15: expected_stage1 =  16'sd562;
                5'd16: expected_stage1 = -16'sd691;
                5'd17: expected_stage1 =  16'sd849;
                5'd18: expected_stage1 = -16'sd1045;
                5'd19: expected_stage1 =  16'sd1296;
                5'd20: expected_stage1 = -16'sd1629;
                5'd21: expected_stage1 =  16'sd2094;
                5'd22: expected_stage1 = -16'sd2803;
                5'd23: expected_stage1 =  16'sd4044;
                5'd24: expected_stage1 = -16'sd6876;
                5'd25: expected_stage1 =  16'sd20836;
                default: expected_stage1 = 16'sd0;
            endcase
        end
    endfunction

    function signed [15:0] expected_stage23;
        input [5:0] index;
        begin
            case (index)
                6'd0:  expected_stage23 = -16'sd115;
                6'd1:  expected_stage23 =  16'sd534;
                6'd2:  expected_stage23 = -16'sd1302;
                6'd3:  expected_stage23 =  16'sd2116;
                6'd4:  expected_stage23 =  16'sd30298;
                6'd5:  expected_stage23 =  16'sd2116;
                6'd6:  expected_stage23 = -16'sd1302;
                6'd7:  expected_stage23 =  16'sd534;
                6'd8:  expected_stage23 = -16'sd115;
                6'd16: expected_stage23 = -16'sd203;
                6'd17: expected_stage23 =  16'sd1233;
                6'd18: expected_stage23 = -16'sd4595;
                6'd19: expected_stage23 =  16'sd19945;
                6'd20: expected_stage23 =  16'sd19945;
                6'd21: expected_stage23 = -16'sd4595;
                6'd22: expected_stage23 =  16'sd1233;
                6'd23: expected_stage23 = -16'sd203;
                6'd32: expected_stage23 =  16'sd404;
                6'd33: expected_stage23 = -16'sd3272;
                6'd34: expected_stage23 =  16'sd19250;
                6'd35: expected_stage23 =  16'sd19250;
                6'd36: expected_stage23 = -16'sd3272;
                6'd37: expected_stage23 =  16'sd404;
                6'd48: expected_stage23 = -16'sd148;
                6'd49: expected_stage23 =  16'sd522;
                6'd50: expected_stage23 =  16'sd32016;
                6'd51: expected_stage23 =  16'sd522;
                6'd52: expected_stage23 = -16'sd148;
                default: expected_stage23 = 16'sd0;
            endcase
        end
    endfunction

    initial begin
        // glbl holds the primitive model in global reset for about 100 ns.
        #120;

        // Check every address, including all intentionally zero-filled holes.
        for (addr = 0; addr < 64; addr = addr + 1) begin
            @(negedge clk);
            stage1_addr = addr[4:0];
            stage23_addr = addr[5:0];
            @(posedge clk);
            #1;

            if (addr < 32 &&
                stage1_coeff !== expected_stage1(addr[4:0])) begin
                $display("Stage1 primitive mismatch addr=%0d actual=%0d expected=%0d",
                         stage1_addr, stage1_coeff,
                         expected_stage1(addr[4:0]));
                errors = errors + 1;
            end

            if (stage23_coeff !== expected_stage23(addr[5:0])) begin
                $display("Stage23 primitive mismatch addr=%0d actual=%0d expected=%0d",
                         stage23_addr, stage23_coeff,
                         expected_stage23(addr[5:0]));
                errors = errors + 1;
            end
        end

        if (errors != 0)
            $fatal(1, "Unified coefficient RAMB18 primitive FAIL errors=%0d",
                   errors);

        $display("UNIFIED COEFFICIENT RAMB18 PRIMITIVE PASS: 32 Stage1 + 64 Stage23 addresses");
        $finish;
    end
endmodule
