`timescale 1ns / 1ps

// Four-column, two-row national-finals keypad scanner.
//
// The selected key is encoded as {valid,family,mode} while a scan is in
// progress.  A later row-0 hit replaces a row-1 hit, preserving the original
// SW1..SW4 priority, while the first column found within a row is retained.
// This replaces two independent found/mode contexts with one priority code.
module matrix_keypad_mode_ctrl_ultracompact #(
    parameter integer SCAN_DIV = 20000,
    parameter integer DEBOUNCE_SCANS = 5,
    parameter integer USE_EXTERNAL_SCAN_TICK = 0
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       scan_tick,
    input  wire [3:0] kc,
    output reg  [3:0] kr_drive_low,
    output reg        family_sel,
    output reg  [1:0] mode_sel
);

    function integer calc_width;
        input integer value;
        integer work;
        begin
            work = value - 1;
            calc_width = 0;
            while (work > 0) begin
                calc_width = calc_width + 1;
                work = work >> 1;
            end
            if (calc_width < 1)
                calc_width = 1;
        end
    endfunction

    localparam integer SCAN_CNT_W = calc_width(SCAN_DIV);
    localparam integer STABLE_W = calc_width(DEBOUNCE_SCANS + 1);

    reg [SCAN_CNT_W-1:0] scan_cnt;
    reg [1:0] scan_idx;
    (* ASYNC_REG = "TRUE" *) reg [1:0] kc_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] kc_sync;

    // {valid, family, mode[1:0]}
    reg [3:0] scan_candidate;
    reg [3:0] raw_candidate;
    reg [STABLE_W-1:0] stable_cnt;
    reg [3:0] scan_candidate_now;

    wire row0_pressed = ~kc_sync[0];
    wire row1_pressed = ~kc_sync[1];
    wire scan_advance = (USE_EXTERNAL_SCAN_TICK != 0) ? scan_tick :
                        (scan_cnt == SCAN_DIV - 1);

    always @(*) begin
        scan_candidate_now = scan_candidate;
        if (row0_pressed &&
            (!scan_candidate[3] || scan_candidate[2]))
            scan_candidate_now = {1'b1, 1'b0, scan_idx};
        else if (row1_pressed && !scan_candidate[3])
            scan_candidate_now = {1'b1, 1'b1, scan_idx};
    end

    always @(posedge clk) begin
        if (!rst_n)
            scan_cnt <= {SCAN_CNT_W{1'b0}};
        else if (USE_EXTERNAL_SCAN_TICK != 0)
            scan_cnt <= {SCAN_CNT_W{1'b0}};
        else if (scan_cnt == SCAN_DIV - 1)
            scan_cnt <= {SCAN_CNT_W{1'b0}};
        else
            scan_cnt <= scan_cnt + {{(SCAN_CNT_W-1){1'b0}}, 1'b1};
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            kc_meta <= 2'b11;
            kc_sync <= 2'b11;
        end
        else begin
            kc_meta <= kc[1:0];
            kc_sync <= kc_meta;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            scan_idx <= 2'd0;
            kr_drive_low <= 4'b0001;
            scan_candidate <= 4'd0;
            raw_candidate <= 4'd0;
            stable_cnt <= {STABLE_W{1'b0}};
            family_sel <= 1'b0;
            mode_sel <= 2'b11;
        end
        else if (scan_advance) begin
            if (scan_idx == 2'd3) begin
                scan_idx <= 2'd0;
                kr_drive_low <= 4'b0001;
                scan_candidate <= 4'd0;

                if (scan_candidate_now == raw_candidate) begin
                    if (stable_cnt < DEBOUNCE_SCANS)
                        stable_cnt <= stable_cnt +
                            {{(STABLE_W-1){1'b0}}, 1'b1};
                    else if (scan_candidate_now[3]) begin
                        family_sel <= scan_candidate_now[2];
                        mode_sel <= scan_candidate_now[1:0];
                    end
                end
                else begin
                    raw_candidate <= scan_candidate_now;
                    stable_cnt <= {STABLE_W{1'b0}};
                end
            end
            else begin
                scan_idx <= scan_idx + 2'd1;
                kr_drive_low <= {kr_drive_low[2:0], kr_drive_low[3]};
                scan_candidate <= scan_candidate_now;
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (SCAN_DIV < 1)
            $fatal(1, "SCAN_DIV must be positive");
        if (DEBOUNCE_SCANS < 1)
            $fatal(1, "DEBOUNCE_SCANS must be positive");
    end
`endif

endmodule
