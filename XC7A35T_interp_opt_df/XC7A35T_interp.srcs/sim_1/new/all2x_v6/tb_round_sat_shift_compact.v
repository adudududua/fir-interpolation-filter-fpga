`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_round_sat_shift_compact.v
// 模块名       : tb_round_sat_shift_compact
// 功能简述     : Phase 6 紧凑级间缩位模块等价测试。
//                同时验证 24->22、22->20、20->18 三种配置，
//                使用原 round_sat_q16_to24 作为参考，覆盖边界值
//                和 100000 组确定性随机有符号输入。
//
// 当前默认配置：
//                  舍入规则：中点远离 0
//                  比较标准：全部输出误差 0 LSB
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-13
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-13：新增紧凑级间缩位等价测试。
//=============================================================

module tb_round_sat_shift_compact;

    reg signed [23:0] din24;
    reg signed [21:0] din22;
    reg signed [19:0] din20;
    wire signed [24:0] din24_ext = {din24[23], din24};
    wire signed [22:0] din22_ext = {din22[21], din22};
    wire signed [20:0] din20_ext = {din20[19], din20};
    wire signed [21:0] ref22;
    wire signed [21:0] dut22;
    wire signed [19:0] ref20;
    wire signed [19:0] dut20;
    wire signed [17:0] ref18;
    wire signed [17:0] dut18;

    integer test_index;
    integer random_state;

    round_sat_q16_to24 #(
        .IN_W(25), .OUT_W(22), .FRAC_W(2)
    ) u_ref_24_to_22 (
        .din_full(din24_ext), .dout_24(ref22)
    );

    round_sat_shift_compact #(
        .IN_W(24), .OUT_W(22), .SHIFT_N(2)
    ) u_dut_24_to_22 (
        .din(din24), .dout(dut22)
    );

    round_sat_q16_to24 #(
        .IN_W(23), .OUT_W(20), .FRAC_W(2)
    ) u_ref_22_to_20 (
        .din_full(din22_ext), .dout_24(ref20)
    );

    round_sat_shift_compact #(
        .IN_W(22), .OUT_W(20), .SHIFT_N(2)
    ) u_dut_22_to_20 (
        .din(din22), .dout(dut20)
    );

    round_sat_q16_to24 #(
        .IN_W(21), .OUT_W(18), .FRAC_W(2)
    ) u_ref_20_to_18 (
        .din_full(din20_ext), .dout_24(ref18)
    );

    round_sat_shift_compact #(
        .IN_W(20), .OUT_W(18), .SHIFT_N(2)
    ) u_dut_20_to_18 (
        .din(din20), .dout(dut18)
    );

    task check_outputs;
        begin
            #1;
            if (dut22 !== ref22)
                $fatal(1, "24->22 mismatch din=%0d ref=%0d dut=%0d",
                       din24, ref22, dut22);
            if (dut20 !== ref20)
                $fatal(1, "22->20 mismatch din=%0d ref=%0d dut=%0d",
                       din22, ref20, dut20);
            if (dut18 !== ref18)
                $fatal(1, "20->18 mismatch din=%0d ref=%0d dut=%0d",
                       din20, ref18, dut18);
        end
    endtask

    initial begin
        din24 = 24'sd0;
        din22 = 22'sd0;
        din20 = 20'sd0;
        random_state = 32'h26071351;
        check_outputs();

        din24 = 24'sh7fffff;
        din22 = 22'sh1fffff;
        din20 = 20'sh7ffff;
        check_outputs();

        din24 = -24'sh800000;
        din22 = -22'sh200000;
        din20 = -20'sh80000;
        check_outputs();

        din24 = 24'sd2;
        din22 = 22'sd2;
        din20 = 20'sd2;
        check_outputs();

        din24 = -24'sd2;
        din22 = -22'sd2;
        din20 = -20'sd2;
        check_outputs();

        for (test_index = 0; test_index < 100000;
             test_index = test_index + 1) begin
            din24 = $random(random_state);
            din22 = $random(random_state);
            din20 = $random(random_state);
            check_outputs();
        end

        $display("PASS: compact interstage wordlength rounder, 100000 random sets");
        $finish;
    end

endmodule
