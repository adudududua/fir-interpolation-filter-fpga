`timescale 1ns / 1ps
//=============================================================
// 文件名       : audio_nco_sine_source.v
// 模块名       : audio_nco_sine_source
// 功能简述     : 44.1kHz 采样、1kHz～20kHz 可调的 24bit 正弦 NCO。
//                相位累加器在 sample_ce 有效时更新，频率切换时保持相位连续；
//                256 点正弦查找表使用 Block RAM，输出峰值为 0.50FS。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-18
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-18：新增 1kHz～20kHz 可调音频 NCO 输入源。
//                2026-07-18：增加独立无复位 ROM 地址寄存器，避免
//                            频率/复位组合逻辑折叠到 BRAM 地址端。
//=============================================================

module audio_nco_sine_source #(
    parameter DATA_W   = 24,
    parameter ADDR_W   = 8,
    parameter MEM_FILE = "nco_sine_0p50fs_256.mem"
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      sample_ce,
    input  wire [4:0]                tone_khz,

    output reg  signed [DATA_W-1:0]  sample_out,
    output reg                       sample_update,
    output reg  [ADDR_W-1:0]         phase_addr_dbg
);

    //=========================================================
    // 1）1kHz～20kHz 相位步进字
    //
    // phase_increment = round(frequency / 44100 * 2^32)
    //=========================================================
    function [31:0] phase_increment;
        input [4:0] frequency_khz;
        begin
            case (frequency_khz)
                5'd1:    phase_increment = 32'h05CE13BD;
                5'd2:    phase_increment = 32'h0B9C2779;
                5'd3:    phase_increment = 32'h116A3B36;
                5'd4:    phase_increment = 32'h17384EF3;
                5'd5:    phase_increment = 32'h1D0662AF;
                5'd6:    phase_increment = 32'h22D4766C;
                5'd7:    phase_increment = 32'h28A28A29;
                5'd8:    phase_increment = 32'h2E709DE5;
                5'd9:    phase_increment = 32'h343EB1A2;
                5'd10:   phase_increment = 32'h3A0CC55F;
                5'd11:   phase_increment = 32'h3FDAD91B;
                5'd12:   phase_increment = 32'h45A8ECD8;
                5'd13:   phase_increment = 32'h4B770095;
                5'd14:   phase_increment = 32'h51451451;
                5'd15:   phase_increment = 32'h5713280E;
                5'd16:   phase_increment = 32'h5CE13BCB;
                5'd17:   phase_increment = 32'h62AF4F87;
                5'd18:   phase_increment = 32'h687D6344;
                5'd19:   phase_increment = 32'h6E4B7701;
                5'd20:   phase_increment = 32'h74198ABD;
                default: phase_increment = 32'h5713280E;
            endcase
        end
    endfunction

    //=========================================================
    // 2）32bit 相位累加器和 256 点同步正弦 ROM
    //=========================================================
    (* use_dsp = "no" *) reg [31:0] phase_accumulator;
    wire [31:0] phase_next;

    assign phase_next = phase_accumulator + phase_increment(tone_khz);

    (* rom_style = "block" *)
    reg signed [DATA_W-1:0] sine_rom [0:(1 << ADDR_W)-1];
    reg signed [DATA_W-1:0] rom_data_q;
    (* keep = "true" *) reg [ADDR_W-1:0] rom_address = {ADDR_W{1'b0}};

    initial begin
        $readmemh(MEM_FILE, sine_rom);
    end

    // 独立的无复位同步读进程便于 Vivado 2018.3 推断 Block RAM ROM。
    always @(posedge clk) begin
        rom_data_q <= sine_rom[rom_address];
    end

    // ROM 地址寄存器不带复位控制，BRAM 地址端只连接寄存器 Q。
    // 每次输出当前样点时，提前装载下一相位地址供后续 128 拍读取。
    always @(posedge clk) begin
        if (sample_ce)
            rom_address <= phase_next[31:32-ADDR_W];
    end

    //=========================================================
    // 3）44.1kHz 采样更新
    //=========================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            phase_accumulator <= 32'd0;
            sample_out        <= {DATA_W{1'b0}};
            sample_update     <= 1'b0;
            phase_addr_dbg    <= {ADDR_W{1'b0}};
        end
        else begin
            sample_update <= 1'b0;

            if (sample_ce) begin
                sample_out        <= rom_data_q;
                sample_update     <= 1'b1;
                phase_addr_dbg    <= phase_accumulator[31:32-ADDR_W];
                phase_accumulator <= phase_next;
            end
        end
    end

endmodule
