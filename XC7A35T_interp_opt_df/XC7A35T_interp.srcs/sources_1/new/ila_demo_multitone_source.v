`timescale 1ns / 1ps
//=============================================================
// 文件名       : ila_demo_multitone_source.v
// 模块名       : ila_demo_multitone_source
// 功能简述     : ILA 镜像抑制演示专用 44.1kHz 相干多音源。
//                441 点 ROM 同时包含 4.1kHz 与 15kHz，两个
//                分量各为 0.20FS；4.1kHz 在第一级零插值后
//                产生精确的 40kHz 镜像。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-19
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-19：新增 ILA 镜像抑制演示测试源。
//=============================================================

module ila_demo_multitone_source #(
    parameter integer DATA_W = 24,
    parameter integer ROM_DEPTH = 441,
    parameter MEM_FILE = "ila_demo_mix_4k1_15k_441.mem"
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     enable,
    input  wire                     sample_ce,

    output reg signed [DATA_W-1:0] sample_out,
    output reg                     sample_update,
    output reg [8:0]               sample_index_dbg
);

    (* rom_style = "block" *)
    reg signed [DATA_W-1:0] sample_rom [0:ROM_DEPTH-1];
    reg signed [DATA_W-1:0] rom_data_q;
    (* keep = "true" *) reg [8:0] rom_address = 9'd0;

    initial begin
        $readmemh(MEM_FILE, sample_rom);
    end

    // 独立同步读进程用于稳定推断 512x36 RAMB18 ROM。
    always @(posedge clk) begin
        rom_data_q <= sample_rom[rom_address];
    end

    always @(posedge clk) begin
        if (sample_ce) begin
            if (!enable)
                rom_address <= 9'd0;
            else if (rom_address == ROM_DEPTH - 1)
                rom_address <= 9'd0;
            else
                rom_address <= rom_address + 9'd1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            sample_out      <= {DATA_W{1'b0}};
            sample_update   <= 1'b0;
            sample_index_dbg <= 9'd0;
        end
        else begin
            sample_update <= 1'b0;

            if (sample_ce) begin
                if (enable) begin
                    sample_out       <= rom_data_q;
                    sample_update    <= 1'b1;
                    sample_index_dbg <= rom_address;
                end
                else begin
                    sample_out       <= {DATA_W{1'b0}};
                    sample_index_dbg <= 9'd0;
                end
            end
        end
    end

endmodule
