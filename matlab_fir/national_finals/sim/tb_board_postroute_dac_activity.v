`timescale 1ns / 1ps

// Public-pin-only gate for the implemented board design.  It intentionally
// includes the real MMCMs, 65535-cycle power-on reset, test-tone ROM, complete
// interpolation chain and DAC ODDR.  This catches synthesis-only failures that
// an RTL testbench cannot see, such as a ROM INIT image that differs from the
// procedural RTL initialization semantics.
module tb_board_postroute_dac_activity;
    reg clk;
    reg [3:0] key_kc;
    wire [3:0] key_kr;
    wire dac_clk;
    wire [7:0] dac_data;
    wire beep_io;

    integer dac_edge_count;
    integer dac_data_change_count;
    reg [7:0] last_dac_data;
    reg measure_enable;

    board_demo_competition_dac8_top dut (
        .clk(clk),
        .key_kr(key_kr),
        .key_kc(key_kc),
        .dac_clk(dac_clk),
        .dac_data(dac_data),
        .beep_io(beep_io)
    );

    initial clk = 1'b0;
    always #25 clk = ~clk;

    always @(posedge dac_clk) begin
        if (measure_enable)
            dac_edge_count = dac_edge_count + 1;
    end

    always @(dac_data) begin
        if (measure_enable && dac_data !== last_dac_data)
            dac_data_change_count = dac_data_change_count + 1;
        last_dac_data = dac_data;
    end

    initial begin
        key_kc = 4'b1111;
        dac_edge_count = 0;
        dac_data_change_count = 0;
        last_dac_data = 8'hxx;
        measure_enable = 1'b0;

        // The real top holds reset for 65535 cycles at 20 MHz (3.277 ms).
        // Leave margin for both MMCMs to lock and for audio reset release.
        #4000000;
        if (^dac_clk === 1'bx || ^dac_data === 1'bx) begin
            $display("BOARD POSTROUTE DAC ACTIVITY FAIL: X after startup clk=%b data=%h",
                     dac_clk, dac_data);
            $finish;
        end

        dac_edge_count = 0;
        dac_data_change_count = 0;
        last_dac_data = dac_data;
        measure_enable = 1'b1;
        #2000000;
        measure_enable = 1'b0;

        $display("BOARD POSTROUTE DAC: edges=%0d data_changes=%0d final_data=%0d beep=%b",
                 dac_edge_count, dac_data_change_count, dac_data, beep_io);
        if (dac_edge_count < 10000) begin
            $display("BOARD POSTROUTE DAC ACTIVITY FAIL: forwarded DAC clock is absent or too slow");
            $finish;
        end
        if (dac_data_change_count < 32) begin
            $display("BOARD POSTROUTE DAC ACTIVITY FAIL: DAC data remains constant or muted");
            $finish;
        end
        if (beep_io !== 1'b1) begin
            $display("BOARD POSTROUTE DAC ACTIVITY FAIL: beep output is not inactive-high");
            $finish;
        end

        $display("BOARD POSTROUTE DAC ACTIVITY PASS");
        $finish;
    end
endmodule
