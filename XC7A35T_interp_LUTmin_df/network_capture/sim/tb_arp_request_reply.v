`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_arp_request_reply.v
// 模块名       : tb_arp_request_reply
// 功能简述     : ARP 请求解析与应答生成单元测试。覆盖合法请求、字段错误、FCS 错误及回复帧内容/FCS。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
module tb_arp_request_reply;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg [7:0] frame_data = 8'd0;
    reg frame_data_valid = 1'b0;
    reg frame_start = 1'b0;
    reg frame_end = 1'b0;
    reg frame_error = 1'b0;
    wire request_valid;
    wire request_ready;
    wire [47:0] requester_mac;
    wire [31:0] requester_ip;
    wire [7:0] tx_data;
    wire tx_valid;
    reg tx_ready = 1'b0;
    wire tx_last;

    reg [7:0] request_bytes [0:63];
    reg [7:0] reply_bytes [0:71];
    integer request_size;
    integer reply_count = 0;
    integer reply_frames = 0;
    integer cycle_count = 0;
    integer i;
    reg [31:0] crc;
    reg [31:0] fcs;

    arp_request_rx u_rx (
        .clk(clk), .rst_n(rst_n),
        .frame_data(frame_data), .frame_data_valid(frame_data_valid),
        .frame_start(frame_start), .frame_end(frame_end),
        .frame_error(frame_error),
        .request_valid(request_valid), .request_ready(request_ready),
        .requester_mac(requester_mac), .requester_ip(requester_ip)
    );

    arp_reply_tx u_tx (
        .clk(clk), .rst_n(rst_n),
        .request_valid(request_valid), .request_ready(request_ready),
        .requester_mac(requester_mac), .requester_ip(requester_ip),
        .tx_data(tx_data), .tx_valid(tx_valid),
        .tx_ready(tx_ready), .tx_last(tx_last)
    );

    function [31:0] crc_byte;
        input [31:0] crc_in;
        input [7:0] data_in;
        integer bit_index;
        reg [31:0] c;
        begin
            c = crc_in ^ {24'd0, data_in};
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                c = c[0] ? ((c >> 1) ^ 32'hEDB8_8320) : (c >> 1);
            crc_byte = c;
        end
    endfunction

    task build_request;
        input [31:0] target_ip;
        input corrupt_fcs;
        integer n;
        begin
            request_size = 64;
            for (n = 0; n < request_size; n = n + 1)
                request_bytes[n] = 8'h00;

            // Ethernet II：广播目的，PC MAC 10:20:30:40:50:60，ARP。
            for (n = 0; n < 6; n = n + 1)
                request_bytes[n] = 8'hFF;
            request_bytes[6]=8'h10; request_bytes[7]=8'h20;
            request_bytes[8]=8'h30; request_bytes[9]=8'h40;
            request_bytes[10]=8'h50; request_bytes[11]=8'h60;
            request_bytes[12]=8'h08; request_bytes[13]=8'h06;

            request_bytes[14]=8'h00; request_bytes[15]=8'h01;
            request_bytes[16]=8'h08; request_bytes[17]=8'h00;
            request_bytes[18]=8'h06; request_bytes[19]=8'h04;
            request_bytes[20]=8'h00; request_bytes[21]=8'h01;
            request_bytes[22]=8'h10; request_bytes[23]=8'h20;
            request_bytes[24]=8'h30; request_bytes[25]=8'h40;
            request_bytes[26]=8'h50; request_bytes[27]=8'h60;
            request_bytes[28]=8'hC0; request_bytes[29]=8'hA8;
            request_bytes[30]=8'h01; request_bytes[31]=8'h14;
            // target MAC 32..37 = 0。
            request_bytes[38]=target_ip[31:24];
            request_bytes[39]=target_ip[23:16];
            request_bytes[40]=target_ip[15:8];
            request_bytes[41]=target_ip[7:0];
            // 42..59 为 Ethernet 最小帧填充。

            crc = 32'hFFFF_FFFF;
            for (n = 0; n < request_size-4; n = n + 1)
                crc = crc_byte(crc, request_bytes[n]);
            fcs = ~crc;
            if (corrupt_fcs)
                fcs = fcs ^ 32'h0000_0001;
            request_bytes[60]=fcs[7:0]; request_bytes[61]=fcs[15:8];
            request_bytes[62]=fcs[23:16]; request_bytes[63]=fcs[31:24];
        end
    endtask

    task send_request;
        integer n;
        begin
            @(negedge clk);
            for (n = 0; n < request_size; n = n + 1) begin
                frame_data = request_bytes[n];
                frame_data_valid = 1'b1;
                frame_start = (n == 0);
                frame_end = (n == request_size-1);
                @(negedge clk);
            end
            frame_data_valid = 1'b0;
            frame_start = 1'b0;
            frame_end = 1'b0;
        end
    endtask

    task expect_reply_byte;
        input integer index;
        input [7:0] expected;
        begin
            if (reply_bytes[index] !== expected)
                $fatal(1, "ARP reply 字节 %0d 错误：%02x != %02x",
                       index, reply_bytes[index], expected);
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 0;
            tx_ready <= 1'b0;
        end else begin
            cycle_count <= cycle_count + 1;
            tx_ready <= ((cycle_count % 5) != 2);
        end

        if (tx_valid && tx_ready) begin
            if (reply_count > 71)
                $fatal(1, "ARP reply 超过 72 字节");
            reply_bytes[reply_count] = tx_data;
            reply_count = reply_count + 1;
            if (tx_last) begin
                if (reply_count != 72)
                    $fatal(1, "ARP reply 长度错误：%0d", reply_count);
                reply_frames = reply_frames + 1;
            end
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // 错目标 IP、坏 FCS 都不得应答。
        build_request(32'hC0A8_010B, 1'b0);
        send_request(); repeat (10) @(posedge clk);
        if (reply_frames != 0) $fatal(1, "错误目标 IP 被应答");

        build_request(32'hC0A8_010A, 1'b1);
        send_request(); repeat (10) @(posedge clk);
        if (reply_frames != 0) $fatal(1, "错误 FCS 被应答");

        build_request(32'hC0A8_010A, 1'b0);
        send_request();
        wait (reply_frames == 1);
        repeat (3) @(posedge clk);

        for (i = 0; i < 7; i = i + 1) expect_reply_byte(i, 8'h55);
        expect_reply_byte(7, 8'hD5);
        expect_reply_byte(8,8'h10); expect_reply_byte(9,8'h20);
        expect_reply_byte(10,8'h30); expect_reply_byte(11,8'h40);
        expect_reply_byte(12,8'h50); expect_reply_byte(13,8'h60);
        expect_reply_byte(14,8'h02); expect_reply_byte(15,8'h35);
        expect_reply_byte(16,8'h24); expect_reply_byte(17,8'h00);
        expect_reply_byte(18,8'h00); expect_reply_byte(19,8'h01);
        expect_reply_byte(20,8'h08); expect_reply_byte(21,8'h06);
        expect_reply_byte(22,8'h00); expect_reply_byte(23,8'h01);
        expect_reply_byte(24,8'h08); expect_reply_byte(25,8'h00);
        expect_reply_byte(26,8'h06); expect_reply_byte(27,8'h04);
        expect_reply_byte(28,8'h00); expect_reply_byte(29,8'h02);
        expect_reply_byte(30,8'h02); expect_reply_byte(31,8'h35);
        expect_reply_byte(32,8'h24); expect_reply_byte(33,8'h00);
        expect_reply_byte(34,8'h00); expect_reply_byte(35,8'h01);
        expect_reply_byte(36,8'hC0); expect_reply_byte(37,8'hA8);
        expect_reply_byte(38,8'h01); expect_reply_byte(39,8'h0A);
        expect_reply_byte(40,8'h10); expect_reply_byte(41,8'h20);
        expect_reply_byte(42,8'h30); expect_reply_byte(43,8'h40);
        expect_reply_byte(44,8'h50); expect_reply_byte(45,8'h60);
        expect_reply_byte(46,8'hC0); expect_reply_byte(47,8'hA8);
        expect_reply_byte(48,8'h01); expect_reply_byte(49,8'h14);
        for (i = 50; i < 68; i = i + 1) expect_reply_byte(i, 8'h00);

        crc = 32'hFFFF_FFFF;
        for (i = 8; i < 68; i = i + 1)
            crc = crc_byte(crc, reply_bytes[i]);
        fcs = ~crc;
        if ({reply_bytes[71],reply_bytes[70],reply_bytes[69],reply_bytes[68]} !== fcs)
            $fatal(1, "ARP reply FCS 错误");

        $display("ARP_REQUEST_REPLY_PASS");
        $finish;
    end

    initial begin
        #50000;
        $fatal(1, "ARP request/reply 仿真超时");
    end
endmodule
