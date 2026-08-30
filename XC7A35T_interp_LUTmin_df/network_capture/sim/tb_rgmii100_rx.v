`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_rgmii100_rx.v
// 模块名       : tb_rgmii100_rx
// 功能简述     : 100M RGMII 接收测试。验证下降沿取样、前导/SFD 搜索、错误前导重同步、字节拼接及奇数半字节截断。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
module tb_rgmii100_rx;
    reg rx_clk = 1'b0;
    reg rst_n = 1'b0;
    reg [3:0] rgmii_rxd = 4'd0;
    reg rgmii_rxctl = 1'b0;
    always #20 rx_clk = ~rx_clk;

    wire [7:0] data;
    wire data_valid, frame_start, frame_end, frame_error;
    integer byte_count = 0;
    integer frame_byte_index = 0;
    integer end_count = 0;
    integer errors = 0;
    reg [7:0] expected [0:3];

    rgmii100_rx dut(
        .rx_clk(rx_clk), .rst_n(rst_n), .rgmii_rxd(rgmii_rxd),
        .rgmii_rxctl(rgmii_rxctl), .data(data), .data_valid(data_valid),
        .frame_start(frame_start), .frame_end(frame_end), .frame_error(frame_error)
    );

    task send_symbol;
        input [3:0] rise_nibble;
        input [3:0] fall_nibble;
        input rise_ctl;
        input fall_ctl;
        begin
            @(negedge rx_clk); #1;
            rgmii_rxd=rise_nibble; rgmii_rxctl=rise_ctl;
            @(posedge rx_clk); #1;
            rgmii_rxd=fall_nibble; rgmii_rxctl=fall_ctl;
        end
    endtask

    task send_byte;
        input [7:0] value;
        begin
            send_symbol(value[3:0],value[3:0],1'b1,1'b1);
            send_symbol(value[7:4],value[7:4],1'b1,1'b1);
        end
    endtask

    task send_preamble;
        integer preamble_index;
        begin
            for (preamble_index = 0; preamble_index < 7;
                 preamble_index = preamble_index + 1)
                send_byte(8'h55);
            send_byte(8'hD5);
        end
    endtask

    always @(posedge rx_clk) begin
        #2;
        if(data_valid) begin
            if(data!==expected[byte_count]) begin
                $display("RGMII_BYTE_MISMATCH index=%0d got=%02x exp=%02x",
                         byte_count,data,expected[byte_count]);
                errors=errors+1;
            end
            if((frame_byte_index==0) !== frame_start) begin
                $display("RGMII_START_MISMATCH index=%0d start=%b",byte_count,frame_start);
                errors=errors+1;
            end
            byte_count=byte_count+1;
            frame_byte_index=frame_byte_index+1;
        end
        if(frame_end) begin
            end_count=end_count+1;
            frame_byte_index=0;
            if((end_count==1) && frame_error) begin
                $display("RGMII_GOOD_FRAME_ERROR"); errors=errors+1;
            end
            if((end_count==2) && frame_error) begin
                $display("RGMII_RISE_MISMATCH_FALSE_ERROR"); errors=errors+1;
            end
            if((end_count==3) && !frame_error) begin
                $display("RGMII_ODD_NIBBLE_NOT_DETECTED"); errors=errors+1;
            end
        end
    end

    initial begin
        expected[0]=8'h12; expected[1]=8'h34; expected[2]=8'hab; expected[3]=8'hce;
        repeat(4) @(negedge rx_clk); rst_n=1'b1;
        repeat(3) send_symbol(4'd0,4'd0,1'b0,1'b0);
        send_preamble();
        send_byte(8'h12); send_byte(8'h34);
        send_symbol(4'd0,4'd0,1'b0,1'b0);
        repeat(4) send_symbol(4'd0,4'd0,1'b0,1'b0);

        // 错误前导和孤立 SFD 不得泄漏到上层；随后在同一 RX_DV 内重新同步。
        send_byte(8'h55); send_byte(8'h55); send_byte(8'h54);
        send_byte(8'hD5); send_byte(8'h11);
        send_preamble();
        send_byte(8'hab);
        send_symbol(4'hd,4'he,1'b0,1'b1);
        send_symbol(4'hc,4'hc,1'b1,1'b1);
        send_symbol(4'd0,4'd0,1'b0,1'b0);
        repeat(3) send_symbol(4'd0,4'd0,1'b0,1'b0);

        send_preamble();
        send_symbol(4'h5,4'h5,1'b1,1'b1);
        send_symbol(4'd0,4'd0,1'b0,1'b0);
        repeat(6) send_symbol(4'd0,4'd0,1'b0,1'b0);

        if(byte_count!=4 || end_count!=3) begin
            $display("RGMII_COUNT_FAILED bytes=%0d ends=%0d",byte_count,end_count);
            errors=errors+1;
        end
        if(errors==0) $display("RGMII100_RX_PASS");
        else $fatal(1,"RGMII100_RX_FAILED errors=%0d",errors);
        $finish;
    end
endmodule
