`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_udp_control_ack_tx.v
// 模块名       : tb_udp_control_ack_tx
// 功能简述     : 控制 ACK 帧测试。核对事务字段、动态目标 IP/端口、IPv4 校验和、反压及 Ethernet FCS。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
module tb_udp_control_ack_tx;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg event_valid = 1'b0;
    wire event_ready;
    wire [7:0] tx_data;
    wire tx_valid;
    reg tx_ready = 1'b0;
    wire tx_last;

    reg [7:0] captured [0:85];
    integer captured_count = 0;
    integer cycle_count = 0;
    integer i;
    integer sum;
    reg [31:0] crc;
    reg [31:0] received_fcs;

    udp_control_ack_tx dut (
        .clk(clk),
        .rst_n(rst_n),
        .event_valid(event_valid),
        .event_ready(event_ready),
        .status_code(16'h0005),
        .transaction_id(32'h1234_5678),
        .sequence(32'h89AB_CDEF),
        .total_samples(32'h0000_4000),
        .next_offset(32'h0102_0304),
        .dest_ip(32'hC0A8_0114),
        .dest_port(16'd54321),
        .tx_data(tx_data),
        .tx_valid(tx_valid),
        .tx_ready(tx_ready),
        .tx_last(tx_last)
    );

    // 在发送期间插入可重复的反压，验证 ready/valid 下字节不会跳变或丢失。
    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 0;
            tx_ready <= 1'b0;
        end else begin
            cycle_count <= cycle_count + 1;
            tx_ready <= ((cycle_count % 5) != 2);
        end
    end

    always @(posedge clk) begin
        if (tx_valid && tx_ready) begin
            if (captured_count > 85)
                $fatal(1, "ACK 帧长度超过预期");
            captured[captured_count] = tx_data;
            captured_count = captured_count + 1;
            if (tx_last && captured_count != 86)
                $fatal(1, "tx_last 所在位置错误：%0d", captured_count);
        end
    end

    function [31:0] crc32_byte;
        input [31:0] crc_in;
        input [7:0] data_in;
        integer bit_index;
        reg [31:0] c;
        begin
            c = crc_in ^ {24'd0, data_in};
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                c = c[0] ? ((c >> 1) ^ 32'hEDB8_8320) : (c >> 1);
            crc32_byte = c;
        end
    endfunction

    task expect_byte;
        input integer index;
        input [7:0] expected;
        begin
            if (captured[index] !== expected)
                $fatal(1, "字节 %0d 错误：实测 %02x，预期 %02x",
                       index, captured[index], expected);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        if (!event_ready)
            $fatal(1, "复位释放后 event_ready 未置位");
        event_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        event_valid = 1'b0;

        wait(captured_count == 86);
        repeat (3) @(posedge clk);
        if (!event_ready)
            $fatal(1, "ACK 完成后 event_ready 未恢复");

        for (i = 0; i < 7; i = i + 1)
            expect_byte(i, 8'h55);
        expect_byte(7, 8'hD5);
        for (i = 8; i < 14; i = i + 1)
            expect_byte(i, 8'hFF);
        expect_byte(14, 8'h02);
        expect_byte(15, 8'h35);
        expect_byte(16, 8'h24);
        expect_byte(17, 8'h00);
        expect_byte(18, 8'h00);
        expect_byte(19, 8'h01);
        expect_byte(20, 8'h08);
        expect_byte(21, 8'h00);

        expect_byte(22, 8'h45);
        expect_byte(24, 8'h00);
        expect_byte(25, 8'h3C);
        expect_byte(28, 8'h40);
        expect_byte(29, 8'h00);
        expect_byte(30, 8'h40);
        expect_byte(31, 8'h11);
        expect_byte(34, 8'hC0);
        expect_byte(35, 8'hA8);
        expect_byte(36, 8'h01);
        expect_byte(37, 8'h0A);
        expect_byte(38, 8'hC0);
        expect_byte(39, 8'hA8);
        expect_byte(40, 8'h01);
        expect_byte(41, 8'h14);

        // 含头校验和字段的十个 16 位字做一补求和，结果必须为 0xFFFF。
        sum = 0;
        for (i = 22; i < 42; i = i + 2) begin
            sum = sum + {captured[i], captured[i+1]};
            sum = (sum & 16'hFFFF) + (sum >> 16);
        end
        sum = (sum & 16'hFFFF) + (sum >> 16);
        if ((sum & 16'hFFFF) != 16'hFFFF)
            $fatal(1, "IPv4 头校验和错误：折叠和=%04x", sum & 16'hFFFF);

        expect_byte(42, 8'h0F);
        expect_byte(43, 8'hA1); // 源端口 4001
        expect_byte(44, 8'hD4);
        expect_byte(45, 8'h31); // 目的端口 54321
        expect_byte(46, 8'h00);
        expect_byte(47, 8'h28);
        expect_byte(48, 8'h00);
        expect_byte(49, 8'h00);

        expect_byte(50, 8'h44);
        expect_byte(51, 8'h41);
        expect_byte(52, 8'h43);
        expect_byte(53, 8'h55);
        expect_byte(54, 8'h01);
        expect_byte(55, 8'h81);
        expect_byte(56, 8'h00);
        expect_byte(57, 8'h20);
        expect_byte(58, 8'h78);
        expect_byte(59, 8'h56);
        expect_byte(60, 8'h34);
        expect_byte(61, 8'h12);
        expect_byte(62, 8'hEF);
        expect_byte(63, 8'hCD);
        expect_byte(64, 8'hAB);
        expect_byte(65, 8'h89);
        expect_byte(66, 8'h00);
        expect_byte(67, 8'h40);
        expect_byte(68, 8'h00);
        expect_byte(69, 8'h00);
        expect_byte(70, 8'h04);
        expect_byte(71, 8'h03);
        expect_byte(72, 8'h02);
        expect_byte(73, 8'h01);
        expect_byte(74, 8'h05);
        expect_byte(75, 8'h00);
        expect_byte(76, 8'h18);
        expect_byte(77, 8'h01);
        for (i = 78; i < 82; i = i + 1)
            expect_byte(i, 8'h00);

        crc = 32'hFFFF_FFFF;
        for (i = 8; i < 82; i = i + 1)
            crc = crc32_byte(crc, captured[i]);
        received_fcs = {captured[85], captured[84], captured[83], captured[82]};
        if (received_fcs !== ~crc)
            $fatal(1, "Ethernet FCS 错误：实测 %08x，预期 %08x",
                   received_fcs, ~crc);

        repeat (8) @(posedge clk);
        if (captured_count != 86)
            $fatal(1, "单个事件被重复发送");
        $display("通过：DACU ACK 的字段、IPv4 校验和、反压和 Ethernet FCS 均正确");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "ACK 发送仿真超时");
    end
endmodule
