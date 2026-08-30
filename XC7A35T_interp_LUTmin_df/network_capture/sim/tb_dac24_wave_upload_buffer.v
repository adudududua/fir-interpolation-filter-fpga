`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_dac24_wave_upload_buffer.v
// 模块名       : tb_dac24_wave_upload_buffer
// 功能简述     : 上传事务与双 Bank 控制测试。覆盖顺序、offset、重传、family 门禁、capture_ready、循环/单次播放及提交复位。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
// 上传事务/双 bank 播放缓冲自检：
// 乱序拒绝 -> 协议错误拒绝 -> 两包正常上传 -> COMMIT -> 循环播放。
module tb_dac24_wave_upload_buffer;
    reg rx_clk = 1'b0;
    reg audio_clk = 1'b0;
    always #5 rx_clk = ~rx_clk;
    always #7 audio_clk = ~audio_clk;

    reg rx_rst_n = 1'b0;
    reg audio_rst_n = 1'b0;
    reg header_valid = 1'b0;
    reg packet_error = 1'b0;
    reg [7:0] msg_type = 8'd0;
    reg [7:0] flags = 8'd0;
    reg [31:0] transaction_id = 32'd0;
    reg [31:0] sequence = 32'd0;
    reg [31:0] total_samples = 32'd0;
    reg [31:0] sample_offset = 32'd0;
    reg [15:0] sample_count = 16'd0;
    reg [7:0] body_data = 8'd0;
    reg body_valid = 1'b0;
    reg body_last = 1'b0;
    reg sample_ce = 1'b0;
    reg capture_ready = 1'b1;
    reg current_family_48k = 1'b0;

    wire status_valid;
    wire [15:0] status_code;
    wire [31:0] status_transaction_id;
    wire [31:0] status_sequence;
    wire [31:0] status_total_samples;
    wire [31:0] next_offset;
    wire transaction_active;
    wire [31:0] active_transaction_id;
    wire signed [23:0] sample_out;
    wire sample_update;
    wire source_active;
    wire pipeline_reset_pulse;
    wire playback_family_48k;
    wire [1:0] playback_mode;
    wire [31:0] playback_length;

    integer errors = 0;
    integer played = 0;
    reg signed [23:0] expected [0:5];

    dac24_wave_upload_buffer #(
        .ADDR_WIDTH(4),
        .MAX_SAMPLES(16)
    ) dut (
        .rx_clk(rx_clk), .rx_rst_n(rx_rst_n),
        .header_valid(header_valid), .packet_error(packet_error),
        .msg_type(msg_type), .flags(flags),
        .transaction_id(transaction_id), .sequence(sequence),
        .total_samples(total_samples), .sample_offset(sample_offset),
        .sample_count(sample_count),
        .body_data(body_data), .body_valid(body_valid), .body_last(body_last),
        .status_valid(status_valid), .status_code(status_code),
        .status_transaction_id(status_transaction_id),
        .status_sequence(status_sequence),
        .status_total_samples(status_total_samples), .next_offset(next_offset),
        .transaction_active(transaction_active),
        .active_transaction_id(active_transaction_id),
        .last_received_transaction_id(),
        .audio_clk(audio_clk), .audio_rst_n(audio_rst_n), .sample_ce(sample_ce),
        .capture_ready(capture_ready),
        .current_family_48k(current_family_48k),
        .sample_out(sample_out), .sample_update(sample_update),
        .source_active(source_active), .pipeline_reset_pulse(pipeline_reset_pulse),
        .playback_family_48k(playback_family_48k),
        .playback_mode(playback_mode), .playback_length(playback_length),
        .playback_transaction_id()
    );

    task send_body;
        input [7:0] value;
        input is_last;
        begin
            @(negedge rx_clk);
            body_data = value;
            body_valid = 1'b1;
            body_last = is_last;
            header_valid = is_last;
            @(negedge rx_clk);
            body_valid = 1'b0;
            body_last = 1'b0;
            header_valid = 1'b0;
        end
    endtask

    task begin_upload;
        input [31:0] tid;
        begin
            msg_type = 8'h01;
            flags = 8'h02; // LOOP
            transaction_id = tid;
            sequence = 0;
            total_samples = 4;
            sample_offset = 0;
            sample_count = 0;
            send_body(8'h01, 0); // BEGIN
            send_body(8'h00, 0); // 44.1 kHz
            send_body(8'h03, 0); // 128x
            send_body(8'h01, 0); // PC source
            send_body(8'h00, 0);
            send_body(8'h00, 0);
            send_body(8'h00, 0);
            send_body(8'h00, 1); // repeat_count=0，配合 LOOP 无限循环
        end
    endtask

    task send_wave2;
        input [31:0] tid;
        input [31:0] seq;
        input [31:0] off;
        input [23:0] a;
        input [23:0] b;
        begin
            msg_type = 8'h02;
            flags = 8'h02;
            transaction_id = tid;
            sequence = seq;
            total_samples = 4;
            sample_offset = off;
            sample_count = 2;
            send_body(a[7:0], 0);
            send_body(a[15:8], 0);
            send_body(a[23:16], 0);
            send_body(b[7:0], 0);
            send_body(b[15:8], 0);
            send_body(b[23:16], 1);
        end
    endtask

    task send_commit;
        input [31:0] tid;
        begin
            @(negedge rx_clk);
            msg_type = 8'h03;
            flags = 8'h02;
            transaction_id = tid;
            sequence = 2;
            total_samples = 4;
            sample_offset = 4;
            sample_count = 0;
            header_valid = 1'b1;
            @(negedge rx_clk);
            header_valid = 1'b0;
        end
    endtask

    task expect_status;
        input [15:0] wanted;
        input [31:0] wanted_offset;
        begin
            if (!status_valid || status_code !== wanted ||
                status_total_samples !== total_samples ||
                next_offset !== wanted_offset) begin
                $display("错误：状态 code=%0d offset=%0d，期望 code=%0d offset=%0d",
                         status_code, next_offset, wanted, wanted_offset);
                errors = errors + 1;
            end
        end
    endtask

    task pulse_sample_ce;
        begin
            @(negedge audio_clk);
            sample_ce = 1'b1;
            @(negedge audio_clk);
            sample_ce = 1'b0;
        end
    endtask

    always @(negedge audio_clk) begin
        if (sample_update) begin
            if (played > 5 || sample_out !== expected[played]) begin
                $display("错误：播放样本[%0d]=%0d，期望=%0d", played,
                         $signed(sample_out), $signed(expected[played]));
                errors = errors + 1;
            end
            played = played + 1;
        end
    end

    initial begin
        expected[0] = 24'sd1;
        expected[1] = -24'sd1;
        expected[2] = 24'sh123456;
        expected[3] = -24'sh800000;
        expected[4] = 24'sd1;
        expected[5] = -24'sd1;

        repeat (4) @(posedge rx_clk);
        rx_rst_n = 1'b1;
        audio_rst_n = 1'b1;
        repeat (2) @(posedge rx_clk);

        begin_upload(32'h13572468);
        expect_status(16'd0, 32'd0);
        if (!transaction_active) begin
            $display("错误：BEGIN 后事务没有激活");
            errors = errors + 1;
        end

        // 首先发送乱序包，必须拒绝且 next_offset 保持 0。
        send_wave2(32'h13572468, 32'd1, 32'd2, 24'h111111, 24'h222222);
        expect_status(16'd4, 32'd0);

        // 模拟协议解析器报告 CRC/长度错误，不能推进事务。
        @(negedge rx_clk);
        transaction_id = 32'h13572468;
        sequence = 0;
        packet_error = 1'b1;
        @(negedge rx_clk);
        packet_error = 1'b0;
        expect_status(16'd1, 32'd0);

        send_wave2(32'h13572468, 32'd0, 32'd0, 24'h000001, 24'hFFFFFF);
        expect_status(16'd0, 32'd2);
        // 模拟 ACK 丢失后重发上一包：必须幂等成功且不能重复推进。
        send_wave2(32'h13572468, 32'd0, 32'd0, 24'h000001, 24'hFFFFFF);
        expect_status(16'd0, 32'd2);

        send_wave2(32'h13572468, 32'd1, 32'd2, 24'h123456, 24'h800000);
        expect_status(16'd0, 32'd4);

        // 模拟旧采集帧仍在发送：COMMIT 可以应答，但不得立即开始播放。
        capture_ready = 1'b0;
        send_commit(32'h13572468);
        expect_status(16'd0, 32'd4);
        // COMMIT ACK 丢失后重发也必须成功，但不能再次切换 bank。
        send_commit(32'h13572468);
        expect_status(16'd0, 32'd4);
        if (transaction_active) begin
            $display("错误：COMMIT 后事务仍处于激活状态");
            errors = errors + 1;
        end

        // 等待提交事件和 BRAM 首样本预取完成。
        repeat (10) @(posedge audio_clk);
        if (source_active || pipeline_reset_pulse) begin
            $display("错误：采集 RAM 忙时提前启动了新播放 epoch");
            errors = errors + 1;
        end
        // 采集 RAM 已空闲但板上采样率族不匹配时，仍不得消耗样本。
        current_family_48k = 1'b1;
        capture_ready = 1'b1;
        repeat (10) @(posedge audio_clk);
        if (source_active || pipeline_reset_pulse) begin
            $display("错误：采样率族不匹配时提前启动了播放");
            errors = errors + 1;
        end
        current_family_48k = 1'b0;
        repeat (10) @(posedge audio_clk);
        if (!source_active || playback_length != 4 || playback_mode != 3) begin
            $display("错误：音频侧没有采用已提交的描述符");
            errors = errors + 1;
        end

        pulse_sample_ce();
        pulse_sample_ce();
        pulse_sample_ce();
        pulse_sample_ce();
        pulse_sample_ce();
        pulse_sample_ce();
        repeat (4) @(posedge audio_clk);

        if (played != 6) begin
            $display("错误：只观察到 %0d 个播放样本，期望 6", played);
            errors = errors + 1;
        end

        // 回归首次正式冲激偶发失败：上一事务的非零样本仍停留在
        // sample_out 时，提交新事务必须立即把输出寄存器清零，不得让
        // 旧样本进入新的流水线 epoch。
        if (sample_out !== -24'sd1) begin
            $display("错误：未建立非零旧样本的回归前置条件");
            errors = errors + 1;
        end
        begin_upload(32'h24681357);
        expect_status(16'd0, 32'd0);
        send_wave2(32'h24681357, 32'd0, 32'd0, 24'h400000, 24'h000000);
        expect_status(16'd0, 32'd2);
        send_wave2(32'h24681357, 32'd1, 32'd2, 24'h000000, 24'h000000);
        expect_status(16'd0, 32'd4);
        send_commit(32'h24681357);
        expect_status(16'd0, 32'd4);
        repeat (10) @(posedge audio_clk);
        if (sample_out !== 24'sd0) begin
            $display("错误：新 COMMIT 采用后仍残留旧样本 %0d", $signed(sample_out));
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: 两包上传、原子提交、循环播放和错误拒绝全部通过");
        else
            $display("FAIL: 共 %0d 个错误", errors);
        $finish;
    end
endmodule
