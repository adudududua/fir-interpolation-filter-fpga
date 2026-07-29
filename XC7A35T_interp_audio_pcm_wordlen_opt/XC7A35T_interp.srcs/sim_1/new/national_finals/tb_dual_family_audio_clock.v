`timescale 1ps / 1ps

// National-finals clock acceptance:
// 20 MHz -> 5.6448/6.144 MHz, with glitchless family switching.
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
    integer edge_index;
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

    always @(posedge clk_audio_128x)
        high_start = $time;

    always @(negedge clk_audio_128x) begin
        high_width = $time - high_start;
        if (check_high_width && high_width < 70000) begin
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
        edge_index = 0;

        repeat (20) @(posedge clk_20m);
        reset = 1'b0;

        wait (locked_44k1 && locked_48k);

        check_high_width = 1'b1;
        measure_period(1'b0, 177000, 177400);

        family_48k = 1'b1;
        repeat (20) @(posedge clk_audio_128x);
        if (!locked_selected) begin
            $display("FAIL: selected 48 kHz-family MMCM is not locked");
            $fatal(1);
        end
        measure_period(1'b1, 162600, 162900);

        family_48k = 1'b0;
        repeat (20) @(posedge clk_audio_128x);
        measure_period(1'b0, 177000, 177400);

        $display("PASS: dual-family clock frequency and glitchless switching");
        $finish;
    end

endmodule
