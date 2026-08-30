`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_network_upload_end_to_end.v
// 模块名       : tb_network_upload_end_to_end
// 功能简述     : 完整网络链路测试。由真实 RGMII 前导开始，覆盖 ARP、UDP4001、DACU 重传、COMMIT、ACK、上传播放与 16384 点索引 0 回传。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
// 网络上传整链自检：真实 100M RGMII RX -> ARP/UDP/IP/FCS -> DACU 协议 ->
// 双 bank 上传 -> ACK/ARP 异步 FIFO -> 三路仲裁，并验证提交后的音频样本。
module tb_network_upload_end_to_end;
    reg audio_clk = 1'b0;
    reg net_clk = 1'b0;
    reg net_txc_clk = 1'b0;
    reg mac_rxc = 1'b0;
    always #7  audio_clk = ~audio_clk;
    always #20 net_clk = ~net_clk;
    initial begin #2; forever #20 net_txc_clk = ~net_txc_clk; end
    always #20 mac_rxc = ~mac_rxc;

    reg net_rst_n = 1'b0;
    reg mac_rxctl = 1'b0;
    reg [3:0] mac_rxd = 4'd0;
    reg input_sample_ce = 1'b0;
    reg [31:0] monitor_sample_index = 32'h02D4_B9E1;
    reg        monitor_valid = 1'b0;
    wire signed [23:0] upload_sample;
    wire upload_sample_update;
    wire upload_source_active;
    wire upload_pipeline_reset_pulse;
    wire mac_txc, mac_txctl;
    wire [3:0] mac_txd;

    dac24_udp_network_top dut (
        .audio_clk(audio_clk), .monitor_sample(monitor_sample_index[23:0]),
        .monitor_valid(monitor_valid),
        .monitor_sample_index(monitor_sample_index),
        .monitor_mode(2'd0), .monitor_family_48k(1'b0),
        .net_clk_25m(net_clk), .net_txc_clk_25m(net_txc_clk),
        .net_rst_n(net_rst_n), .mac_rxc(mac_rxc),
        .mac_rxctl(mac_rxctl), .mac_rxd(mac_rxd),
        .upload_sample(upload_sample),
        .upload_sample_update(upload_sample_update),
        .upload_source_active(upload_source_active),
        .upload_pipeline_reset_pulse(upload_pipeline_reset_pulse),
        .upload_family_48k(),
        .upload_mode(), .upload_transaction_id(),
        .input_sample_ce(input_sample_ce),
        .mac_txc(mac_txc), .mac_txctl(mac_txctl), .mac_txd(mac_txd)
    );

    reg [7:0] app [0:1023];
    reg [7:0] frame [0:2047];
    reg [7:0] captured [0:1023];
    integer frame_start_offset [0:7];
    integer captured_frame_length [0:7];
    integer app_length;
    integer frame_length;
    integer captured_count = 0;
    integer captured_frame_count = 0;
    integer current_frame_start = 0;
    reg capture_in_frame = 1'b0;
    integer played_count = 0;
    reg signed [23:0] played [0:3];
    integer i;
    reg [31:0] crc;
    reg [31:0] fcs;
    integer ip_sum;

    // 模拟 common 输出 epoch：COMMIT 前索引已经很大；复位脉冲到达后，
    // 下一拍清零，随后新上传源的首个有效输出索引为 0。
    always @(posedge audio_clk) begin
        if (!net_rst_n) begin
            monitor_sample_index <= 32'h02D4_B9E1;
            monitor_valid <= 1'b1;
        end else if (upload_pipeline_reset_pulse) begin
            monitor_sample_index <= 32'd0;
            monitor_valid <= 1'b0;
        end else begin
            monitor_valid <= 1'b1;
            if (monitor_valid)
                monitor_sample_index <= monitor_sample_index + 32'd1;
        end
    end

    function [31:0] crc_byte;
        input [31:0] crc_in;
        input [7:0] data_in;
        integer bit_index;
        reg [31:0] c;
        begin
            c = crc_in ^ {24'd0, data_in};
            for (bit_index=0; bit_index<8; bit_index=bit_index+1)
                c = c[0] ? ((c>>1)^32'hEDB8_8320) : (c>>1);
            crc_byte = c;
        end
    endfunction

    task put_u32_le;
        input integer base;
        input [31:0] value;
        begin
            app[base+0]=value[7:0]; app[base+1]=value[15:8];
            app[base+2]=value[23:16]; app[base+3]=value[31:24];
        end
    endtask

    task finish_app_header;
        input [7:0] message_type;
        input [7:0] flags;
        input [31:0] transaction_id;
        input [31:0] sequence;
        input [31:0] total_samples;
        input [31:0] sample_offset;
        input [15:0] sample_count;
        input integer body_bytes;
        integer n;
        begin
            app[0]=8'h44; app[1]=8'h41; app[2]=8'h43; app[3]=8'h55;
            app[4]=8'h01; app[5]=message_type; app[6]=flags; app[7]=8'h20;
            put_u32_le(8,transaction_id); put_u32_le(12,sequence);
            put_u32_le(16,total_samples); put_u32_le(20,sample_offset);
            app[24]=sample_count[7:0]; app[25]=sample_count[15:8];
            app[26]=8'h18; app[27]=8'h01;
            crc=32'hFFFF_FFFF;
            for(n=0;n<body_bytes;n=n+1) crc=crc_byte(crc,app[32+n]);
            crc=~crc;
            app[28]=crc[7:0]; app[29]=crc[15:8];
            app[30]=crc[23:16]; app[31]=crc[31:24];
            app_length=32+body_bytes;
        end
    endtask

    task build_begin;
        begin
            app[32]=8'h01; // BEGIN
            app[33]=8'h00; // 44.1 kHz
            app[34]=8'h00; // 1x
            app[35]=8'h01; // upload RAM
            app[36]=8'h01; app[37]=0; app[38]=0; app[39]=0;
            finish_app_header(8'h01,8'h01,32'h1234_5678,0,2,0,0,8);
        end
    endtask

    task build_wave;
        begin
            app[32]=8'h01; app[33]=8'h00; app[34]=8'h00;
            app[35]=8'hFF; app[36]=8'hFF; app[37]=8'hFF;
            finish_app_header(8'h02,8'h01,32'h1234_5678,0,2,0,2,6);
        end
    endtask

    task build_commit;
        begin
            // ACK_REQUIRED | RESET_PIPELINE | ONE_SHOT。
            finish_app_header(8'h03,8'h0D,32'h1234_5678,1,2,2,0,0);
        end
    endtask

    task build_udp_frame;
        integer n;
        integer ip_total_length;
        integer udp_length;
        begin
            ip_total_length=20+8+app_length;
            udp_length=8+app_length;
            frame_length=14+ip_total_length+4;
            for(n=0;n<frame_length;n=n+1) frame[n]=0;
            frame[0]=8'h02;frame[1]=8'h35;frame[2]=8'h24;
            frame[3]=0;frame[4]=0;frame[5]=1;
            frame[6]=8'h10;frame[7]=8'h20;frame[8]=8'h30;
            frame[9]=8'h40;frame[10]=8'h50;frame[11]=8'h60;
            frame[12]=8'h08;frame[13]=8'h00;
            frame[14]=8'h45;frame[15]=0;
            frame[16]=ip_total_length>>8;frame[17]=ip_total_length;
            frame[18]=8'h12;frame[19]=8'h34;
            frame[20]=8'h40;frame[21]=0;frame[22]=8'h40;frame[23]=8'h11;
            frame[24]=0;frame[25]=0;
            frame[26]=8'hC0;frame[27]=8'hA8;frame[28]=1;frame[29]=8'h14;
            frame[30]=8'hC0;frame[31]=8'hA8;frame[32]=1;frame[33]=8'h0A;
            ip_sum=0;
            for(n=14;n<34;n=n+2) begin
                ip_sum=ip_sum+{frame[n],frame[n+1]};
                ip_sum=(ip_sum&16'hFFFF)+(ip_sum>>16);
            end
            ip_sum=(ip_sum&16'hFFFF)+(ip_sum>>16);
            ip_sum=(~ip_sum)&16'hFFFF;
            frame[24]=ip_sum>>8;frame[25]=ip_sum;
            frame[34]=8'h13;frame[35]=8'h88; // PC port 5000
            frame[36]=8'h0F;frame[37]=8'hA1; // FPGA port 4001
            frame[38]=udp_length>>8;frame[39]=udp_length;
            frame[40]=0;frame[41]=0;
            for(n=0;n<app_length;n=n+1)frame[42+n]=app[n];
            crc=32'hFFFF_FFFF;
            for(n=0;n<frame_length-4;n=n+1)crc=crc_byte(crc,frame[n]);
            fcs=~crc;
            frame[frame_length-4]=fcs[7:0];frame[frame_length-3]=fcs[15:8];
            frame[frame_length-2]=fcs[23:16];frame[frame_length-1]=fcs[31:24];
        end
    endtask

    task build_arp_request;
        integer n;
        begin
            frame_length=64;
            for(n=0;n<frame_length;n=n+1)frame[n]=0;
            for(n=0;n<6;n=n+1)frame[n]=8'hFF;
            frame[6]=8'h10;frame[7]=8'h20;frame[8]=8'h30;
            frame[9]=8'h40;frame[10]=8'h50;frame[11]=8'h60;
            frame[12]=8'h08;frame[13]=8'h06;
            frame[14]=0;frame[15]=1;frame[16]=8'h08;frame[17]=0;
            frame[18]=6;frame[19]=4;frame[20]=0;frame[21]=1;
            frame[22]=8'h10;frame[23]=8'h20;frame[24]=8'h30;
            frame[25]=8'h40;frame[26]=8'h50;frame[27]=8'h60;
            frame[28]=8'hC0;frame[29]=8'hA8;frame[30]=1;frame[31]=8'h14;
            frame[38]=8'hC0;frame[39]=8'hA8;frame[40]=1;frame[41]=8'h0A;
            crc=32'hFFFF_FFFF;
            for(n=0;n<60;n=n+1)crc=crc_byte(crc,frame[n]);
            fcs=~crc;frame[60]=fcs[7:0];frame[61]=fcs[15:8];
            frame[62]=fcs[23:16];frame[63]=fcs[31:24];
        end
    endtask

    task send_symbol;
        input [3:0] nibble;
        input ctl;
        begin
            @(negedge mac_rxc);#1 mac_rxd=nibble;mac_rxctl=ctl;
            @(posedge mac_rxc);#1 mac_rxd=nibble;mac_rxctl=ctl;
        end
    endtask
    task send_byte;
        input [7:0] value;
        begin send_symbol(value[3:0],1'b1);send_symbol(value[7:4],1'b1);end
    endtask
    task send_frame;
        integer n;
        begin
            for(n=0;n<7;n=n+1)send_byte(8'h55);
            send_byte(8'hD5);
            for(n=0;n<frame_length;n=n+1)send_byte(frame[n]);
            send_symbol(0,0);repeat(3)send_symbol(0,0);
        end
    endtask

    task wait_frames;
        input integer wanted;
        begin
            while (captured_frame_count < wanted)
                @(posedge net_clk);
            repeat(3)@(posedge net_clk);
        end
    endtask

    task check_ack;
        input integer frame_number;
        input [31:0] expected_sequence;
        input [31:0] expected_offset;
        integer s;
        begin
            s=frame_start_offset[frame_number];
            if(captured_frame_length[frame_number]!=86)
                $fatal(1,"ACK frame %0d 长度=%0d",frame_number,
                       captured_frame_length[frame_number]);
            if({captured[s+53],captured[s+52],captured[s+51],captured[s+50]}
               !==32'h5543_4144)
                $fatal(1,"ACK magic 错误");
            if({captured[s+65],captured[s+64],captured[s+63],captured[s+62]}
               !==expected_sequence)
                $fatal(1,"ACK sequence 错误");
            if({captured[s+69],captured[s+68],captured[s+67],captured[s+66]}
               !==32'd2)
                $fatal(1,"ACK total_samples 错误");
            if({captured[s+73],captured[s+72],captured[s+71],captured[s+70]}
               !==expected_offset)
                $fatal(1,"ACK next_offset 错误");
            if({captured[s+75],captured[s+74]}!==16'd0)
                $fatal(1,"ACK status 非零");
        end
    endtask

    task pulse_ce;
        begin
            @(negedge audio_clk);input_sample_ce=1'b1;
            @(negedge audio_clk);input_sample_ce=1'b0;
        end
    endtask

    always @(posedge net_clk) begin
        if(dut.tx_valid&&dut.tx_ready) begin
            if(!capture_in_frame) begin
                current_frame_start=captured_count;
                frame_start_offset[captured_frame_count]=captured_count;
                capture_in_frame=1'b1;
            end
            captured[captured_count]=dut.tx_data;
            captured_count=captured_count+1;
            if(dut.tx_last_unused) begin
                captured_frame_length[captured_frame_count]=
                    captured_count-current_frame_start;
                captured_frame_count=captured_frame_count+1;
                capture_in_frame=1'b0;
            end
        end
    end

    always @(negedge audio_clk)
        if(upload_sample_update) begin
            played[played_count]=upload_sample;
            played_count=played_count+1;
        end

    initial begin
        repeat(6)@(posedge net_clk);net_rst_n=1'b1;
        repeat(8)send_symbol(0,0);

        build_arp_request();send_frame();wait_frames(1);
        if(captured_frame_length[0]!=72 ||
           captured[8]!==8'h10 || captured[13]!==8'h60 ||
           captured[20]!==8'h08 || captured[21]!==8'h06 ||
           captured[28]!==8'h00 || captured[29]!==8'h02)
            $fatal(1,"ARP reply 字段错误");

        build_begin();build_udp_frame();send_frame();wait_frames(2);
        check_ack(1,0,0);

        build_wave();build_udp_frame();send_frame();wait_frames(3);
        check_ack(2,0,2);
        // ACK 丢失等价重发：不得推进两次。
        send_frame();wait_frames(4);check_ack(3,0,2);

        build_commit();build_udp_frame();send_frame();wait_frames(5);
        check_ack(4,1,2);
        // COMMIT 重发不得再次翻转播放 bank/event。
        send_frame();wait_frames(6);check_ack(5,1,2);

        wait(upload_source_active);repeat(8)@(posedge audio_clk);
        pulse_ce();pulse_ce();repeat(4)@(posedge audio_clk);
        if(played_count<2 || played[0]!==24'sd1 || played[1]!==-24'sd1)
            $fatal(1,"上传播放样本错误 count=%0d first=%0d second=%0d",
                   played_count,$signed(played[0]),$signed(played[1]));

        // 等一份完整的上传源采集帧，验证 COMMIT -> reset -> capture
        // 集成链的首帧描述符确实从输出索引 0 开始。
        wait(dut.u_capture.capture_full);
        if (dut.u_capture.done_start_sample_index !== 32'd0 ||
            !dut.u_capture.done_upload_source ||
            dut.u_capture.done_transaction_id !== 32'h1234_5678)
            $fatal(1,"uploaded capture descriptor error: start=%0d source=%0d txid=%h",
                   dut.u_capture.done_start_sample_index,
                   dut.u_capture.done_upload_source,
                   dut.u_capture.done_transaction_id);

        $display("NETWORK_UPLOAD_END_TO_END_PASS: uploaded capture starts at index zero");
        $finish;
    end

    initial begin #500000; $fatal(1,"网络上传整链仿真超时"); end
endmodule
