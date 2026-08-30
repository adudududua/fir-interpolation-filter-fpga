`timescale 1ns / 1ps

//=============================================================
// 文件名       : matrix_keypad_mode_ctrl_ultracompact.v
// 模块名       : matrix_keypad_mode_ctrl_ultracompact
// 功能简述     : 全国赛板卡四列、两行有效按键的超紧凑扫描器。
//                扫描过程中把按键编码为 {valid,family,mode}，其中
//                family 选择 44.1/48 kHz，mode 选择 1x/4x/8x/128x。
//
//                同一轮扫描若先发现 SW5～SW8、后发现 SW1～SW4，
//                行 0 结果会覆盖行 1，以保持原板卡 SW1～SW4 的
//                优先级；同一行只保留最先扫描到的列。模块还包含
//                两级输入同步和按整轮扫描计数的消抖逻辑。
//
// 当前默认配置：
//                  SCAN_DIV=20000
//                  DEBOUNCE_SCANS=5
//                  支持上层提供共享 scan_tick
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-18
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-18：合并双行扫描状态，形成优先级编码。
//                2026-08-16：完善中文接口、消抖和优先级说明。
//=============================================================

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

    wire [STABLE_W-1:0] stable_next;
    wire stable_done;

    wire row0_pressed = ~kc_sync[0];
    wire row1_pressed = ~kc_sync[1];
    wire scan_advance = (USE_EXTERNAL_SCAN_TICK != 0) ? scan_tick :
                        (scan_cnt == SCAN_DIV - 1);

    // 签核配置DEBOUNCE_SCANS=5要求连续6轮完整扫描结果一致才提交按键。
    // 3位Johnson序列000→001→011→111→110→100无需3位加法器即可到终点；
    // 若使用其它参数值，则自动保留通用二进制计数器分支。
    generate
        if (DEBOUNCE_SCANS == 5) begin : gen_johnson_debounce
            assign stable_next = {stable_cnt[1:0], ~stable_cnt[2]};
            assign stable_done = (stable_cnt == 3'b100);
        end
        else begin : gen_generic_debounce
            assign stable_next = stable_cnt +
                {{(STABLE_W-1){1'b0}}, 1'b1};
            assign stable_done = (stable_cnt >= DEBOUNCE_SCANS);
        end
    endgenerate

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
                    if (!stable_done)
                        stable_cnt <= stable_next;
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
