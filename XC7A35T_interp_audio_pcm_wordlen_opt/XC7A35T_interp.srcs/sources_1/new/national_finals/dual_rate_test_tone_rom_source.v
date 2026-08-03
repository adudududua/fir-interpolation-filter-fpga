`timescale 1ns / 1ps

//=============================================================
// 文件名       : dual_rate_test_tone_rom_source.v
// 模块名       : dual_rate_test_tone_rom_source
// 功能简述     : 共用一块 Block RAM 保存 44.1/48 kHz 两组 15 kHz、
//                24 bit signed、0.50FS 板级测试正弦。
//
//                44.1 kHz: 地址   0..146，共 147 点、50 个周期
//                48   kHz: 地址 147..162，共  16 点、 5 个周期
//
//                两组序列打包在同一个 256x24 ROM，避免为了第二
//                采样率额外消耗一块 RAMB18。
//=============================================================

module dual_rate_test_tone_rom_source #(
    parameter MEM_FILE = "nf_sine_15k_dual_rate_24bit_256.mem"
)(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       sample_ce,
    input  wire                       family_48k,
    output reg  signed [23:0]         sample_out,
    output reg                        sample_update,
    output reg  [7:0]                 sample_addr_dbg
);

    localparam [7:0] ADDR_44K1_FIRST = 8'd0;
    localparam [7:0] ADDR_44K1_LAST  = 8'd146;
    localparam [7:0] ADDR_48K_FIRST  = 8'd147;
    localparam [7:0] ADDR_48K_LAST   = 8'd162;

    // Pack the next ROM address into the otherwise unused upper byte of each
    // 36-bit RAMB18 word.  This removes the external increment, two range
    // comparators and family-dependent wrap mux without adding a BRAM.
    (* rom_style = "block" *)
    reg [31:0] pcm_rom [0:255];
    reg [7:0] rd_addr;
    reg [31:0] rom_word_q;
    integer init_addr;

    initial begin
        $readmemh(MEM_FILE, pcm_rom);
        for (init_addr = 0; init_addr < 256;
             init_addr = init_addr + 1) begin
            if (init_addr < ADDR_44K1_LAST)
                pcm_rom[init_addr][31:24] = init_addr + 1;
            else if (init_addr == ADDR_44K1_LAST)
                pcm_rom[init_addr][31:24] = ADDR_44K1_FIRST;
            else if (init_addr < ADDR_48K_FIRST)
                pcm_rom[init_addr][31:24] = ADDR_44K1_FIRST;
            else if (init_addr < ADDR_48K_LAST)
                pcm_rom[init_addr][31:24] = init_addr + 1;
            else
                pcm_rom[init_addr][31:24] = ADDR_48K_FIRST;
        end
    end

    // 保持纯同步读形式，便于 Vivado 2018.3 推断 RAMB18E1。
    always @(posedge clk) begin
        rom_word_q <= pcm_rom[rd_addr];
    end

    // 地址寄存器直接驱动 BRAM 地址脚，使用同步复位可避免异步控制在
    // 复位边沿附近破坏 ROM 读地址。顶层在采样率家族切换时会把复位保持
    // 数百个音频时钟周期，因此这里不需要异步复位。
    always @(posedge clk) begin
        if (!rst_n) begin
            rd_addr <= family_48k ? ADDR_48K_FIRST : ADDR_44K1_FIRST;
            sample_out <= 24'sd0;
            sample_update <= 1'b0;
            sample_addr_dbg <= 8'd0;
        end
        else begin
            sample_update <= 1'b0;
            if (sample_ce) begin
                sample_out <= rom_word_q[23:0];
                sample_update <= 1'b1;
                sample_addr_dbg <= rd_addr;
                rd_addr <= rom_word_q[31:24];
            end
        end
    end

endmodule
