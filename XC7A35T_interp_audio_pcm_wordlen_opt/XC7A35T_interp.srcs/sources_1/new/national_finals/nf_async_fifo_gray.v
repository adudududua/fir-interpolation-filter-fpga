`timescale 1ns / 1ps

// Small asynchronous FIFO used by the 20 MHz unified-FIR experiment.
// The payload RAM has one write clock and an asynchronous read port, which
// maps efficiently to distributed RAM for the deliberately small depths.
module nf_async_fifo_gray #(
    parameter integer WIDTH = 24,
    parameter integer ADDR_W = 2
)(
    input  wire                 wr_clk,
    input  wire                 wr_rst_n,
    input  wire                 wr_en,
    input  wire [WIDTH-1:0]     wr_data,
    output wire                 wr_full,
    output reg                  wr_overflow,
    input  wire                 rd_clk,
    input  wire                 rd_rst_n,
    input  wire                 rd_en,
    output wire [WIDTH-1:0]     rd_data,
    output wire                 rd_empty,
    output reg                  rd_underflow
);
    localparam integer PTR_W = ADDR_W + 1;
    localparam integer DEPTH = (1 << ADDR_W);

    (* ram_style = "distributed" *) reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [PTR_W-1:0] wr_bin;
    reg [PTR_W-1:0] wr_gray;
    reg [PTR_W-1:0] rd_bin;
    reg [PTR_W-1:0] rd_gray;
    reg wr_full_reg;

    (* ASYNC_REG = "TRUE" *) reg [PTR_W-1:0] rd_gray_wr_meta;
    (* ASYNC_REG = "TRUE" *) reg [PTR_W-1:0] rd_gray_wr_sync;
    (* ASYNC_REG = "TRUE" *) reg [PTR_W-1:0] wr_gray_rd_meta;
    (* ASYNC_REG = "TRUE" *) reg [PTR_W-1:0] wr_gray_rd_sync;

    wire wr_take = wr_en && !wr_full_reg;
    wire rd_take = rd_en && !rd_empty;
    wire [PTR_W-1:0] wr_bin_next = wr_bin + wr_take;
    wire [PTR_W-1:0] rd_bin_next = rd_bin + rd_take;
    wire [PTR_W-1:0] wr_gray_next =
        (wr_bin_next >> 1) ^ wr_bin_next;
    wire [PTR_W-1:0] rd_gray_next =
        (rd_bin_next >> 1) ^ rd_bin_next;
    wire [PTR_W-1:0] rd_gray_full_compare =
        {~rd_gray_wr_sync[PTR_W-1:PTR_W-2],
          rd_gray_wr_sync[PTR_W-3:0]};

    assign wr_full = wr_full_reg;
    assign rd_empty = (rd_gray == wr_gray_rd_sync);
    assign rd_data = mem[rd_bin[ADDR_W-1:0]];

    // Keep payload storage out of the asynchronously reset pointer process;
    // otherwise Vivado dissolves even this small RAM into 96 flip-flops.
    always @(posedge wr_clk) begin
        if (wr_take)
            mem[wr_bin[ADDR_W-1:0]] <= wr_data;
    end

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_bin <= {PTR_W{1'b0}};
            wr_gray <= {PTR_W{1'b0}};
            rd_gray_wr_meta <= {PTR_W{1'b0}};
            rd_gray_wr_sync <= {PTR_W{1'b0}};
            wr_full_reg <= 1'b0;
            wr_overflow <= 1'b0;
        end
        else begin
            rd_gray_wr_meta <= rd_gray;
            rd_gray_wr_sync <= rd_gray_wr_meta;
            wr_bin <= wr_bin_next;
            wr_gray <= wr_gray_next;
            wr_full_reg <= (wr_gray_next == rd_gray_full_compare);
            if (wr_en && wr_full_reg)
                wr_overflow <= 1'b1;
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_bin <= {PTR_W{1'b0}};
            rd_gray <= {PTR_W{1'b0}};
            wr_gray_rd_meta <= {PTR_W{1'b0}};
            wr_gray_rd_sync <= {PTR_W{1'b0}};
            rd_underflow <= 1'b0;
        end
        else begin
            wr_gray_rd_meta <= wr_gray;
            wr_gray_rd_sync <= wr_gray_rd_meta;
            rd_bin <= rd_bin_next;
            rd_gray <= rd_gray_next;
            if (rd_en && rd_empty)
                rd_underflow <= 1'b1;
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (ADDR_W < 2)
            $fatal(1, "nf_async_fifo_gray requires ADDR_W >= 2");
    end
`endif
endmodule
