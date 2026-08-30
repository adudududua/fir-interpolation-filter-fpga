`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_dac_offset_binary_compact_equiv.v
// 模块名       : tb_dac_offset_binary_compact_equiv
// 功能简述     : DAC 有符号 24 bit 到 8 bit 偏移二进制紧凑映射的
//                穷举等价证明。测试平台保留旧版扩展、饱和、截位和
//                加 128 运算作为独立参考，并与紧凑符号位翻转表达式
//                {~sample24[23], sample24[22:16]} 逐项比较。
//
//                256 个 DAC 高字节码各配合 4 组低 16 位模式，
//                用于证明低位不会影响 DAC 码且映射结果完全一致。
//
// 当前默认配置：覆盖 256×4 个 24 bit 输入组合
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-29
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-29：新增偏移二进制穷举等价测试。
//                2026-08-16：统一中文文件头及覆盖范围说明。
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
        // 用4种低字模式遍历全部DAC码。低16位理论上不影响任一实现，但多种
        // 模式可防止代码误用更宽切片而未被测试发现。
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
