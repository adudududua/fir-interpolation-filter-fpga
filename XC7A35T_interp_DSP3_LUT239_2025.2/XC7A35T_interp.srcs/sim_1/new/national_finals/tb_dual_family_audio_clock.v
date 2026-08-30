`timescale 1ps / 1ps

//=============================================================
// 文件名       : tb_dual_family_audio_clock.v
// 模块名       : tb_dual_family_audio_clock
// 功能简述     : 双采样率音频时钟模块的板级原语验收测试。
//                输入 20 MHz，经两组 MMCM 产生 5.6448 MHz 与
//                6.144 MHz，并通过 BUFGMUX_CTRL 无毛刺切换。
//
//                测试等待两组 MMCM 锁定，测量切换前后的周期与
//                高低脉宽，重点检查 family 切换时不存在短脉冲、
//                停钟或错误的 locked_selected 状态。
//
// 当前默认配置：时间精度 1 ps，输入时钟 20 MHz
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-29
// 版本         : V2025.2
// 开发工具     : Vivado Simulator 2025.2
// 修订记录     :
//                2026-07-29：新增双 MMCM 无毛刺切换验收。
//                2026-08-16：补充中文时钟测量和判定说明。
//=============================================================

module tb_dual_family_audio_clock;

    reg clk_20m;
    reg reset;
    reg family_48k;
    wire clk_audio_128x;
    wire locked_selected;
    wire locked_44k1;
    wire locked_48k;

    time rise_start;
    time rise_stop;
    time high_start;
    time high_width;
    time low_start;
    time low_width;
    integer edge_index;
    integer switch_index;
    reg check_high_width;

    dual_family_audio_clock u_dut (
        .clk_20m          (clk_20m),
        .reset            (reset),
        .family_48k       (family_48k),
        .clk_audio_128x   (clk_audio_128x),
        .locked_selected  (locked_selected),
        .locked_44k1      (locked_44k1),
        .locked_48k       (locked_48k)
    );

    always #25000 clk_20m = ~clk_20m;

    initial begin
        #200000000;
        if (!(locked_44k1 && locked_48k)) begin
            $display("FAIL: dual MMCM lock timeout");
            $fatal(1);
        end
    end

    always @(posedge clk_audio_128x) begin
        high_start = $time;
        low_width = $time - low_start;
        if (check_high_width && low_width < 65000) begin
            $display("FAIL: runt low pulse during family switch: %0d ps",
                     low_width);
            $fatal(1);
        end
    end

    always @(negedge clk_audio_128x) begin
        high_width = $time - high_start;
        low_start = $time;
        if (check_high_width && high_width < 65000) begin
            $display("FAIL: runt high pulse during family switch: %0d ps",
                     high_width);
            $fatal(1);
        end
    end

    task measure_period;
        input expected_family;
        input time min_period_ps;
        input time max_period_ps;
        time average_period_ps;
        begin
            if (family_48k !== expected_family ||
                locked_selected !== 1'b1) begin
                $display("FAIL: clock selection/lock mismatch");
                $fatal(1);
            end
            repeat (12) @(posedge clk_audio_128x);
            rise_start = $time;
            repeat (100) @(posedge clk_audio_128x);
            rise_stop = $time;
            average_period_ps = (rise_stop - rise_start) / 100;
            if (average_period_ps < min_period_ps ||
                average_period_ps > max_period_ps) begin
                $display("FAIL: family=%0d period=%0d ps outside [%0d,%0d]",
                         expected_family, average_period_ps,
                         min_period_ps, max_period_ps);
                $fatal(1);
            end
            $display("CLOCK family=%0d average_period=%0d ps frequency=%0f Hz",
                     expected_family, average_period_ps,
                     1.0e12 / average_period_ps);
        end
    endtask

    initial begin
        clk_20m = 1'b0;
        reset = 1'b1;
        family_48k = 1'b0;
        check_high_width = 1'b0;
        rise_start = 0;
        rise_stop = 0;
        high_start = 0;
        high_width = 0;
        low_start = 0;
        low_width = 0;
        edge_index = 0;
        switch_index = 0;

        repeat (20) @(posedge clk_20m);
        reset = 1'b0;

        wait (locked_44k1 && locked_48k);

        check_high_width = 1'b1;
        measure_period(1'b0, 177000, 177400);

        for (switch_index = 0; switch_index < 100;
             switch_index = switch_index + 1) begin
            @(negedge clk_20m);
            family_48k = ~family_48k;
            repeat (8) @(posedge clk_audio_128x);
            if (!locked_selected) begin
                $display("FAIL: selected family MMCM is not locked at switch %0d",
                         switch_index);
                $fatal(1);
            end
        end

        family_48k = 1'b1;
        repeat (20) @(posedge clk_audio_128x);
        measure_period(1'b1, 162600, 162900);

        family_48k = 1'b0;
        repeat (20) @(posedge clk_audio_128x);
        measure_period(1'b0, 177000, 177400);

        $display("PASS: dual-family clock frequency and glitchless switching; 100-switch pulse-width stress");
        $finish;
    end

endmodule
