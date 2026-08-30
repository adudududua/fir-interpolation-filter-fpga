`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_dac_offset_binary_compact_equiv.v
// 模块名       : tb_dac_offset_binary_compact_equiv
// 功能简述     : 仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 设计说明     : 本文件采用同步时序设计；复位、时钟使能、
//                有效信号和定点位宽关系均在对应代码段说明。
//                注释仅用于阐明实现，不参与综合结果。
// 设计作者     : kafeizizi
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     : 2026-08-30：统一中文文件头、模块编号与结构说明。
//=============================================================

// Exhaustively proves the signed8 -> offset-binary reduction used by the
// board DAC path. The legacy arithmetic/saturation expression is retained
// only in this testbench as an independent reference.
//=============================================================
// 1）模块名称：tb_dac_offset_binary_compact_equiv
// 功能说明：仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 工程版本：Vivado 2025.2。
//=============================================================
module tb_dac_offset_binary_compact_equiv;

    reg signed [23:0] sample24;
    reg signed [31:0] legacy_ext;
    reg signed [23:0] legacy_sat;
    reg signed [7:0] legacy_s8;
    reg signed [8:0] legacy_bias;
    reg [7:0] legacy_u8;
    reg [7:0] compact_u8;
    integer upper_code;
    integer lower_pattern;

    task compare_one;
        input signed [23:0] value;
        begin
            sample24 = value;
            legacy_ext = {{8{sample24[23]}}, sample24};
            if (legacy_ext > 32'sd8388607)
                legacy_sat = 24'sd8388607;
            else if (legacy_ext < -32'sd8388608)
                legacy_sat = -24'sd8388608;
            else
                legacy_sat = legacy_ext[23:0];

            legacy_s8 = legacy_sat[23:16];
            legacy_bias = $signed({legacy_s8[7], legacy_s8}) + 9'sd128;
            if (legacy_bias < 9'sd0)
                legacy_u8 = 8'd0;
            else if (legacy_bias > 9'sd255)
                legacy_u8 = 8'hff;
            else
                legacy_u8 = legacy_bias[7:0];

            compact_u8 = {~sample24[23], sample24[22:16]};
            #1;
            if (compact_u8 !== legacy_u8) begin
                $display("FAIL: sample=%0d legacy=%0d compact=%0d",
                         sample24, legacy_u8, compact_u8);
                $fatal(1);
            end
        end
    endtask

    initial begin
        // Cover every possible DAC code with four low-word patterns. The low
        // 16 bits cannot affect either implementation, but using multiple
        // patterns guards against an accidental wider slice.
        for (upper_code = 0; upper_code < 256;
             upper_code = upper_code + 1) begin
            for (lower_pattern = 0; lower_pattern < 4;
                 lower_pattern = lower_pattern + 1) begin
                case (lower_pattern)
                    0: compare_one({upper_code[7:0], 16'h0000});
                    1: compare_one({upper_code[7:0], 16'hffff});
                    2: compare_one({upper_code[7:0], 16'h5555});
                    default:
                       compare_one({upper_code[7:0], 16'haaaa});
                endcase
            end
        end

        compare_one(-24'sd8388608);
        compare_one(24'sd8388607);
        compare_one(-24'sd1);
        compare_one(24'sd0);
        compare_one(24'sd1);

        $display("DAC OFFSET-BINARY COMPACT EQUIVALENCE PASS: 1029 samples");
        $finish;
    end

endmodule
