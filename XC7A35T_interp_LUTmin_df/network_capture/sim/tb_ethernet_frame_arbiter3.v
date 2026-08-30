`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_ethernet_frame_arbiter3.v
// 模块名       : tb_ethernet_frame_arbiter3
// 功能简述     : 三路帧仲裁与 IFG 测试。验证 ARP>ACK>音频优先级、帧不被打断以及帧间隔。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
module tb_ethernet_frame_arbiter3;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg s0_enable = 1'b0;
    reg s1_enable = 1'b0;
    reg s2_enable = 1'b0;
    reg [2:0] s0_index = 0;
    reg [2:0] s1_index = 0;
    reg [2:0] s2_index = 0;
    wire [7:0] s0_data = 8'hC0 + s0_index;
    wire [7:0] s1_data = 8'hB0 + s1_index;
    wire [7:0] s2_data = 8'hA0 + s2_index;
    wire s0_valid = s0_enable && (s0_index < 2);
    wire s1_valid = s1_enable && (s1_index < 2);
    wire s2_valid = s2_enable && (s2_index < 3);
    wire s0_last = (s0_index == 1);
    wire s1_last = (s1_index == 1);
    wire s2_last = (s2_index == 2);
    wire s0_ready, s1_ready, s2_ready;
    wire [7:0] m_data;
    wire m_valid, m_last;
    reg m_ready = 1'b0;

    reg [7:0] captured [0:6];
    integer captured_count = 0;
    integer cycle_count = 0;
    integer last_transfer_cycle = -1000;
    integer frame_count = 0;

    ethernet_frame_arbiter3 #(.IFG_CYCLES(4)) dut (
        .clk(clk), .rst_n(rst_n),
        .s0_data(s0_data), .s0_valid(s0_valid),
        .s0_ready(s0_ready), .s0_last(s0_last),
        .s1_data(s1_data), .s1_valid(s1_valid),
        .s1_ready(s1_ready), .s1_last(s1_last),
        .s2_data(s2_data), .s2_valid(s2_valid),
        .s2_ready(s2_ready), .s2_last(s2_last),
        .m_data(m_data), .m_valid(m_valid), .m_ready(m_ready), .m_last(m_last)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (s0_valid && s0_ready) s0_index <= s0_index + 1'b1;
            if (s1_valid && s1_ready) s1_index <= s1_index + 1'b1;
            if (s2_valid && s2_ready) s2_index <= s2_index + 1'b1;
            if (m_valid && m_ready) begin
                captured[captured_count] = m_data;
                captured_count = captured_count + 1;
                if ((captured_count == 3 || captured_count == 5) &&
                    (cycle_count - last_transfer_cycle) < 5)
                    $fatal(1, "IFG 不足：相邻帧最后/最初字节仅间隔 %0d 周期",
                           cycle_count-last_transfer_cycle);
                if (m_last) begin
                    last_transfer_cycle = cycle_count;
                    frame_count = frame_count + 1;
                end
            end
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // 低优先级音频先出现；下游停顿时 ACK/ARP 随后到达。仲裁器必须
        // 已锁定音频，不能让首字节从 A0 变成 C0。
        @(negedge clk); s2_enable = 1'b1; m_ready = 1'b0;
        @(posedge clk); #1;
        if (!m_valid || m_data !== 8'hA0)
            $fatal(1, "未在 valid 出现时选择音频首字节");
        @(negedge clk); s0_enable = 1'b1; s1_enable = 1'b1;
        @(posedge clk); #1;
        if (!m_valid || m_data !== 8'hA0)
            $fatal(1, "首字节停顿时被高优先级输入替换");
        @(negedge clk); m_ready = 1'b1;

        wait (captured_count == 7);
        repeat (3) @(posedge clk);
        if (captured[0]!==8'hA0 || captured[1]!==8'hA1 || captured[2]!==8'hA2 ||
            captured[3]!==8'hC0 || captured[4]!==8'hC1 ||
            captured[5]!==8'hB0 || captured[6]!==8'hB1)
            $fatal(1, "仲裁次序错误");
        if (frame_count != 3)
            $fatal(1, "帧计数错误：%0d", frame_count);
        $display("ETHERNET_FRAME_ARBITER3_PASS");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "三路仲裁器仿真超时");
    end
endmodule
