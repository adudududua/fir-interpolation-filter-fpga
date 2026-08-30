`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_udp_ipv4_rx_parser.v
// 模块名       : tb_udp_ipv4_rx_parser
// 功能简述     : Ethernet/IPv4/UDP parser 测试。覆盖连续合法帧、端口错误、IPv4 校验错误、截断、FCS 错误及末字节同拍结束。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
module tb_udp_ipv4_rx_parser;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg [7:0] frame_data = 8'd0;
    reg frame_data_valid = 1'b0;
    reg frame_start = 1'b0;
    reg frame_end = 1'b0;
    reg frame_error = 1'b0;
    wire [7:0] payload_data;
    wire payload_valid, payload_last, packet_valid, packet_drop;
    wire [15:0] payload_length;
    wire [31:0] source_ip;
    wire [15:0] source_port;

    udp_ipv4_rx_parser #(.MAX_PAYLOAD(64)) dut (
        .clk(clk), .rst_n(rst_n),
        .frame_data(frame_data), .frame_data_valid(frame_data_valid),
        .frame_start(frame_start), .frame_end(frame_end),
        .frame_error(frame_error),
        .payload_data(payload_data), .payload_valid(payload_valid),
        .payload_last(payload_last), .packet_valid(packet_valid),
        .packet_drop(packet_drop), .payload_length(payload_length),
        .source_ip(source_ip), .source_port(source_port)
    );

    reg [7:0] packet [0:255];
    integer payload_size;
    integer packet_size;
    integer observed_payload;
    integer replay_byte_index;
    integer valid_count;
    integer drop_count;
    integer test_errors;
    integer i;
    reg [31:0] crc;
    reg [15:0] ip_sum;

    function [31:0] crc_byte;
        input [31:0] crc_in;
        input [7:0] data_in;
        integer k;
        reg [31:0] c;
        begin
            c = crc_in ^ {24'd0, data_in};
            for (k = 0; k < 8; k = k + 1)
                c = c[0] ? ((c >> 1) ^ 32'hEDB88320) : (c >> 1);
            crc_byte = c;
        end
    endfunction

    task build_packet;
        input [15:0] destination_port;
        input integer body_len;
        integer n;
        reg [31:0] fcs;
        reg [17:0] sum_ext;
        reg [15:0] checksum;
        begin
            payload_size = body_len;
            packet_size = 14 + 20 + 8 + body_len + 4;
            for (n = 0; n < 256; n = n + 1) packet[n] = 8'd0;
            packet[0]=8'h02; packet[1]=8'h35; packet[2]=8'h24;
            packet[3]=8'h00; packet[4]=8'h00; packet[5]=8'h01;
            packet[6]=8'h10; packet[7]=8'h20; packet[8]=8'h30;
            packet[9]=8'h40; packet[10]=8'h50; packet[11]=8'h60;
            packet[12]=8'h08; packet[13]=8'h00;
            packet[14]=8'h45; packet[15]=8'h00;
            packet[16]=(20+8+body_len)>>8; packet[17]=(20+8+body_len)&8'hff;
            packet[18]=8'h12; packet[19]=8'h34;
            packet[20]=8'h00; packet[21]=8'h00;
            packet[22]=8'h40; packet[23]=8'h11;
            packet[24]=8'h00; packet[25]=8'h00;
            packet[26]=8'hc0; packet[27]=8'ha8; packet[28]=8'h01; packet[29]=8'h14;
            packet[30]=8'hc0; packet[31]=8'ha8; packet[32]=8'h01; packet[33]=8'h0a;
            sum_ext = 18'd0;
            for (n = 14; n < 34; n = n + 2) begin
                sum_ext = sum_ext + {packet[n],packet[n+1]};
                sum_ext = {2'd0,sum_ext[15:0]} + sum_ext[17:16];
            end
            sum_ext = {2'd0,sum_ext[15:0]} + sum_ext[17:16];
            checksum = ~sum_ext[15:0];
            packet[24]=checksum[15:8]; packet[25]=checksum[7:0];
            packet[34]=8'h13; packet[35]=8'h88;
            packet[36]=destination_port[15:8]; packet[37]=destination_port[7:0];
            packet[38]=(8+body_len)>>8; packet[39]=(8+body_len)&8'hff;
            packet[40]=8'h00; packet[41]=8'h00;
            for (n = 0; n < body_len; n = n + 1) begin
                packet[42+n] = 8'h80 + n;
            end
            crc = 32'hffffffff;
            for (n = 0; n < packet_size-4; n = n + 1)
                crc = crc_byte(crc,packet[n]);
            fcs = ~crc;
            packet[packet_size-4]=fcs[7:0];
            packet[packet_size-3]=fcs[15:8];
            packet[packet_size-2]=fcs[23:16];
            packet[packet_size-1]=fcs[31:24];
        end
    endtask

    task send_packet;
        input integer bytes_to_send;
        integer n;
        begin
            @(negedge clk);
            for (n = 0; n < bytes_to_send; n = n + 1) begin
                frame_data = packet[n]; frame_data_valid = 1'b1;
                frame_start = (n == 0);
                @(negedge clk);
            end
            frame_data_valid = 1'b0; frame_start = 1'b0; frame_end = 1'b1;
            @(negedge clk); frame_end = 1'b0;
        end
    endtask

    // 覆盖下层把 frame_end 与最后一个 FCS 字节同周期给出的合法接口时序。
    task send_packet_end_on_last_byte;
        input integer bytes_to_send;
        integer n;
        begin
            @(negedge clk);
            for (n = 0; n < bytes_to_send; n = n + 1) begin
                frame_data = packet[n]; frame_data_valid = 1'b1;
                frame_start = (n == 0); frame_end = (n == bytes_to_send-1);
                @(negedge clk);
            end
            frame_data_valid = 1'b0; frame_start = 1'b0; frame_end = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        if (payload_valid) begin
            observed_payload = observed_payload + 1;
            if (payload_data !== (8'h80 + replay_byte_index)) begin
                $display("PAYLOAD_DATA_FAILED index=%0d got=%02x expected=%02x",
                         replay_byte_index, payload_data,
                         (8'h80 + replay_byte_index));
                test_errors = test_errors + 1;
            end
            if (payload_last !== (replay_byte_index == payload_length-1)) begin
                $display("PAYLOAD_LAST_FAILED index=%0d len=%0d last=%0b",
                         replay_byte_index, payload_length, payload_last);
                test_errors = test_errors + 1;
            end
            replay_byte_index = replay_byte_index + 1;
        end
        if (packet_valid) begin
            valid_count = valid_count + 1;
            replay_byte_index = 0;
        end
        if (packet_drop) begin
            drop_count = drop_count + 1;
        end
    end

    initial begin
        test_errors=0; valid_count=0; drop_count=0; observed_payload=0;
        replay_byte_index=0;
        repeat(4) @(negedge clk); rst_n=1'b1;

        build_packet(16'd4001,12); send_packet(packet_size);
        repeat(20) @(negedge clk);
        if(valid_count!=1 || drop_count!=0 || observed_payload!=12 ||
           payload_length!=12 || source_ip!=32'hc0a80114 || source_port!=16'd5000) begin
            $display("LEGAL_FRAME_FAILED valid=%0d drop=%0d payload=%0d len=%0d",
                     valid_count,drop_count,observed_payload,payload_length);
            test_errors=test_errors+1;
        end

        // 前一包回放期间立即接收下一包，验证两个载荷 bank 不互相覆盖。
        build_packet(16'd4001,16); send_packet(packet_size);
        build_packet(16'd4001,5); send_packet(packet_size);
        repeat(25) @(negedge clk);
        if(valid_count!=3 || drop_count!=0 || observed_payload!=33) begin
            $display("BACK_TO_BACK_FAILED valid=%0d drop=%0d payload=%0d",
                     valid_count,drop_count,observed_payload);
            test_errors=test_errors+1;
        end

        build_packet(16'd4001,9); send_packet_end_on_last_byte(packet_size);
        repeat(15) @(negedge clk);
        if(valid_count!=4 || drop_count!=0 || observed_payload!=42) begin
            $display("SAME_CYCLE_END_FAILED valid=%0d drop=%0d payload=%0d",
                     valid_count,drop_count,observed_payload);
            test_errors=test_errors+1;
        end

        build_packet(16'd4999,6); send_packet(packet_size); repeat(5) @(negedge clk);
        if(valid_count!=4 || drop_count!=1) begin
            $display("WRONG_PORT_FAILED valid=%0d drop=%0d",valid_count,drop_count);
            test_errors=test_errors+1;
        end

        build_packet(16'd4001,8); packet[packet_size-1]=packet[packet_size-1]^8'h01;
        send_packet(packet_size); repeat(5) @(negedge clk);
        if(valid_count!=4 || drop_count!=2) begin
            $display("BAD_FCS_FAILED valid=%0d drop=%0d",valid_count,drop_count);
            test_errors=test_errors+1;
        end

        build_packet(16'd4001,10); send_packet(packet_size-3); repeat(5) @(negedge clk);
        if(valid_count!=4 || drop_count!=3) begin
            $display("TRUNCATION_FAILED valid=%0d drop=%0d",valid_count,drop_count);
            test_errors=test_errors+1;
        end

        build_packet(16'd4001,7); packet[24]=packet[24]^8'h01;
        crc=32'hffffffff;
        for(i=0;i<packet_size-4;i=i+1)crc=crc_byte(crc,packet[i]);
        crc=~crc;
        packet[packet_size-4]=crc[7:0];packet[packet_size-3]=crc[15:8];
        packet[packet_size-2]=crc[23:16];packet[packet_size-1]=crc[31:24];
        send_packet(packet_size);repeat(5)@(negedge clk);
        if(valid_count!=4||drop_count!=4)begin
            $display("BAD_IP_CHECKSUM_FAILED valid=%0d drop=%0d",valid_count,drop_count);
            test_errors=test_errors+1;
        end

        if(test_errors==0) $display("UDP_IPV4_RX_PARSER_PASS");
        else $fatal(1,"UDP_IPV4_RX_PARSER_FAILED errors=%0d",test_errors);
        $finish;
    end
endmodule
