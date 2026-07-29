`timescale 1ns / 1ps
//=============================================================
// 文件名       : tb_dac_clock_frequency_meter.v
// 模块名       : tb_dac_clock_frequency_meter
// 功能简述     : 验证独立100MHz参考时钟对约5.645161MHz DAC_CLK
//                的100ms闸门计数和Hz换算结果。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-19
// 版本         : V2018.3
// 开发工具     : Vivado Simulator
// 修订记录     :
//                2026-07-19：新增DAC采样时钟测频模块专项仿真。
//=============================================================

module tb_dac_clock_frequency_meter;

    reg clk_ref_100m = 1'b0;
    reg rst_n = 1'b0;
    reg signal_in_async = 1'b0;

    wire [23:0] frequency_hz;
    wire [19:0] edge_count_100ms;
    wire measurement_toggle;

    always #5 clk_ref_100m = ~clk_ref_100m;

    // 实现报告周期为177.143ns。两个半周期分别取88.571ns和
    // 88.572ns，避免1ps仿真精度对重复小数累计取整。
    always begin
        #88.571 signal_in_async = ~signal_in_async;
        #88.572 signal_in_async = ~signal_in_async;
    end

    dac_clock_frequency_meter u_dac_clock_frequency_meter (
        .clk_ref_100m       (clk_ref_100m),
        .rst_n              (rst_n),
        .signal_in_async    (signal_in_async),
        .frequency_hz       (frequency_hz),
        .edge_count_100ms   (edge_count_100ms),
        .measurement_toggle (measurement_toggle)
    );

    initial begin
        #200;
        rst_n = 1'b1;

        @(posedge measurement_toggle);
        #20;

        $display("DAC_FREQ_RESULT edges_100ms=%0d frequency_hz=%0d",
                 edge_count_100ms, frequency_hz);

        if ((edge_count_100ms < 20'd564515) ||
            (edge_count_100ms > 20'd564517)) begin
            $display("FAIL: unexpected 100ms edge count");
            $finish;
        end

        if (frequency_hz != edge_count_100ms * 10) begin
            $display("FAIL: Hz result is not edge_count_100ms multiplied by 10");
            $finish;
        end

        $display("PASS: independent 100MHz DAC clock frequency meter");
        $finish;
    end

endmodule
