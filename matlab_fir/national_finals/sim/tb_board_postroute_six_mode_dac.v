`timescale 1ns / 1ps

// Public-pin-only six-mode gate for the routed board netlist.  The test keeps
// the real 20-MHz power-on reset, MMCMs, keypad debounce, family guard, ROM,
// interpolation datapath and DAC ODDR in the loop.  No internal mode/reset
// signal is forced.
module tb_board_postroute_six_mode_dac;
    reg clk;
    reg key_press;
    reg key_family;
    reg [1:0] key_mode;
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

    // SW2/SW3/SW4 are row 0, columns 1/2/3; SW6/SW7/SW8 use
    // the same columns on row 1.  Drive a column only while the DUT scans it.
    always @(*) begin
        key_kc = 4'b1111;
        if (key_press && key_kr[key_mode] === 1'b0)
            key_kc[key_family] = 1'b0;
    end

    always @(posedge dac_clk) begin
        if (measure_enable)
            dac_edge_count = dac_edge_count + 1;
    end

    always @(dac_data) begin
        if (measure_enable && dac_data !== last_dac_data)
            dac_data_change_count = dac_data_change_count + 1;
        last_dac_data = dac_data;
    end

    task measure_mode;
        input [8*20-1:0] mode_name;
        input integer min_edges;
        input integer max_edges;
        input integer min_changes;
        begin
            if (^dac_clk === 1'bx || ^dac_data === 1'bx) begin
                $display("BOARD SIX-MODE FAIL %0s: X before measurement clk=%b data=%h",
                         mode_name, dac_clk, dac_data);
                $finish;
            end

            dac_edge_count = 0;
            dac_data_change_count = 0;
            last_dac_data = dac_data;
            measure_enable = 1'b1;
            #1000000;
            measure_enable = 1'b0;

            $display("BOARD SIX-MODE %0s: edges=%0d data_changes=%0d final_data=%0d",
                     mode_name, dac_edge_count, dac_data_change_count,
                     dac_data);
            if (dac_edge_count < min_edges || dac_edge_count > max_edges) begin
                $display("BOARD SIX-MODE FAIL %0s: DAC clock count outside [%0d,%0d]",
                         mode_name, min_edges, max_edges);
                $finish;
            end
            if (dac_data_change_count < min_changes) begin
                $display("BOARD SIX-MODE FAIL %0s: DAC data is constant or muted",
                         mode_name);
                $finish;
            end
            if (beep_io !== 1'b1) begin
                $display("BOARD SIX-MODE FAIL %0s: beep output is not inactive-high",
                         mode_name);
                $finish;
            end
        end
    endtask

    task select_mode;
        input selected_family;
        input [1:0] selected_mode;
        begin
            key_family = selected_family;
            key_mode = selected_mode;
            key_press = 1'b1;
            // Seven complete scans are required in the worst debounce phase.
            // 26 ms also leaves margin for family reset and FIR history fill.
            #26000000;
        end
    endtask

    initial begin
        key_press = 1'b0;
        key_family = 1'b0;
        key_mode = 2'b11;
        dac_edge_count = 0;
        dac_data_change_count = 0;
        last_dac_data = 8'hxx;
        measure_enable = 1'b0;

        // Default after the real 65535-cycle POR is 44.1 kHz / 128x.
        #4000000;
        measure_mode("44k1_128x", 5600, 5690, 32);

        select_mode(1'b0, 2'b01);
        measure_mode("44k1_4x", 172, 181, 16);

        select_mode(1'b0, 2'b10);
        measure_mode("44k1_8x", 348, 358, 16);

        select_mode(1'b1, 2'b01);
        measure_mode("48k_4x", 188, 197, 16);

        select_mode(1'b1, 2'b10);
        measure_mode("48k_8x", 379, 389, 16);

        select_mode(1'b1, 2'b11);
        measure_mode("48k_128x", 6095, 6195, 32);

        key_press = 1'b0;
        $display("BOARD POSTROUTE SIX-MODE DAC PASS");
        $finish;
    end
endmodule
