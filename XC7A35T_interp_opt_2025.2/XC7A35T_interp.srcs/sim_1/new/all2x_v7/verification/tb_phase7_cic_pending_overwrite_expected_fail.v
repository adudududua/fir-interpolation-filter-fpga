`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_phase7_cic_pending_overwrite_expected_fail.v
// 模块名       : tb_phase7_cic_pending_overwrite_expected_fail
// 功能简述     : Phase 7 CIC 输入速率约束的预期失败测试。
//                连续两个时钟送入有效样点，故意违反每个输入样点
//                必须留出完整 16 拍输出 burst 的接口约束，验证
//                CIC 核的 pending overwrite 断言能够立即终止仿真。
//
//                本测试必须以 $fatal 结束，不纳入普通 PASS 回归。
//                若仿真自然运行到超时，则表示保护断言失效。
//
// 当前默认配置：
//                  输入位宽：20bit signed
//                  CIC 参数：R=16，M=1，N=3
//                  末级裁剪：0 LSB
//                  预期结果：触发 CIC comb result pending overwrite
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-14
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-14：新增 CIC pending overwrite 负向测试。
//=============================================================
//=============================================================
// 1）模块名称：tb_phase7_cic_pending_overwrite_expected_fail
// 功能说明：仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 工程版本：Vivado 2025.2。
//=============================================================

module tb_phase7_cic_pending_overwrite_expected_fail;

    reg clk;
    reg rst_n;
    reg signed [19:0] x_in;
    reg x_in_valid;

    wire signed [19:0] y_out;
    wire y_out_valid;

    // 例化说明：调用 cic_interp16_core_ce CIC/补偿子模块，完成高倍率插值或通带下垂校正。
    cic_interp16_core_ce #(
        .DATA_W          (20),
        .CIC_ORDER       (3),
        .FINAL_PRUNE_LSB (0)
    ) u_dut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .ce_out              (1'b1),
        .x_in                (x_in),
        .x_in_valid          (x_in_valid),
        .y_out               (y_out),
        .y_out_valid         (y_out_valid),
        .burst_remaining_dbg (),
        .pending_dbg         ()
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        x_in = 20'sd0;
        x_in_valid = 1'b0;

        repeat (4) @(negedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        x_in = 20'sd12345;
        x_in_valid = 1'b1;

        @(negedge clk);
        x_in = -20'sd23456;
        x_in_valid = 1'b1;

        repeat (4) @(negedge clk);
        $fatal(1, "PHASE7 CIC PENDING NEGATIVE TEST FAIL: overwrite assertion did not fire");
    end

endmodule
