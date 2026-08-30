`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_arp_rgmii_loop.v
// 模块名       : tb_arp_rgmii_loop
// 功能简述     : 真实 100M RGMII 半字节输入到 ARP 回复字节流的链路测试，覆盖前导码、SFD、FCS 与请求/应答地址闭环。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
// 从 100M RGMII 引脚语义开始，覆盖前导码剥离、ARP/FCS 校验和 reply 生成。
module tb_arp_rgmii_loop;
    reg rx_clk = 1'b0;
    reg rst_n = 1'b0;
    reg [3:0] rgmii_rxd = 4'd0;
    reg rgmii_rxctl = 1'b0;
    always #20 rx_clk = ~rx_clk;

    wire [7:0] frame_data;
    wire frame_data_valid, frame_start, frame_end, frame_error;
    wire request_valid, request_ready;
    wire [47:0] requester_mac;
    wire [31:0] requester_ip;
    wire [7:0] tx_data;
    wire tx_valid, tx_last;

    reg [7:0] packet [0:63];
    integer i;
    integer reply_count = 0;
    reg [31:0] crc;
    reg [31:0] fcs;

    rgmii100_rx u_rgmii (
        .rx_clk(rx_clk), .rst_n(rst_n),
        .rgmii_rxd(rgmii_rxd), .rgmii_rxctl(rgmii_rxctl),
        .data(frame_data), .data_valid(frame_data_valid),
        .frame_start(frame_start), .frame_end(frame_end),
        .frame_error(frame_error)
    );
    arp_request_rx u_arp_rx (
        .clk(rx_clk), .rst_n(rst_n),
        .frame_data(frame_data), .frame_data_valid(frame_data_valid),
        .frame_start(frame_start), .frame_end(frame_end), .frame_error(frame_error),
        .request_valid(request_valid), .request_ready(request_ready),
        .requester_mac(requester_mac), .requester_ip(requester_ip)
    );
    arp_reply_tx u_arp_tx (
        .clk(rx_clk), .rst_n(rst_n),
        .request_valid(request_valid), .request_ready(request_ready),
        .requester_mac(requester_mac), .requester_ip(requester_ip),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_ready(1'b1), .tx_last(tx_last)
    );

    function [31:0] crc_byte;
        input [31:0] crc_in;
        input [7:0] data_in;
        integer k;
        reg [31:0] c;
        begin
            c = crc_in ^ {24'd0,data_in};
            for (k=0;k<8;k=k+1)
                c = c[0] ? ((c>>1)^32'hEDB8_8320) : (c>>1);
            crc_byte=c;
        end
    endfunction

    task send_symbol;
        input [3:0] nibble;
        input ctl;
        begin
            @(negedge rx_clk); #1 rgmii_rxd=nibble; rgmii_rxctl=ctl;
            @(posedge rx_clk); #1 rgmii_rxd=nibble; rgmii_rxctl=ctl;
        end
    endtask
    task send_byte;
        input [7:0] value;
        begin send_symbol(value[3:0],1'b1); send_symbol(value[7:4],1'b1); end
    endtask

    always @(posedge rx_clk)
        if (tx_valid) begin
            reply_count = reply_count + 1;
            if (tx_last && reply_count != 72)
                $fatal(1,"RGMII ARP loop reply 长度错误 %0d",reply_count);
        end

    initial begin
        for(i=0;i<64;i=i+1)packet[i]=0;
        for(i=0;i<6;i=i+1)packet[i]=8'hff;
        packet[6]=8'h10;packet[7]=8'h20;packet[8]=8'h30;
        packet[9]=8'h40;packet[10]=8'h50;packet[11]=8'h60;
        packet[12]=8'h08;packet[13]=8'h06;
        packet[14]=0;packet[15]=1;packet[16]=8'h08;packet[17]=0;
        packet[18]=6;packet[19]=4;packet[20]=0;packet[21]=1;
        packet[22]=8'h10;packet[23]=8'h20;packet[24]=8'h30;
        packet[25]=8'h40;packet[26]=8'h50;packet[27]=8'h60;
        packet[28]=8'hc0;packet[29]=8'ha8;packet[30]=1;packet[31]=8'h14;
        packet[38]=8'hc0;packet[39]=8'ha8;packet[40]=1;packet[41]=8'h0a;
        crc=32'hffff_ffff;
        for(i=0;i<60;i=i+1)crc=crc_byte(crc,packet[i]);
        fcs=~crc;packet[60]=fcs[7:0];packet[61]=fcs[15:8];
        packet[62]=fcs[23:16];packet[63]=fcs[31:24];

        repeat(4)@(negedge rx_clk);rst_n=1;
        repeat(3)send_symbol(0,0);
        for(i=0;i<7;i=i+1)send_byte(8'h55);
        send_byte(8'hd5);
        for(i=0;i<64;i=i+1)send_byte(packet[i]);
        send_symbol(0,0);
        wait(reply_count==72);
        repeat(3)@(posedge rx_clk);
        $display("ARP_RGMII_LOOP_PASS");
        $finish;
    end
    initial begin #100000; $fatal(1,"ARP RGMII loop timeout"); end
endmodule
