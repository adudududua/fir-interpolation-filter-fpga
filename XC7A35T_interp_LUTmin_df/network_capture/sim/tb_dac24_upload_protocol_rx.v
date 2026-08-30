`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_dac24_upload_protocol_rx.v
// 模块名       : tb_dac24_upload_protocol_rx
// 功能简述     : DACU 32 字节头与正文解析测试。覆盖 WAVE、CONTROL、COMMIT、CRC 错误及长度错误。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
module tb_dac24_upload_protocol_rx;
    reg clk=1'b0, rst_n=1'b0;
    always #5 clk=~clk;
    reg [7:0] payload_data=0;
    reg payload_valid=0, payload_last=0, packet_start=0;
    reg [15:0] packet_length=0;
    wire header_valid, packet_error, body_valid, body_last;
    wire [7:0] msg_type,flags,body_data;
    wire [31:0] transaction_id,sequence,total_samples,sample_offset,payload_crc32;
    wire [15:0] sample_count;
    reg [7:0] bytes[0:63];
    integer valid_count=0,error_count=0,body_count=0,test_errors=0,n;
    reg [31:0] crc;

    dac24_upload_protocol_rx dut(
        .clk(clk), .rst_n(rst_n),
        .payload_data(payload_data), .payload_valid(payload_valid),
        .payload_last(payload_last), .packet_start(packet_start),
        .packet_length(packet_length), .header_valid(header_valid),
        .packet_error(packet_error), .msg_type(msg_type), .flags(flags),
        .transaction_id(transaction_id), .sequence(sequence),
        .total_samples(total_samples), .sample_offset(sample_offset),
        .sample_count(sample_count), .payload_crc32(payload_crc32),
        .body_data(body_data), .body_valid(body_valid), .body_last(body_last)
    );

    function [31:0] crc_byte;
        input [31:0] crc_in; input [7:0] data_in;
        integer k; reg [31:0] c;
        begin
            c=crc_in^{24'd0,data_in};
            for(k=0;k<8;k=k+1)c=c[0]?((c>>1)^32'hEDB88320):(c>>1);
            crc_byte=c;
        end
    endfunction

    task build_wave;
        begin
            for(n=0;n<64;n=n+1)bytes[n]=0;
            bytes[0]="D";bytes[1]="A";bytes[2]="C";bytes[3]="U";
            bytes[4]=1;bytes[5]=8'h02;bytes[6]=1;bytes[7]=32;
            bytes[8]=8'h78;bytes[9]=8'h56;bytes[10]=8'h34;bytes[11]=8'h12;
            bytes[12]=3;bytes[16]=8'h00;bytes[17]=8'h10;
            bytes[20]=6;bytes[24]=2;bytes[26]=24;bytes[27]=1;
            bytes[32]=8'h01;bytes[33]=8'h02;bytes[34]=8'h03;
            bytes[35]=8'hfe;bytes[36]=8'hff;bytes[37]=8'h7f;
            crc=32'hffffffff;
            for(n=32;n<38;n=n+1)crc=crc_byte(crc,bytes[n]);
            crc=~crc;
            bytes[28]=crc[7:0];bytes[29]=crc[15:8];
            bytes[30]=crc[23:16];bytes[31]=crc[31:24];
        end
    endtask

    task build_control;
        begin
            for(n=0;n<64;n=n+1)bytes[n]=0;
            bytes[0]="D";bytes[1]="A";bytes[2]="C";bytes[3]="U";
            bytes[4]=1;bytes[5]=8'h01;bytes[6]=1;bytes[7]=32;
            bytes[8]=8'h78;bytes[9]=8'h56;bytes[10]=8'h34;bytes[11]=8'h12;
            bytes[16]=8'h04;bytes[17]=8'h00;
            bytes[26]=24;bytes[27]=1;
            bytes[32]=1;bytes[33]=0;bytes[34]=3;bytes[35]=1;
            bytes[36]=0;bytes[37]=0;bytes[38]=0;bytes[39]=0;
            crc=32'hffffffff;
            for(n=32;n<40;n=n+1)crc=crc_byte(crc,bytes[n]);
            crc=~crc;
            bytes[28]=crc[7:0];bytes[29]=crc[15:8];
            bytes[30]=crc[23:16];bytes[31]=crc[31:24];
        end
    endtask

    task send_payload;
        input integer length;
        begin
            @(negedge clk);packet_start=1;packet_length=length;
            @(negedge clk);packet_start=0;
            for(n=0;n<length;n=n+1)begin
                payload_data=bytes[n];payload_valid=1;payload_last=(n==length-1);
                @(negedge clk);
            end
            payload_valid=0;payload_last=0;
        end
    endtask

    always @(posedge clk) begin
        if(header_valid)valid_count=valid_count+1;
        if(packet_error)error_count=error_count+1;
        if(body_valid)body_count=body_count+1;
    end

    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        build_wave;send_payload(38);repeat(3)@(negedge clk);
        if(valid_count!=1||error_count!=0||body_count!=6||msg_type!=2||
           transaction_id!=32'h12345678||sequence!=3||total_samples!=4096||
           sample_offset!=6||sample_count!=2)begin
            $display("UPLOAD_LEGAL_FAILED valid=%0d error=%0d body=%0d",valid_count,error_count,body_count);
            test_errors=test_errors+1;
        end
        build_wave;bytes[35]=bytes[35]^1;send_payload(38);repeat(3)@(negedge clk);
        if(valid_count!=1||error_count!=1)begin
            $display("UPLOAD_BAD_CRC_FAILED valid=%0d error=%0d",valid_count,error_count);
            test_errors=test_errors+1;
        end
        build_control;send_payload(40);repeat(3)@(negedge clk);
        if(valid_count!=2||error_count!=1||msg_type!=1||body_count!=20)begin
            $display("UPLOAD_CONTROL_FAILED valid=%0d error=%0d body=%0d",
                     valid_count,error_count,body_count);
            test_errors=test_errors+1;
        end
        build_control;send_payload(39);repeat(3)@(negedge clk);
        if(valid_count!=2||error_count!=2)begin
            $display("UPLOAD_SHORT_CONTROL_FAILED valid=%0d error=%0d",
                     valid_count,error_count);
            test_errors=test_errors+1;
        end
        for(n=0;n<64;n=n+1)bytes[n]=0;
        bytes[0]="D";bytes[1]="A";bytes[2]="C";bytes[3]="U";
        bytes[4]=1;bytes[5]=8'h03;bytes[7]=32;bytes[26]=24;bytes[27]=1;
        send_payload(32);repeat(3)@(negedge clk);
        if(valid_count!=3||error_count!=2)begin
            $display("UPLOAD_HEADER_ONLY_FAILED valid=%0d error=%0d",valid_count,error_count);
            test_errors=test_errors+1;
        end
        if(test_errors==0)$display("DAC24_UPLOAD_PROTOCOL_RX_PASS");
        else $fatal(1,"DAC24_UPLOAD_PROTOCOL_RX_FAILED errors=%0d",test_errors);
        $finish;
    end
endmodule
