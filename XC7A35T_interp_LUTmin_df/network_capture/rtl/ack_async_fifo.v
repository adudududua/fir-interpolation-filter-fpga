`timescale 1ns / 1ps

//=============================================================
// 文件名       : ack_async_fifo.v
// 模块名       : ack_async_fifo
// 功能简述     : ARP/ACK 以太网字节流跨时钟异步 FIFO。采用 Gray 指针同步、写满/读空保护和读域预取寄存，保证反压期间输出数据稳定。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
// ACK 帧跨时钟域异步 FIFO。每个字包含 {帧末标志, 数据字节}。
// 深度 256 足以容纳数个 78 字节 ACK 帧；指针使用 Gray 码同步，
// 读写存储器均为单时钟端口，便于 Vivado 推断分布式 RAM。
module ack_async_fifo #(
    parameter integer ADDR_W = 8
)(
    input  wire              wr_clk,
    input  wire              wr_rst_n,
    input  wire [8:0]        wr_data,
    input  wire              wr_valid,
    output wire              wr_ready,
    input  wire              rd_clk,
    input  wire              rd_rst_n,
    output wire [8:0]        rd_data,
    output wire              rd_valid,
    input  wire              rd_ready
);
    localparam integer DEPTH = (1 << ADDR_W);
    // 标准双时钟 simple-dual-port BRAM：写口属于 RXC，读口属于 TXC。
    // 每个 FIFO 只需一块 RAMB18，换取已登记的读域输出和明确 CDC 边界。
    (* ram_style = "block" *) reg [8:0] mem [0:DEPTH-1];

    reg [ADDR_W:0] wr_bin, wr_gray;
    reg [ADDR_W:0] rd_bin, rd_gray;
    (* ASYNC_REG = "TRUE" *) reg [ADDR_W:0] rd_gray_w1, rd_gray_w2;
    (* ASYNC_REG = "TRUE" *) reg [ADDR_W:0] wr_gray_r1, wr_gray_r2;

    wire wr_push = wr_valid && wr_ready;
    wire rd_pop  = rd_valid && rd_ready;
    wire [ADDR_W:0] wr_bin_next = wr_bin + wr_push;
    wire [ADDR_W:0] rd_bin_plus_one =
        rd_bin + {{ADDR_W{1'b0}}, 1'b1};
    wire [ADDR_W:0] wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;
    wire [ADDR_W:0] rd_gray_plus_one =
        (rd_bin_plus_one >> 1) ^ rd_bin_plus_one;
    wire [ADDR_W:0] wr_bin_plus_one = wr_bin + {{ADDR_W{1'b0}}, 1'b1};
    wire [ADDR_W:0] wr_gray_plus_one =
        (wr_bin_plus_one >> 1) ^ wr_bin_plus_one;
    wire fifo_full = (wr_gray_plus_one ==
                      {~rd_gray_w2[ADDR_W:ADDR_W-1],
                       rd_gray_w2[ADDR_W-2:0]});
    // rd_bin/rd_gray 指向“下一个尚未预取的字节”。读时钟域再用
    // 一级输出寄存器做 FWFT，避免 LUTRAM 的异步组合读直接进入
    // TX 仲裁/输出逻辑。
    wire memory_empty = (rd_gray == wr_gray_r2);
    reg [8:0] rd_data_reg;
    reg       rd_valid_reg;
    wire can_prefetch = !rd_valid_reg || rd_ready;
    wire do_prefetch  = can_prefetch && !memory_empty;

    assign wr_ready = !fifo_full;
    assign rd_valid = rd_valid_reg;
    assign rd_data  = rd_data_reg;

    // 存储器写端不带异步复位，保持严格双时钟 RAM 推断模板。
    always @(posedge wr_clk) begin
        if (wr_push)
            mem[wr_bin[ADDR_W-1:0]] <= wr_data;
    end

    // 只在读时钟域预取并寄存数据；该寄存器无复位，
    // rd_valid_reg=0 时其内容不对外有效。
    always @(posedge rd_clk) begin
        if (do_prefetch)
            rd_data_reg <= mem[rd_bin[ADDR_W-1:0]];
    end

    // wr_rst_n/rd_rst_n 均已由各自时钟域的外层同步器产生。指针采用
    // 同步复位，避免带异步控制的寄存器直接驱动 BRAM 地址/使能。
    always @(posedge wr_clk) begin
        if (!wr_rst_n) begin
            wr_bin <= 0; wr_gray <= 0;
            rd_gray_w1 <= 0; rd_gray_w2 <= 0;
        end else begin
            rd_gray_w1 <= rd_gray;
            rd_gray_w2 <= rd_gray_w1;
            if (wr_push) begin
                wr_bin <= wr_bin_next;
                wr_gray <= wr_gray_next;
            end
        end
    end

    always @(posedge rd_clk) begin
        if (!rd_rst_n) begin
            rd_bin <= 0; rd_gray <= 0;
            wr_gray_r1 <= 0; wr_gray_r2 <= 0;
            rd_valid_reg <= 1'b0;
        end else begin
            wr_gray_r1 <= wr_gray;
            wr_gray_r2 <= wr_gray_r1;
            if (do_prefetch) begin
                rd_bin <= rd_bin_plus_one;
                rd_gray <= rd_gray_plus_one;
                rd_valid_reg <= 1'b1;
            end else if (rd_pop) begin
                rd_valid_reg <= 1'b0;
            end
        end
    end
endmodule
