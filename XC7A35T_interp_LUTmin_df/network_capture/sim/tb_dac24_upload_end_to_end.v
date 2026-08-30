`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_dac24_upload_end_to_end.v
// 模块名       : tb_dac24_upload_end_to_end
// 功能简述     : DACU 协议解析、上传双 Bank、COMMIT、ACK 与音频播放的模块级端到端测试，逐点核对 s24LE 样本。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
// Phase 2 PC->FPGA 闭环集成仿真：
// RGMII(含前导码/SFD/FCS) -> IPv4/UDP4001 -> DACU -> 双 bank 播放 -> ACK。
// 本用例不实例化 FIR，目的是把网络协议、事务状态、capture_ready 门控和 ACK 字段隔离验证清楚。
module tb_dac24_upload_end_to_end;
    localparam [31:0] TXID = 32'h1234_ABCD;
    localparam integer SAMPLE_TOTAL = 4;

    reg rx_clk = 1'b0;
    reg audio_clk = 1'b0;
    reg rst_n = 1'b0;
    always #20 rx_clk = ~rx_clk;       // RTL8211E 百兆模式：25 MHz
    always #5  audio_clk = ~audio_clk;

    reg [3:0] rgmii_rxd = 4'd0;
    reg       rgmii_rxctl = 1'b0;

    wire [7:0] mac_data;
    wire mac_data_valid;
    wire mac_frame_start;
    wire mac_frame_end;
    wire mac_frame_error;

    wire [7:0] udp_payload_data;
    wire udp_payload_valid;
    wire udp_payload_last;
    wire udp_packet_valid;
    wire udp_packet_drop;
    wire [15:0] udp_payload_length;
    wire [31:0] udp_source_ip;
    wire [15:0] udp_source_port;

    wire protocol_header_valid;
    wire protocol_packet_error;
    wire [7:0] protocol_msg_type;
    wire [7:0] protocol_flags;
    wire [31:0] protocol_transaction_id;
    wire [31:0] protocol_sequence;
    wire [31:0] protocol_total_samples;
    wire [31:0] protocol_sample_offset;
    wire [15:0] protocol_sample_count;
    wire [31:0] protocol_payload_crc;
    wire [7:0] protocol_body_data;
    wire protocol_body_valid;
    wire protocol_body_last;

    wire status_valid;
    wire [15:0] status_code;
    wire [31:0] status_transaction_id;
    wire [31:0] status_sequence;
    wire [31:0] status_total_samples;
    wire [31:0] status_next_offset;
    wire transaction_active;
    wire [31:0] active_transaction_id;
    wire [31:0] last_received_transaction_id;

    reg sample_ce = 1'b0;
    reg capture_ready = 1'b0;
    wire signed [23:0] sample_out;
    wire sample_update;
    wire source_active;
    wire pipeline_reset_pulse;
    wire playback_family_48k;
    wire [1:0] playback_mode;
    wire [31:0] playback_length;
    wire [31:0] playback_transaction_id;

    wire ack_event_ready;
    wire [7:0] ack_tx_data;
    wire ack_tx_valid;
    wire ack_tx_last;

    rgmii100_rx u_rgmii_rx (
        .rx_clk(rx_clk), .rst_n(rst_n),
        .rgmii_rxd(rgmii_rxd), .rgmii_rxctl(rgmii_rxctl),
        .data(mac_data), .data_valid(mac_data_valid),
        .frame_start(mac_frame_start), .frame_end(mac_frame_end),
        .frame_error(mac_frame_error)
    );

    udp_ipv4_rx_parser #(.MAX_PAYLOAD(1024)) u_udp_rx (
        .clk(rx_clk), .rst_n(rst_n),
        .frame_data(mac_data), .frame_data_valid(mac_data_valid),
        .frame_start(mac_frame_start), .frame_end(mac_frame_end),
        .frame_error(mac_frame_error),
        .payload_data(udp_payload_data), .payload_valid(udp_payload_valid),
        .payload_last(udp_payload_last), .packet_valid(udp_packet_valid),
        .packet_drop(udp_packet_drop), .payload_length(udp_payload_length),
        .source_ip(udp_source_ip), .source_port(udp_source_port)
    );

    // packet_valid 与合法负载开始回放相差一个周期；协议解析器先看到起始脉冲，
    // 下一周期才接收 header byte 0。这与板级 top 的连接完全一致。
    dac24_upload_protocol_rx u_protocol (
        .clk(rx_clk), .rst_n(rst_n),
        .payload_data(udp_payload_data), .payload_valid(udp_payload_valid),
        .payload_last(udp_payload_last), .packet_start(udp_packet_valid),
        .packet_length(udp_payload_length),
        .header_valid(protocol_header_valid),
        .packet_error(protocol_packet_error), .msg_type(protocol_msg_type),
        .flags(protocol_flags), .transaction_id(protocol_transaction_id),
        .sequence(protocol_sequence), .total_samples(protocol_total_samples),
        .sample_offset(protocol_sample_offset), .sample_count(protocol_sample_count),
        .body_data(protocol_body_data),
        .body_valid(protocol_body_valid), .body_last(protocol_body_last)
    );

    dac24_wave_upload_buffer #(
        .ADDR_WIDTH(4), .MAX_SAMPLES(16)
    ) u_upload (
        .rx_clk(rx_clk), .rx_rst_n(rst_n),
        .header_valid(protocol_header_valid),
        .packet_error(protocol_packet_error), .msg_type(protocol_msg_type),
        .flags(protocol_flags), .transaction_id(protocol_transaction_id),
        .sequence(protocol_sequence), .total_samples(protocol_total_samples),
        .sample_offset(protocol_sample_offset), .sample_count(protocol_sample_count),
        .body_data(protocol_body_data),
        .body_valid(protocol_body_valid), .body_last(protocol_body_last),
        .status_valid(status_valid), .status_code(status_code),
        .status_transaction_id(status_transaction_id),
        .status_sequence(status_sequence),
        .status_total_samples(status_total_samples), .next_offset(status_next_offset),
        .transaction_active(transaction_active),
        .active_transaction_id(active_transaction_id),
        .last_received_transaction_id(last_received_transaction_id),
        .audio_clk(audio_clk), .audio_rst_n(rst_n), .sample_ce(sample_ce),
        .capture_ready(capture_ready), .current_family_48k(1'b0),
        .sample_out(sample_out),
        .sample_update(sample_update), .source_active(source_active),
        .pipeline_reset_pulse(pipeline_reset_pulse),
        .playback_family_48k(playback_family_48k),
        .playback_mode(playback_mode), .playback_length(playback_length),
        .playback_transaction_id(playback_transaction_id)
    );

    udp_control_ack_tx u_ack_tx (
        .clk(rx_clk), .rst_n(rst_n), .event_valid(status_valid),
        .event_ready(ack_event_ready), .status_code(status_code),
        .transaction_id(status_transaction_id), .sequence(status_sequence),
        .total_samples(status_total_samples), .next_offset(status_next_offset),
        .dest_ip(udp_source_ip), .dest_port(udp_source_port),
        .tx_data(ack_tx_data), .tx_valid(ack_tx_valid),
        .tx_ready(1'b1), .tx_last(ack_tx_last)
    );

    reg [7:0] payload [0:1023];
    reg [7:0] frame [0:2047];
    reg [7:0] ack_bytes [0:511];
    reg signed [23:0] played_samples [0:15];
    integer payload_size;
    integer frame_size;
    integer ack_count = 0;
    integer ack_frames = 0;
    integer ack_frame_base = 0;
    integer played_count = 0;
    integer packet_drop_count = 0;
    integer pipeline_reset_count = 0;
    integer errors = 0;
    integer i;
    reg [31:0] crc_work;

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

    task put_u32_le;
        input integer offset;
        input [31:0] value;
        begin
            payload[offset+0] = value[7:0];
            payload[offset+1] = value[15:8];
            payload[offset+2] = value[23:16];
            payload[offset+3] = value[31:24];
        end
    endtask

    task begin_header;
        input [7:0] msg_type;
        input [7:0] flags;
        input [31:0] sequence;
        input [31:0] offset;
        input [15:0] count;
        integer n;
        begin
            for (n = 0; n < 1024; n = n + 1) payload[n] = 8'd0;
            payload[0]=8'h44; payload[1]=8'h41; payload[2]=8'h43; payload[3]=8'h55;
            payload[4]=8'h01; payload[5]=msg_type; payload[6]=flags; payload[7]=8'd32;
            put_u32_le(8, TXID);
            put_u32_le(12, sequence);
            put_u32_le(16, SAMPLE_TOTAL);
            put_u32_le(20, offset);
            payload[24]=count[7:0]; payload[25]=count[15:8];
            payload[26]=8'd24; payload[27]=8'd1;
        end
    endtask

    task finish_body_crc;
        input integer body_length;
        integer n;
        reg [31:0] body_fcs;
        begin
            if (body_length == 0) begin
                body_fcs = 32'd0;
            end else begin
                crc_work = 32'hFFFF_FFFF;
                for (n = 0; n < body_length; n = n + 1)
                    crc_work = crc32_byte(crc_work, payload[32+n]);
                body_fcs = ~crc_work;
            end
            put_u32_le(28, body_fcs);
            payload_size = 32 + body_length;
        end
    endtask

    task build_begin;
        begin
            begin_header(8'h01, 8'h01, 32'd0, 32'd0, 16'd0);
            payload[32]=8'h01; // BEGIN
            payload[33]=8'h00; // 44.1 kHz family
            payload[34]=8'h03; // 128x
            payload[35]=8'h01; // upload RAM
            payload[36]=8'h01; payload[37]=8'h00;
            payload[38]=8'h00; payload[39]=8'h00; // repeat_count=1
            finish_body_crc(8);
        end
    endtask

    task build_wave;
        begin
            begin_header(8'h02, 8'h01, 32'd0, 32'd0, SAMPLE_TOTAL);
            // 四个有符号 24 位小端样本。
            payload[32]=8'h56; payload[33]=8'h34; payload[34]=8'h12;
            payload[35]=8'hFE; payload[36]=8'hFF; payload[37]=8'hFF;
            payload[38]=8'h00; payload[39]=8'h00; payload[40]=8'h80;
            payload[41]=8'hFF; payload[42]=8'hFF; payload[43]=8'h7F;
            finish_body_crc(12);
        end
    endtask

    task build_commit;
        begin
            // ACK_REQUIRED | RESET_PIPELINE | ONE_SHOT
            begin_header(8'h03, 8'h0D, 32'd1, SAMPLE_TOTAL, 16'd0);
            finish_body_crc(0);
        end
    endtask

    task build_ethernet_frame;
        integer n;
        reg [17:0] sum_ext;
        reg [15:0] checksum;
        reg [31:0] fcs;
        integer ip_total_length;
        integer udp_length;
        begin
            for (n = 0; n < 2048; n = n + 1) frame[n] = 8'd0;
            frame_size = 14 + 20 + 8 + payload_size + 4;
            ip_total_length = 20 + 8 + payload_size;
            udp_length = 8 + payload_size;

            // FPGA MAC / PC MAC / EtherType IPv4
            frame[0]=8'h02; frame[1]=8'h35; frame[2]=8'h24;
            frame[3]=8'h00; frame[4]=8'h00; frame[5]=8'h01;
            frame[6]=8'h10; frame[7]=8'h20; frame[8]=8'h30;
            frame[9]=8'h40; frame[10]=8'h50; frame[11]=8'h60;
            frame[12]=8'h08; frame[13]=8'h00;

            frame[14]=8'h45; frame[15]=8'h00;
            frame[16]=ip_total_length >> 8; frame[17]=ip_total_length;
            frame[18]=8'h12; frame[19]=8'h34;
            frame[20]=8'h40; frame[21]=8'h00;
            frame[22]=8'h40; frame[23]=8'h11;
            frame[24]=8'h00; frame[25]=8'h00;
            frame[26]=8'hC0; frame[27]=8'hA8; frame[28]=8'h01; frame[29]=8'h14;
            frame[30]=8'hC0; frame[31]=8'hA8; frame[32]=8'h01; frame[33]=8'h0A;

            sum_ext = 18'd0;
            for (n = 14; n < 34; n = n + 2) begin
                sum_ext = sum_ext + {frame[n],frame[n+1]};
                sum_ext = {2'd0,sum_ext[15:0]} + sum_ext[17:16];
            end
            sum_ext = {2'd0,sum_ext[15:0]} + sum_ext[17:16];
            checksum = ~sum_ext[15:0];
            frame[24]=checksum[15:8]; frame[25]=checksum[7:0];

            frame[34]=8'h13; frame[35]=8'h88; // PC source port 5000
            frame[36]=8'h0F; frame[37]=8'hA1; // FPGA UDP4001
            frame[38]=udp_length >> 8; frame[39]=udp_length;
            frame[40]=8'h00; frame[41]=8'h00; // UDP checksum disabled
            for (n = 0; n < payload_size; n = n + 1)
                frame[42+n] = payload[n];

            crc_work = 32'hFFFF_FFFF;
            for (n = 0; n < frame_size-4; n = n + 1)
                crc_work = crc32_byte(crc_work, frame[n]);
            fcs = ~crc_work;
            frame[frame_size-4]=fcs[7:0];
            frame[frame_size-3]=fcs[15:8];
            frame[frame_size-2]=fcs[23:16];
            frame[frame_size-1]=fcs[31:24];
        end
    endtask

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

    task send_rgmii_byte;
        input [7:0] value;
        begin
            send_symbol(value[3:0], value[3:0], 1'b1, 1'b1);
            send_symbol(value[7:4], value[7:4], 1'b1, 1'b1);
        end
    endtask

    task send_current_frame;
        integer n;
        begin
            repeat (3) send_symbol(4'd0,4'd0,1'b0,1'b0);
            for (n = 0; n < 7; n = n + 1) send_rgmii_byte(8'h55);
            send_rgmii_byte(8'hD5);
            for (n = 0; n < frame_size; n = n + 1)
                send_rgmii_byte(frame[n]);
            send_symbol(4'd0,4'd0,1'b0,1'b0);
            repeat (3) send_symbol(4'd0,4'd0,1'b0,1'b0);
        end
    endtask

    task expect_ack_u32_le;
        input integer frame_number;
        input integer byte_offset;
        input [31:0] expected;
        integer base;
        reg [31:0] actual;
        begin
            base = frame_number * 86;
            actual = {ack_bytes[base+byte_offset+3], ack_bytes[base+byte_offset+2],
                      ack_bytes[base+byte_offset+1], ack_bytes[base+byte_offset+0]};
            if (actual !== expected) begin
                $display("ACK_U32_FAIL frame=%0d offset=%0d got=%08x expected=%08x",
                         frame_number, byte_offset, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    task check_ack;
        input integer frame_number;
        input [31:0] expected_sequence;
        input [31:0] expected_next;
        integer base;
        integer n;
        reg [31:0] ack_crc;
        reg [31:0] ack_fcs;
        begin
            base = frame_number * 86;
            if ({ack_bytes[base+50],ack_bytes[base+51],ack_bytes[base+52],ack_bytes[base+53]}
                !== 32'h44414355 || ack_bytes[base+54] !== 8'h01 ||
                ack_bytes[base+55] !== 8'h81) begin
                $display("ACK_MAGIC_FAIL frame=%0d",frame_number);
                errors = errors + 1;
            end
            if ({ack_bytes[base+38],ack_bytes[base+39],ack_bytes[base+40],ack_bytes[base+41]}
                !== 32'hC0A8_0114 ||
                {ack_bytes[base+44],ack_bytes[base+45]} !== 16'd5000) begin
                $display("ACK_DESTINATION_FAIL frame=%0d ip=%02x%02x%02x%02x port=%0d",
                         frame_number, ack_bytes[base+38],ack_bytes[base+39],
                         ack_bytes[base+40],ack_bytes[base+41],
                         {ack_bytes[base+44],ack_bytes[base+45]});
                errors = errors + 1;
            end
            expect_ack_u32_le(frame_number,58,TXID);
            expect_ack_u32_le(frame_number,62,expected_sequence);
            expect_ack_u32_le(frame_number,66,SAMPLE_TOTAL);
            expect_ack_u32_le(frame_number,70,expected_next);
            if ({ack_bytes[base+75],ack_bytes[base+74]} !== 16'd0) begin
                $display("ACK_STATUS_FAIL frame=%0d status=%04x",frame_number,
                         {ack_bytes[base+75],ack_bytes[base+74]});
                errors = errors + 1;
            end
            if (ack_bytes[base+76] !== 8'd24 || ack_bytes[base+77] !== 8'd1) begin
                $display("ACK_FORMAT_FAIL frame=%0d",frame_number);
                errors = errors + 1;
            end
            ack_crc = 32'hFFFF_FFFF;
            for (n = 8; n < 82; n = n + 1)
                ack_crc = crc32_byte(ack_crc, ack_bytes[base+n]);
            ack_fcs = {ack_bytes[base+85],ack_bytes[base+84],
                       ack_bytes[base+83],ack_bytes[base+82]};
            if (ack_fcs !== ~ack_crc) begin
                $display("ACK_FCS_FAIL frame=%0d got=%08x expected=%08x",
                         frame_number,ack_fcs,~ack_crc);
                errors = errors + 1;
            end
        end
    endtask

    always @(posedge rx_clk) begin
        if (udp_packet_drop)
            packet_drop_count = packet_drop_count + 1;
        if (ack_tx_valid) begin
            ack_bytes[ack_count] = ack_tx_data;
            ack_count = ack_count + 1;
            if (ack_tx_last) begin
                if ((ack_count - ack_frame_base) != 86) begin
                    $display("ACK_LENGTH_FAIL frame=%0d length=%0d",
                             ack_frames, ack_count-ack_frame_base);
                    errors = errors + 1;
                end
                ack_frames = ack_frames + 1;
                ack_frame_base = ack_count;
            end
        end
    end

    always @(posedge audio_clk) begin
        if (pipeline_reset_pulse)
            pipeline_reset_count = pipeline_reset_count + 1;
        if (sample_update && played_count < 16) begin
            played_samples[played_count] = sample_out;
            played_count = played_count + 1;
        end
    end

    task pulse_sample_ce;
        begin
            @(negedge audio_clk); sample_ce = 1'b1;
            @(negedge audio_clk); sample_ce = 1'b0;
            repeat (2) @(negedge audio_clk);
        end
    endtask

    initial begin
        repeat (8) @(negedge rx_clk);
        rst_n = 1'b1;

        build_begin(); build_ethernet_frame(); send_current_frame();
        wait (ack_frames == 1);
        if (!transaction_active || active_transaction_id !== TXID) begin
            $display("BEGIN_STATE_FAIL active=%0b txid=%08x",transaction_active,
                     active_transaction_id);
            errors = errors + 1;
        end

        build_wave(); build_ethernet_frame(); send_current_frame();
        wait (ack_frames == 2);

        // 先占用采集 RAM。COMMIT 可以 ACK，但音频 epoch 绝不能提前启动。
        capture_ready = 1'b0;
        build_commit(); build_ethernet_frame(); send_current_frame();
        wait (ack_frames == 3);
        repeat (20) @(posedge audio_clk);
        if (source_active || pipeline_reset_count != 0 || playback_transaction_id != 0) begin
            $display("CAPTURE_GATE_FAIL active=%0b reset_count=%0d playback_txid=%08x",
                     source_active,pipeline_reset_count,playback_transaction_id);
            errors = errors + 1;
        end

        capture_ready = 1'b1;
        wait (source_active);
        repeat (4) @(posedge audio_clk);
        if (pipeline_reset_count != 1 || playback_transaction_id !== TXID ||
            playback_length !== SAMPLE_TOTAL || playback_family_48k !== 1'b0 ||
            playback_mode !== 2'd3) begin
            $display("PLAYBACK_DESCRIPTOR_FAIL reset=%0d txid=%08x len=%0d family=%0b mode=%0d",
                     pipeline_reset_count,playback_transaction_id,playback_length,
                     playback_family_48k,playback_mode);
            errors = errors + 1;
        end

        // 给 BRAM 预取留出余量，再按输入采样率请求四个样本。
        repeat (5) @(posedge audio_clk);
        pulse_sample_ce(); pulse_sample_ce(); pulse_sample_ce(); pulse_sample_ce();
        wait (played_count == 4);
        if (played_samples[0] !== 24'sh123456 ||
            played_samples[1] !== -24'sd2 ||
            played_samples[2] !== 24'sh800000 ||
            played_samples[3] !== 24'sh7FFFFF) begin
            $display("PLAYBACK_DATA_FAIL %06x %06x %06x %06x",
                     played_samples[0],played_samples[1],played_samples[2],played_samples[3]);
            errors = errors + 1;
        end

        check_ack(0,32'd0,32'd0);
        check_ack(1,32'd0,SAMPLE_TOTAL);
        check_ack(2,32'd1,SAMPLE_TOTAL);

        if (packet_drop_count != 0 || ack_count != 3*86 ||
            last_received_transaction_id !== TXID) begin
            $display("FINAL_COUNT_FAIL drops=%0d ack_bytes=%0d last_txid=%08x",
                     packet_drop_count,ack_count,last_received_transaction_id);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("DAC24_UPLOAD_END_TO_END_PASS ack_frames=%0d played=%0d txid=%08x",
                     ack_frames,played_count,playback_transaction_id);
        else
            $fatal(1,"DAC24_UPLOAD_END_TO_END_FAILED errors=%0d",errors);
        $finish;
    end

    initial begin
        #3000000;
        $fatal(1,"DAC24_UPLOAD_END_TO_END_TIMEOUT");
    end
endmodule
