`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_round_sat_q15_compact_to24.v
// 模块名       : tb_round_sat_q15_compact_to24
// 功能简述     : Q15 紧凑舍入饱和模块逐位等价测试。
//                将原 42bit 偏置加法实现作为参考，与紧凑余数
//                进位实现比较，覆盖舍入中点、饱和边界和随机值。
//
// 当前默认配置：
//                  输入位宽：42bit signed Q15
//                  输出位宽：24bit signed
//                  可达范围：40bit signed 累加值符号扩展到 42bit
//                  随机样本：100000
//                  通过标准：全部输出误差为 0 LSB
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-12
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-12：新增紧凑舍入模块等价测试。
//=============================================================
//=============================================================
// 1）模块名称：tb_round_sat_q15_compact_to24
// 功能说明：仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 工程版本：Vivado 2025.2。
//=============================================================

module tb_round_sat_q15_compact_to24;

    reg signed [41:0] din_full;
    wire signed [23:0] reference_out;
    wire signed [23:0] compact_out;

    integer seed;
    integer test_index;
    reg [63:0] random_wide;

    // 例化说明：调用 round_sat_q16_to24 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    round_sat_q16_to24 #(
        .IN_W   (42),
        .OUT_W  (24),
        .FRAC_W (15)
    ) u_reference (
        .din_full (din_full),
        .dout_24  (reference_out)
    );

    // 例化说明：调用 round_sat_q15_compact_to24 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    round_sat_q15_compact_to24 #(
        .IN_W  (42),
        .OUT_W (24)
    ) u_compact (
        .din_full (din_full),
        .dout_24  (compact_out)
    );

    task check_one;
        input signed [41:0] test_value;
        begin
            din_full = test_value;
            #1;
            if (reference_out !== compact_out)
                $fatal(1,
                    "Round mismatch din=%0d ref=%0d compact=%0d",
                    din_full, reference_out, compact_out);
        end
    endtask

    initial begin
        seed = 32'h31415927;
        din_full = 42'sd0;

        check_one(42'sd0);
        check_one(42'sd1);
        check_one(-42'sd1);
        check_one(42'sd16383);
        check_one(42'sd16384);
        check_one(42'sd16385);
        check_one(-42'sd16383);
        check_one(-42'sd16384);
        check_one(-42'sd16385);
        check_one(42'sd32767);
        check_one(42'sd32768);
        check_one(-42'sd32767);
        check_one(-42'sd32768);

        check_one((42'sd8388607 <<< 15) - 42'sd1);
        check_one((42'sd8388607 <<< 15) + 42'sd16384);
        check_one((42'sd8388607 <<< 15) + 42'sd32767);
        check_one((42'sd8388608 <<< 15));
        check_one((-42'sd8388608 <<< 15));
        check_one((-42'sd8388608 <<< 15) - 42'sd16384);
        check_one((-42'sd8388608 <<< 15) - 42'sd32768);

        check_one(42'sh07fffffffff);
        check_one(-42'sh0800000000);

        for (test_index = 0; test_index < 100000;
             test_index = test_index + 1) begin
            random_wide = {$random(seed), $random(seed)};
            check_one({{2{random_wide[39]}}, random_wide[39:0]});
        end

        $display("PASS: compact Q15 round/saturation 100000 random vectors");
        $finish;
    end

endmodule
