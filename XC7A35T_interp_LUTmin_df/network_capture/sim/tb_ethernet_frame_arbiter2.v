`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_ethernet_frame_arbiter2.v
// 模块名       : tb_ethernet_frame_arbiter2
// 功能简述     : 两路帧仲裁器测试。验证高优先级选择、帧内锁定和下游反压。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
module tb_ethernet_frame_arbiter2;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg ack_enable = 1'b0;
    reg [2:0] s0_index = 3'd0;
    reg [2:0] s1_index = 3'd0;
    wire [7:0] s0_data = 8'hB0 + s0_index;
    wire s0_valid = ack_enable && (s0_index < 2);
    wire s0_last = (s0_index == 1);
    wire s0_ready;
    wire [7:0] s1_data = 8'hA0 + s1_index;
    wire s1_valid = (s1_index < 4);
    wire s1_last = (s1_index == 3);
    wire s1_ready;

    wire [7:0] m_data;
    wire m_valid;
    reg m_ready = 1'b0;
    wire m_last;
    reg [7:0] captured [0:5];
    integer captured_count = 0;
    integer cycle_count = 0;

    ethernet_frame_arbiter2 dut (
        .clk(clk), .rst_n(rst_n),
        .s0_data(s0_data), .s0_valid(s0_valid), .s0_ready(s0_ready), .s0_last(s0_last),
        .s1_data(s1_data), .s1_valid(s1_valid), .s1_ready(s1_ready), .s1_last(s1_last),
        .m_data(m_data), .m_valid(m_valid), .m_ready(m_ready), .m_last(m_last)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            m_ready <= 1'b0;
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            m_ready <= ((cycle_count % 4) != 1);
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (s1_valid && s1_ready) begin
                s1_index <= s1_index + 1'b1;
                // 音频帧的第一个字节已经接收后才让 ACK 到达，验证不能中途抢占。
                if (s1_index == 0)
                    ack_enable <= 1'b1;
            end
            if (s0_valid && s0_ready)
                s0_index <= s0_index + 1'b1;
            if (m_valid && m_ready) begin
                captured[captured_count] <= m_data;
                captured_count <= captured_count + 1;
            end
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        wait(captured_count == 6);
        repeat (2) @(posedge clk);
        if (captured[0] !== 8'hA0 || captured[1] !== 8'hA1 ||
            captured[2] !== 8'hA2 || captured[3] !== 8'hA3 ||
            captured[4] !== 8'hB0 || captured[5] !== 8'hB1)
            $fatal(1, "仲裁输出次序错误：%02x %02x %02x %02x %02x %02x",
                   captured[0], captured[1], captured[2], captured[3],
                   captured[4], captured[5]);
        if (s0_index != 2 || s1_index != 4)
            $fatal(1, "输入握手计数错误");
        $display("通过：ACK 优先等待，但没有打断正在发送的音频帧");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "仲裁器仿真超时");
    end
endmodule
