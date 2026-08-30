`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_ack_async_fifo.v
// 模块名       : tb_ack_async_fifo
// 功能简述     : 异步 FIFO 反压与回卷测试平台。验证长突发、停顿期间数据稳定、跨多次指针回卷后的严格字节顺序。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
module tb_ack_async_fifo;
    localparam integer ADDR_W = 3;
    localparam integer WORDS  = 96;

    reg         wr_clk = 1'b0;
    reg         wr_rst_n = 1'b0;
    reg  [8:0]  wr_data = 9'd0;
    reg         wr_valid = 1'b0;
    wire        wr_ready;

    reg         rd_clk = 1'b0;
    reg         rd_rst_n = 1'b0;
    wire [8:0]  rd_data;
    wire        rd_valid;
    reg         rd_ready = 1'b0;

    integer received = 0;
    integer errors = 0;
    integer rd_cycle = 0;
    integer timeout_cycles = 0;
    reg         stall_seen = 1'b0;
    reg  [8:0]  stall_data = 9'd0;

    always #3.5 wr_clk = ~wr_clk;
    always #5.5 rd_clk = ~rd_clk;

    ack_async_fifo #(
        .ADDR_W(ADDR_W)
    ) dut (
        .wr_clk(wr_clk),
        .wr_rst_n(wr_rst_n),
        .wr_data(wr_data),
        .wr_valid(wr_valid),
        .wr_ready(wr_ready),
        .rd_clk(rd_clk),
        .rd_rst_n(rd_rst_n),
        .rd_data(rd_data),
        .rd_valid(rd_valid),
        .rd_ready(rd_ready)
    );

    function [8:0] expected_word;
        input integer index;
        begin
            expected_word = {(index % 13) == 12,
                             ((index * 8'd37) ^ 8'hA5)};
        end
    endfunction

    task push_word;
        input integer index;
        begin
            @(negedge wr_clk);
            wr_data = expected_word(index);
            wr_valid = 1'b1;
            while (!wr_ready)
                @(negedge wr_clk);
            @(posedge wr_clk);
            @(negedge wr_clk);
            wr_valid = 1'b0;
        end
    endtask

    // 先持续反压使小深度 FIFO 写满，再交替使用长停顿和突发连续读取。
    always @(negedge rd_clk) begin
        if (!rd_rst_n) begin
            rd_cycle = 0;
            rd_ready = 1'b0;
        end else begin
            rd_cycle = rd_cycle + 1;
            if (rd_cycle < 24)
                rd_ready = 1'b0;
            else if (rd_cycle < 40)
                rd_ready = 1'b1;
            else if (rd_cycle < 55)
                rd_ready = 1'b0;
            else if (rd_cycle < 72)
                rd_ready = 1'b1;
            else
                rd_ready = ((rd_cycle % 11) < 7);
        end
    end

    // ready=0 时 valid/data 必须保持稳定；每次实际握手必须严格保持顺序。
    always @(posedge rd_clk) begin
        if (!rd_rst_n) begin
            received <= 0;
            stall_seen <= 1'b0;
        end else begin
            if (rd_valid && !rd_ready) begin
                if (stall_seen && (rd_data !== stall_data)) begin
                    $display("错误：反压期间输出从 %03x 变为 %03x", stall_data, rd_data);
                    errors = errors + 1;
                end
                stall_seen <= 1'b1;
                stall_data <= rd_data;
            end else begin
                stall_seen <= 1'b0;
            end

            if (rd_valid && rd_ready) begin
                if (rd_data !== expected_word(received)) begin
                    $display("错误：第 %0d 个字期望 %03x，实际 %03x",
                             received, expected_word(received), rd_data);
                    errors = errors + 1;
                end
                received <= received + 1;
            end
        end
    end

    initial begin
        repeat (5) @(posedge wr_clk);
        wr_rst_n = 1'b1;
        repeat (3) @(posedge rd_clk);
        rd_rst_n = 1'b1;

        fork
            begin : producer
                integer i;
                for (i = 0; i < WORDS; i = i + 1)
                    push_word(i);
            end
            begin : watchdog
                while ((received < WORDS) && (timeout_cycles < 5000)) begin
                    @(posedge rd_clk);
                    timeout_cycles = timeout_cycles + 1;
                end
            end
        join

        repeat (8) @(posedge rd_clk);
        if (received != WORDS) begin
            $display("错误：仅收到 %0d/%0d 个字", received, WORDS);
            errors = errors + 1;
        end
        if (rd_valid) begin
            $display("错误：全部数据读完后 rd_valid 仍有效");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("ACK_ASYNC_FIFO_BACKPRESSURE_PASS");
        else
            $display("ACK_ASYNC_FIFO_BACKPRESSURE_FAIL errors=%0d", errors);
        $finish;
    end
endmodule
