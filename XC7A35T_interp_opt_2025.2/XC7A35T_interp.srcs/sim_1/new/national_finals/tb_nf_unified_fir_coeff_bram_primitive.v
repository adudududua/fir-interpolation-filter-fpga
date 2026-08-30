`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_nf_unified_fir_coeff_bram_primitive.v
// 模块名       : tb_nf_unified_fir_coeff_bram_primitive
// 功能简述     : 仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 设计说明     : 本文件采用同步时序设计；复位、时钟使能、
//                有效信号和定点位宽关系均在对应代码段说明。
//                注释仅用于阐明实现，不参与综合结果。
// 设计作者     : kafeizizi
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     : 2026-08-30：统一中文文件头、模块编号与结构说明。
//=============================================================

// Verifies the actual RAMB18E1 INIT/address mapping used in bitstream builds.
// The regression compiles this test with SYNTHESIS defined, so it exercises
// the primitive branch rather than the behavioral coefficient array.
//=============================================================
// 1）模块名称：tb_nf_unified_fir_coeff_bram_primitive
// 功能说明：仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 工程版本：Vivado 2025.2。
//=============================================================
module tb_nf_unified_fir_coeff_bram_primitive;
    reg clk = 1'b0;
    reg [5:0] stage1_addr = 6'd0;
    reg [6:0] stage23_addr = 7'd0;
    wire signed [15:0] stage1_coeff;
    wire signed [17:0] stage23_coeff;

    integer addr;
    integer errors = 0;

    always #5 clk = ~clk;

    // 例化说明：调用 nf_unified_fir_coeff_bram 全国赛签核子模块，完成正式数据通路中的存储、运算或控制任务。
    nf_unified_fir_coeff_bram dut (
        .clk(clk),
        .stage1_addr(stage1_addr),
        .stage1_coeff(stage1_coeff),
        .stage23_addr(stage23_addr),
        .stage23_coeff(stage23_coeff)
    );

    function signed [15:0] expected_stage1;
        input [5:0] index;
        reg [4:0] symmetric_index;
        begin
            symmetric_index = (index < 6'd26) ? index[4:0] :
                              (6'd51-index);
            case (symmetric_index)
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

    function signed [17:0] expected_stage23;
        input [6:0] index;
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
                7'd64: expected_stage23 = -18'sd5;
                7'd65: expected_stage23 =  18'sd7;
                7'd66: expected_stage23 = -18'sd12;
                7'd67: expected_stage23 =  18'sd19;
                7'd68: expected_stage23 = -18'sd29;
                7'd69: expected_stage23 =  18'sd42;
                7'd70: expected_stage23 = -18'sd59;
                7'd71: expected_stage23 =  18'sd80;
                7'd72: expected_stage23 = -18'sd107;
                7'd73: expected_stage23 =  18'sd141;
                7'd74: expected_stage23 = -18'sd182;
                7'd75: expected_stage23 =  18'sd233;
                7'd76: expected_stage23 = -18'sd293;
                7'd77: expected_stage23 =  18'sd367;
                7'd78: expected_stage23 = -18'sd455;
                7'd79: expected_stage23 =  18'sd562;
                7'd80: expected_stage23 = -18'sd691;
                7'd81: expected_stage23 =  18'sd849;
                7'd82: expected_stage23 = -18'sd1045;
                7'd83: expected_stage23 =  18'sd1296;
                7'd84: expected_stage23 = -18'sd1629;
                7'd85: expected_stage23 =  18'sd2094;
                7'd86: expected_stage23 = -18'sd2803;
                7'd87: expected_stage23 =  18'sd4044;
                7'd88: expected_stage23 = -18'sd6876;
                7'd89: expected_stage23 =  18'sd20836;
                7'd96:  expected_stage23 =  18'sd561;
                7'd97:  expected_stage23 = -18'sd4232;
                7'd98:  expected_stage23 =  18'sd20046;
                7'd99:  expected_stage23 =  18'sd20046;
                7'd100: expected_stage23 = -18'sd4232;
                7'd101: expected_stage23 =  18'sd561;
                7'd112: expected_stage23 =  18'sd137;
                7'd113: expected_stage23 = -18'sd1554;
                7'd114: expected_stage23 =  18'sd35584;
                7'd115: expected_stage23 = -18'sd1554;
                7'd116: expected_stage23 =  18'sd137;
                default: expected_stage23 = 18'sd0;
            endcase
        end
    endfunction

    initial begin
        // glbl holds the primitive model in global reset for about 100 ns.
        #120;

        // Check every address, including all intentionally zero-filled holes.
        for (addr = 0; addr < 128; addr = addr + 1) begin
            @(negedge clk);
            stage1_addr = addr[5:0];
            stage23_addr = addr[6:0];
            @(posedge clk);
            #1;

            if (addr < 52 &&
                stage1_coeff !== expected_stage1(addr[5:0])) begin
                $display("Stage1 primitive mismatch addr=%0d actual=%0d expected=%0d",
                         stage1_addr, stage1_coeff,
                         expected_stage1(addr[5:0]));
                errors = errors + 1;
            end

            if (stage23_coeff !== expected_stage23(addr[6:0])) begin
                $display("Stage23 primitive mismatch addr=%0d actual=%0d expected=%0d",
                         stage23_addr, stage23_coeff,
                         expected_stage23(addr[6:0]));
                errors = errors + 1;
            end
        end

        if (errors != 0)
            $fatal(1, "Unified coefficient RAMB18 primitive FAIL errors=%0d",
                   errors);

        $display("UNIFIED COEFFICIENT RAMB18 PRIMITIVE PASS: 52 expanded Stage1 + 128 Stage23 addresses with signed18 parity");
        $finish;
    end
endmodule
