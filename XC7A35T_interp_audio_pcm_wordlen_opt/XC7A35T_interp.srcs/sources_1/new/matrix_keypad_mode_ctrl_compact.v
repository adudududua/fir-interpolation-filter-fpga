`timescale 1ns / 1ps
//=============================================================
// 文件名       : matrix_keypad_mode_ctrl_compact.v
// 模块名       : matrix_keypad_mode_ctrl_compact
// 功能简述     : 赛方板 4x4 矩阵按键的紧凑四档模式控制器。
//                仅保留演示实际使用的 SW1～SW8：
//                  SW1～SW4：44.1 kHz 的 1x/4x/8x/128x
//                  SW5～SW8：48 kHz 的 1x/4x/8x/128x
//                KC2/KC3 对应的 SW9～SW16 不改变模式。
//                相比完整 16 键位图实现，本模块直接保存每轮扫描
//                的候选模式，并保留输入同步、整轮消抖和行优先级。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-18
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-18：新增紧凑四档矩阵按键扫描版本。
//                2026-07-18：支持顶层选择二次幂扫描分频优化候选。
//                2026-07-18：增加外部扫描使能输入，支持复用顶层计数器。
//=============================================================

module matrix_keypad_mode_ctrl_compact #(
    parameter integer SCAN_DIV       = 20000,
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

    reg       row0_found;
    reg [1:0] row0_mode;
    reg       row1_found;
    reg [1:0] row1_mode;

    reg       raw_valid;
    reg       raw_family;
    reg [1:0] raw_mode;
    reg [STABLE_W-1:0] stable_cnt;

    wire row0_pressed;
    wire row1_pressed;
    wire row0_found_now;
    wire row1_found_now;
    wire [1:0] row0_mode_now;
    wire [1:0] row1_mode_now;
    wire scan_valid_now;
    wire scan_family_now;
    wire [1:0] scan_mode_now;
    wire scan_same_as_raw;
    wire scan_advance;

    assign row0_pressed = ~kc_sync[0];
    assign row1_pressed = ~kc_sync[1];

    assign row0_found_now = row0_found | row0_pressed;
    assign row1_found_now = row1_found | row1_pressed;
    assign row0_mode_now = row0_found ? row0_mode : scan_idx;
    assign row1_mode_now = row1_found ? row1_mode : scan_idx;

    // 完全沿用原扫描器的键码优先顺序：SW1～SW4 优先于 SW5～SW8。
    assign scan_valid_now = row0_found_now | row1_found_now;
    assign scan_family_now = !row0_found_now && row1_found_now;
    assign scan_mode_now = row0_found_now ? row0_mode_now : row1_mode_now;
    assign scan_same_as_raw = (scan_valid_now == raw_valid) &&
                              (!scan_valid_now ||
                               (scan_family_now == raw_family &&
                                scan_mode_now == raw_mode));
    assign scan_advance = (USE_EXTERNAL_SCAN_TICK != 0) ? scan_tick :
                          (scan_cnt == SCAN_DIV - 1);

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
            scan_idx      <= 2'd0;
            kr_drive_low  <= 4'b0001;

            row0_found    <= 1'b0;
            row0_mode     <= 2'd0;
            row1_found    <= 1'b0;
            row1_mode     <= 2'd0;

            raw_valid     <= 1'b0;
            raw_family    <= 1'b0;
            raw_mode      <= 2'd0;
            stable_cnt    <= {STABLE_W{1'b0}};
            family_sel    <= 1'b0;
            mode_sel      <= 2'b11;
        end
        else if (scan_advance) begin
            if (!row0_found && row0_pressed) begin
                row0_found <= 1'b1;
                row0_mode  <= scan_idx;
            end
            if (!row1_found && row1_pressed) begin
                row1_found <= 1'b1;
                row1_mode  <= scan_idx;
            end

            if (scan_idx == 2'd3) begin
                scan_idx     <= 2'd0;
                kr_drive_low <= 4'b0001;
                row0_found   <= 1'b0;
                row0_mode    <= 2'd0;
                row1_found   <= 1'b0;
                row1_mode    <= 2'd0;

                if (scan_same_as_raw) begin
                    if (stable_cnt < DEBOUNCE_SCANS)
                        stable_cnt <= stable_cnt + {{(STABLE_W-1){1'b0}}, 1'b1};
                    else if (scan_valid_now) begin
                        family_sel <= scan_family_now;
                        mode_sel <= scan_mode_now;
                    end
                end
                else begin
                    raw_valid  <= scan_valid_now;
                    raw_family <= scan_family_now;
                    raw_mode   <= scan_mode_now;
                    stable_cnt <= {STABLE_W{1'b0}};
                end
            end
            else begin
                scan_idx     <= scan_idx + 2'd1;
                kr_drive_low <= (4'b0001 << (scan_idx + 2'd1));
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
