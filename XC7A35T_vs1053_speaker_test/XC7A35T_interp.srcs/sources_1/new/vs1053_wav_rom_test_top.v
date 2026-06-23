`timescale 1ns / 1ps
//=============================================================
// 文件名       : vs1053_wav_rom_test_top.v
// 模块名       : vs1053_wav_rom_test_top
// 功能简述     : VS1053 WAV/PCM ROM 播放测试顶层。
//
//                本模块通过 FPGA SPI 初始化 VS1053，
//                然后通过 SDI 接口发送 WAV 文件头，
//                再持续发送 8kHz / 16bit / mono PCM 数据，
//                使 VS1053 从 PHONE / 耳机输出端播放音频。
//
// 当前用途     :
//                用于验证：
//                  FPGA ROM 音频数据
//                      -> SPI / SDI
//                      -> VS1053 PCM 解码
//                      -> 耳机输出
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-06-21
// 版本         : V2018.3
// 开发工具     : Vivado
//=============================================================

module vs1053_wav_rom_test_top (
    input  wire clk,
    input  wire sw0,          // A/B 音频选择：0 播放 A，1 播放 B

    output reg  vs_rst_n,     // VS1053 复位，低有效
    output reg  vs_xcs_n,     // SCI 控制接口片选，低有效
    output reg  vs_xdcs_n,    // SDI 音频数据接口片选，低有效

    output wire vs_sclk,      // SPI 时钟
    output wire vs_mosi,      // FPGA -> VS1053
    input  wire vs_dreq       // VS1053 数据请求，高有效
);

    //=========================================================
    // 1）基本延时参数
    //=========================================================
    localparam integer POR_CNT_MAX        = 2500000;  // 50ms
    localparam integer AFTER_RST_CNT_MAX  = 1000000;  // 20ms
    localparam integer POST_SCI_DELAY_MAX = 50000;    // 1ms

    reg [31:0] delay_cnt;
    reg [31:0] post_sci_delay_cnt;

    //=========================================================
    // 2）DREQ 输入同步
    //=========================================================
    reg [1:0] dreq_sync;

    always @(posedge clk) begin
        dreq_sync <= {dreq_sync[0], vs_dreq};
    end

    wire dreq_ok = dreq_sync[1];

    //=========================================================
    // sw0 输入同步
    //
    // sw0 来自拨码开关，用于选择播放 A / B 音频。
    // sw0 = 0：播放 A，粗糙版本；
    // sw0 = 1：播放 B，平滑版本。
    //=========================================================
    reg [1:0] sw0_sync;

    always @(posedge clk) begin
        sw0_sync <= {sw0_sync[0], sw0};
    end

    wire ab_sel = sw0_sync[1];

    //=========================================================
    // 3）SPI 单字节发送模块
    //
    // 这里使用独立命名的 SPI master，避免和之前 sine test
    // 文件中的同名模块发生冲突。
    //=========================================================
    reg        spi_start;
    reg [7:0]  spi_data_in;
    wire       spi_busy;
    wire       spi_done;

    vs1053_spi_byte_master_wav #(
        .CLK_DIV(25)      // 50MHz / (2*25) = 1MHz SPI
    ) u_vs1053_spi_byte_master_wav (
        .clk      (clk),
        .rst_n    (1'b1),

        .start    (spi_start),
        .data_in  (spi_data_in),
        .busy     (spi_busy),
        .done     (spi_done),

        .sclk     (vs_sclk),
        .mosi     (vs_mosi)
    );

    //=========================================================
    // 4）PCM 数据 ROM
    //
    // 数据格式：
    //   8 kHz
    //   16 bit signed
    //   mono
    //   little-endian
    //
    // ROM 每个地址存 1 byte。
    //=========================================================
    localparam integer PCM_DEPTH  = 8192;
    localparam integer PCM_ADDR_W = 13;

    //=========================================================
    // A/B 两段 PCM 数据 ROM
    //
    // A：粗糙版本
    // B：平滑版本
    //
    // 两段数据格式必须完全一致：
    //   8kHz / 16bit signed / mono / little-endian
    //=========================================================
    (* rom_style = "block" *)
    reg [7:0] pcm_rom_a [0:PCM_DEPTH-1];

    (* rom_style = "block" *)
    reg [7:0] pcm_rom_b [0:PCM_DEPTH-1];

    integer rom_i;

    initial begin
        for (rom_i = 0; rom_i < PCM_DEPTH; rom_i = rom_i + 1) begin
            pcm_rom_a[rom_i] = 8'h00;
            pcm_rom_b[rom_i] = 8'h00;
        end

        $readmemh("audio_A_raw_s16le_mono_8k_8192.mem",    pcm_rom_a);
        $readmemh("audio_B_smooth_s16le_mono_8k_8192.mem", pcm_rom_b);
    end

    reg [PCM_ADDR_W-1:0] pcm_addr;

    //=========================================================
    // 5）状态定义
    //=========================================================
    localparam [7:0] ST_RST_LOW          = 8'd0;
    localparam [7:0] ST_RST_HIGH_WAIT    = 8'd1;

    localparam [7:0] ST_WAIT_DREQ_MODE   = 8'd2;
    localparam [7:0] ST_WAIT_DREQ_CLKF   = 8'd3;
    localparam [7:0] ST_WAIT_DREQ_VOL    = 8'd4;

    localparam [7:0] ST_WAIT_DREQ_HEADER = 8'd5;
    localparam [7:0] ST_WAIT_DREQ_PCM    = 8'd6;

    localparam [7:0] ST_SEQ_PREP         = 8'd20;
    localparam [7:0] ST_SEQ_START_BYTE   = 8'd21;
    localparam [7:0] ST_SEQ_WAIT_BYTE    = 8'd22;
    localparam [7:0] ST_SEQ_END          = 8'd23;
    localparam [7:0] ST_SEQ_POST_DELAY   = 8'd24;

    localparam [7:0] ST_DONE             = 8'd100;

    reg [7:0] state;
    reg [7:0] next_state_after_seq;

    //=========================================================
    // 6）发送模式
    //
    // SEND_SCI：
    //   发送 4 字节 SCI 写命令。
    //
    // SEND_WAV_HEADER：
    //   发送 WAV 文件头。
    //
    // SEND_PCM：
    //   发送 PCM ROM 中的数据。
    //=========================================================
    localparam [1:0] SEND_SCI        = 2'd0;
    localparam [1:0] SEND_WAV_HEADER = 2'd1;
    localparam [1:0] SEND_PCM        = 2'd2;

    reg [1:0] send_mode;

    reg [2:0] seq_id;
    reg [5:0] seq_idx;
    reg [5:0] seq_len;

    reg [5:0] wav_header_idx;

    //=========================================================
    // 7）SCI 初始化序列
    //
    // SCI 写格式：
    //   0x02, address, data_high, data_low
    //=========================================================
    function [7:0] sci_seq_byte;
        input [2:0] id;
        input [5:0] idx;
        begin
            case (id)
                // SCI_MODE = 0x0800
                // SM_SDINEW = 1，新 SPI 模式
                3'd0: begin
                    case (idx)
                        6'd0: sci_seq_byte = 8'h02;
                        6'd1: sci_seq_byte = 8'h00;
                        6'd2: sci_seq_byte = 8'h08;
                        6'd3: sci_seq_byte = 8'h00;
                        default: sci_seq_byte = 8'h00;
                    endcase
                end

                // SCI_CLOCKF = 0x8800
                3'd1: begin
                    case (idx)
                        6'd0: sci_seq_byte = 8'h02;
                        6'd1: sci_seq_byte = 8'h03;
                        6'd2: sci_seq_byte = 8'h88;
                        6'd3: sci_seq_byte = 8'h00;
                        default: sci_seq_byte = 8'h00;
                    endcase
                end

                // SCI_VOL = 0x3030
                // 数值越大，音量越小。
                3'd2: begin
                    case (idx)
                        6'd0: sci_seq_byte = 8'h02;
                        6'd1: sci_seq_byte = 8'h0B;
                        6'd2: sci_seq_byte = 8'h30;
                        6'd3: sci_seq_byte = 8'h30;
                        default: sci_seq_byte = 8'h00;
                    endcase
                end

                default: begin
                    sci_seq_byte = 8'h00;
                end
            endcase
        end
    endfunction

    //=========================================================
    // 8）WAV 文件头
    //
    // 格式：
    //   RIFF
    //   ChunkSize      = 0xFFFFFFFF
    //   WAVE
    //   fmt
    //   PCM
    //   mono
    //   8000 Hz
    //   16 bit
    //   data
    //   SubChunk2Size  = 0xFFFFFFFF
    //
    // 发送完这个头以后，VS1053 会进入 PCM 解码模式。
    //=========================================================
    function [7:0] wav_header_byte;
        input [5:0] idx;
        begin
            case (idx)
                // "RIFF"
                6'd0 : wav_header_byte = 8'h52;
                6'd1 : wav_header_byte = 8'h49;
                6'd2 : wav_header_byte = 8'h46;
                6'd3 : wav_header_byte = 8'h46;

                // ChunkSize = 0xFFFFFFFF
                6'd4 : wav_header_byte = 8'hFF;
                6'd5 : wav_header_byte = 8'hFF;
                6'd6 : wav_header_byte = 8'hFF;
                6'd7 : wav_header_byte = 8'hFF;

                // "WAVE"
                6'd8 : wav_header_byte = 8'h57;
                6'd9 : wav_header_byte = 8'h41;
                6'd10: wav_header_byte = 8'h56;
                6'd11: wav_header_byte = 8'h45;

                // "fmt "
                6'd12: wav_header_byte = 8'h66;
                6'd13: wav_header_byte = 8'h6D;
                6'd14: wav_header_byte = 8'h74;
                6'd15: wav_header_byte = 8'h20;

                // SubChunk1Size = 16
                6'd16: wav_header_byte = 8'h10;
                6'd17: wav_header_byte = 8'h00;
                6'd18: wav_header_byte = 8'h00;
                6'd19: wav_header_byte = 8'h00;

                // AudioFormat = 1，PCM
                6'd20: wav_header_byte = 8'h01;
                6'd21: wav_header_byte = 8'h00;

                // NumChannels = 1，mono
                6'd22: wav_header_byte = 8'h01;
                6'd23: wav_header_byte = 8'h00;

                // SampleRate = 8000 = 0x00001F40，小端
                6'd24: wav_header_byte = 8'h40;
                6'd25: wav_header_byte = 8'h1F;
                6'd26: wav_header_byte = 8'h00;
                6'd27: wav_header_byte = 8'h00;

                // ByteRate = 8000 * 2 = 16000 = 0x00003E80，小端
                6'd28: wav_header_byte = 8'h80;
                6'd29: wav_header_byte = 8'h3E;
                6'd30: wav_header_byte = 8'h00;
                6'd31: wav_header_byte = 8'h00;

                // BlockAlign = 2
                6'd32: wav_header_byte = 8'h02;
                6'd33: wav_header_byte = 8'h00;

                // BitsPerSample = 16
                6'd34: wav_header_byte = 8'h10;
                6'd35: wav_header_byte = 8'h00;

                // "data"
                6'd36: wav_header_byte = 8'h64;
                6'd37: wav_header_byte = 8'h61;
                6'd38: wav_header_byte = 8'h74;
                6'd39: wav_header_byte = 8'h61;

                // SubChunk2Size = 0xFFFFFFFF
                6'd40: wav_header_byte = 8'hFF;
                6'd41: wav_header_byte = 8'hFF;
                6'd42: wav_header_byte = 8'hFF;
                6'd43: wav_header_byte = 8'hFF;

                default: wav_header_byte = 8'h00;
            endcase
        end
    endfunction

    //=========================================================
    // 9）主状态机
    //=========================================================
    always @(posedge clk) begin
        spi_start <= 1'b0;

        case (state)
            //=================================================
            // 硬件复位 VS1053
            //=================================================
            ST_RST_LOW: begin
                vs_rst_n  <= 1'b0;
                vs_xcs_n  <= 1'b1;
                vs_xdcs_n <= 1'b1;

                delay_cnt <= delay_cnt + 32'd1;

                if (delay_cnt >= POR_CNT_MAX) begin
                    delay_cnt <= 32'd0;
                    state     <= ST_RST_HIGH_WAIT;
                end
            end

            //=================================================
            // 释放复位后等待
            //=================================================
            ST_RST_HIGH_WAIT: begin
                vs_rst_n  <= 1'b1;
                vs_xcs_n  <= 1'b1;
                vs_xdcs_n <= 1'b1;

                delay_cnt <= delay_cnt + 32'd1;

                if (delay_cnt >= AFTER_RST_CNT_MAX) begin
                    delay_cnt <= 32'd0;
                    state     <= ST_WAIT_DREQ_MODE;
                end
            end

            //=================================================
            // 写 SCI_MODE
            //=================================================
            ST_WAIT_DREQ_MODE: begin
                if (dreq_ok) begin
                    send_mode            <= SEND_SCI;
                    seq_id               <= 3'd0;
                    seq_idx              <= 6'd0;
                    seq_len              <= 6'd4;
                    next_state_after_seq <= ST_WAIT_DREQ_CLKF;
                    state                <= ST_SEQ_PREP;
                end
            end

            //=================================================
            // 写 SCI_CLOCKF
            //=================================================
            ST_WAIT_DREQ_CLKF: begin
                if (dreq_ok) begin
                    send_mode            <= SEND_SCI;
                    seq_id               <= 3'd1;
                    seq_idx              <= 6'd0;
                    seq_len              <= 6'd4;
                    next_state_after_seq <= ST_WAIT_DREQ_VOL;
                    state                <= ST_SEQ_PREP;
                end
            end

            //=================================================
            // 写 SCI_VOL
            //=================================================
            ST_WAIT_DREQ_VOL: begin
                if (dreq_ok) begin
                    send_mode            <= SEND_SCI;
                    seq_id               <= 3'd2;
                    seq_idx              <= 6'd0;
                    seq_len              <= 6'd4;
                    next_state_after_seq <= ST_WAIT_DREQ_HEADER;
                    state                <= ST_SEQ_PREP;
                end
            end

            //=================================================
            // 发送 WAV 头
            //
            // DREQ 高时，VS1053 至少可以接收 32 字节 SDI 数据。
            // WAV 头总共 44 字节，所以分两次：
            //   第一次 32 字节；
            //   第二次 12 字节。
            //=================================================
            ST_WAIT_DREQ_HEADER: begin
                if (dreq_ok) begin
                    send_mode <= SEND_WAV_HEADER;
                    seq_idx   <= 6'd0;

                    if (wav_header_idx == 6'd0) begin
                        seq_len              <= 6'd32;
                        next_state_after_seq <= ST_WAIT_DREQ_HEADER;
                    end
                    else begin
                        seq_len              <= 6'd12;
                        next_state_after_seq <= ST_WAIT_DREQ_PCM;
                    end

                    state <= ST_SEQ_PREP;
                end
            end

            //=================================================
            // 发送 PCM 数据
            //
            // 每次 DREQ 高，发送 32 字节。
            // 播放到 ROM 末尾后重新从 0 地址循环。
            //=================================================
            ST_WAIT_DREQ_PCM: begin
                if (dreq_ok) begin
                    send_mode            <= SEND_PCM;
                    seq_idx              <= 6'd0;
                    seq_len              <= 6'd32;
                    next_state_after_seq <= ST_WAIT_DREQ_PCM;
                    state                <= ST_SEQ_PREP;
                end
            end

            //=================================================
            // 根据发送模式选择片选
            //=================================================
            ST_SEQ_PREP: begin
                if (send_mode == SEND_SCI) begin
                    vs_xcs_n  <= 1'b0;
                    vs_xdcs_n <= 1'b1;
                end
                else begin
                    vs_xcs_n  <= 1'b1;
                    vs_xdcs_n <= 1'b0;
                end

                state <= ST_SEQ_START_BYTE;
            end

            //=================================================
            // 启动当前字节发送
            //=================================================
            ST_SEQ_START_BYTE: begin
                if (!spi_busy) begin
                    case (send_mode)
                        SEND_SCI: begin
                            spi_data_in <= sci_seq_byte(seq_id, seq_idx);
                        end

                        SEND_WAV_HEADER: begin
                            spi_data_in <= wav_header_byte(wav_header_idx);
                        end

                        SEND_PCM: begin
                            if (ab_sel)
                                spi_data_in <= pcm_rom_b[pcm_addr];   // sw0 = 1，播放 B 平滑版本
                            else
                                spi_data_in <= pcm_rom_a[pcm_addr];   // sw0 = 0，播放 A 粗糙版本
                        end

                        default: begin
                            spi_data_in <= 8'h00;
                        end
                    endcase

                    spi_start <= 1'b1;
                    state     <= ST_SEQ_WAIT_BYTE;
                end
            end

            //=================================================
            // 等待当前字节发送完成，并更新地址
            //=================================================
            ST_SEQ_WAIT_BYTE: begin
                if (spi_done) begin
                    if (send_mode == SEND_WAV_HEADER) begin
                        wav_header_idx <= wav_header_idx + 6'd1;
                    end
                    else if (send_mode == SEND_PCM) begin
                        if (pcm_addr == PCM_DEPTH - 1)
                            pcm_addr <= {PCM_ADDR_W{1'b0}};
                        else
                            pcm_addr <= pcm_addr + 1'b1;
                    end

                    if (seq_idx == seq_len - 1'b1) begin
                        state <= ST_SEQ_END;
                    end
                    else begin
                        seq_idx <= seq_idx + 1'b1;
                        state   <= ST_SEQ_START_BYTE;
                    end
                end
            end

            //=================================================
            // 一个序列发送完毕，释放片选
            //=================================================
            ST_SEQ_END: begin
                vs_xcs_n  <= 1'b1;
                vs_xdcs_n <= 1'b1;

                if (send_mode == SEND_SCI) begin
                    post_sci_delay_cnt <= 32'd0;
                    state              <= ST_SEQ_POST_DELAY;
                end
                else begin
                    state <= next_state_after_seq;
                end
            end

            //=================================================
            // SCI 命令后延时
            //=================================================
            ST_SEQ_POST_DELAY: begin
                vs_xcs_n  <= 1'b1;
                vs_xdcs_n <= 1'b1;

                if (post_sci_delay_cnt >= POST_SCI_DELAY_MAX) begin
                    post_sci_delay_cnt <= 32'd0;
                    state              <= next_state_after_seq;
                end
                else begin
                    post_sci_delay_cnt <= post_sci_delay_cnt + 32'd1;
                end
            end

            ST_DONE: begin
                vs_xcs_n  <= 1'b1;
                vs_xdcs_n <= 1'b1;
                vs_rst_n  <= 1'b1;
                state     <= ST_DONE;
            end

            default: begin
                state <= ST_RST_LOW;
            end
        endcase
    end

    //=========================================================
    // 10）初始化
    //=========================================================
    initial begin
        state                = ST_RST_LOW;
        next_state_after_seq = ST_RST_LOW;

        delay_cnt          = 32'd0;
        post_sci_delay_cnt = 32'd0;

        dreq_sync = 2'b00;
        sw0_sync  = 2'b00;

        vs_rst_n  = 1'b0;
        vs_xcs_n  = 1'b1;
        vs_xdcs_n = 1'b1;

        spi_start  = 1'b0;
        spi_data_in = 8'h00;

        send_mode = SEND_SCI;

        seq_id  = 3'd0;
        seq_idx = 6'd0;
        seq_len = 6'd0;

        wav_header_idx = 6'd0;
        pcm_addr       = {PCM_ADDR_W{1'b0}};
    end

endmodule


//=============================================================
// 模块名       : vs1053_spi_byte_master_wav
// 功能简述     : VS1053 SPI 单字节发送模块。
//=============================================================
module vs1053_spi_byte_master_wav #(
    parameter CLK_DIV = 25
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       start,
    input  wire [7:0] data_in,

    output reg        busy,
    output reg        done,

    output reg        sclk,
    output reg        mosi
);

    reg [15:0] div_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  tx_shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy     <= 1'b0;
            done     <= 1'b0;

            sclk     <= 1'b0;
            mosi     <= 1'b0;

            div_cnt  <= 16'd0;
            bit_idx  <= 3'd7;
            tx_shift <= 8'h00;
        end
        else begin
            done <= 1'b0;

            if (!busy) begin
                sclk    <= 1'b0;
                div_cnt <= 16'd0;

                if (start) begin
                    busy     <= 1'b1;
                    tx_shift <= data_in;
                    bit_idx  <= 3'd7;
                    mosi     <= data_in[7];
                end
            end
            else begin
                if (div_cnt == CLK_DIV - 1) begin
                    div_cnt <= 16'd0;

                    if (sclk == 1'b0) begin
                        sclk <= 1'b1;
                    end
                    else begin
                        sclk <= 1'b0;

                        if (bit_idx == 3'd0) begin
                            busy <= 1'b0;
                            done <= 1'b1;
                            mosi <= 1'b0;
                        end
                        else begin
                            bit_idx <= bit_idx - 1'b1;
                            mosi    <= tx_shift[bit_idx - 1'b1];
                        end
                    end
                end
                else begin
                    div_cnt <= div_cnt + 16'd1;
                end
            end
        end
    end

endmodule

