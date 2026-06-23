`default_nettype none
`timescale 1ns / 1ps

//=============================================================
// 文件名       : vs1053_fpga_48k_interp_ab_top.v
// 模块名       : vs1053_fpga_48k_interp_ab_top
// 功能简述     : 符合赛题输入规格的 VS1053 A/B 听感辅助展示顶层。
//                本模块读取 48kHz / 24bit signed 音频 ROM，
//                在 FPGA 内部实时生成两路听感对比音频：
//
//                A 路：低质量保持重构效果。
//                      从同一 48kHz 输入音频中抽取部分采样，
//                      并在 FPGA 内部进行保持输出，
//                      用于模拟未经 FIR 插值滤波的粗糙重构效果。
//
//                B 路：FPGA 内部 FIR 插值平滑重构效果。
//                      调用已有 interp4_top_symm_ce 模块，
//                      对同一输入音频构造的低速参考流进行 4x FIR 插值，
//                      用于展示 FIR 插值滤波后的平滑重构效果。
//
//                最终 FPGA 将 sw0 选择后的 24bit 音频结果截位为
//                16bit signed PCM，并通过 VS1053 的 SDI 接口发送。
//                VS1053 只负责 PCM 音频播放，A/B 差异由 FPGA 内部产生。
//
//                该模块属于辅助听感展示支路，不替代 AD9708 + 示波器
//                对 4x / 8x / 128x 输出采样率的主验证。
//
// 当前默认配置：
//                  输入音频采样率：48kHz
//                  输入音频位宽  ：24bit signed
//                  输入 ROM 文件 ：audio_in_48k_24bit_4096.mem
//                  VS1053 输出格式：48kHz / 16bit signed / mono PCM
//                  sw0 = 0       ：播放 A 路低质量保持重构效果
//                  sw0 = 1       ：播放 B 路 FPGA FIR 插值重构效果
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-06-21
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-06-21：新增符合赛题 48kHz / 24bit 输入规格的
//                            VS1053 A/B 听感辅助展示顶层。
//=============================================================

module vs1053_fpga_48k_interp_ab_top (
    input  wire clk,          // 板载 50MHz 时钟
    input  wire sw0,          // A/B 选择：0=A 路保持重构，1=B 路 FIR 插值

    output reg  vs_rst_n,     // VS1053 复位，低有效
    output reg  vs_xcs_n,     // VS1053 SCI 控制接口片选，低有效
    output reg  vs_xdcs_n,    // VS1053 SDI 音频数据接口片选，低有效

    output wire vs_sclk,      // VS1053 SPI 时钟
    output wire vs_mosi,      // FPGA -> VS1053 SPI 数据
    input  wire vs_dreq       // VS1053 数据请求，高有效
);

    //=========================================================
    // 1）基本参数
    //=========================================================
    localparam integer CLK_FREQ_HZ        = 50000000; // FPGA 板载时钟 50MHz
    localparam integer FS_PLAY_HZ         = 48000;    // VS1053 播放采样率 48kHz

    localparam integer POR_CNT_MAX        = 2500000;  // 50ms 复位保持时间
    localparam integer AFTER_RST_CNT_MAX  = 1000000;  // 20ms 复位释放后等待
    localparam integer POST_SCI_DELAY_MAX = 50000;    // 1ms SCI 命令后等待

    localparam integer ROM_DEPTH          = 4096;     // 音频 ROM 采样点数
    localparam integer ROM_ADDR_W         = 12;       // 4096 点地址宽度

    reg [31:0] delay_cnt;
    reg [31:0] post_sci_delay_cnt;

    //=========================================================
    // 2）DREQ 与 sw0 输入同步
    //
    // vs_dreq：
    //   来自 VS1053，是外部异步输入。
    //
    // sw0：
    //   来自拨码开关，也是外部异步输入。
    //
    // 这里都先同步到 FPGA clk 时钟域。
    //=========================================================
    reg [1:0] dreq_sync;
    reg [1:0] sw0_sync;

    always @(posedge clk) begin
        dreq_sync <= {dreq_sync[0], vs_dreq};
        sw0_sync  <= {sw0_sync[0],  sw0};
    end

    wire dreq_ok;
    wire ab_sel;

    assign dreq_ok = dreq_sync[1];
    assign ab_sel  = sw0_sync[1];

    //=========================================================
    // 3）SPI 单字节发送模块
    //
    // CLK_DIV = 12：
    //   SPI SCLK 频率约为 50MHz / (2*12) = 2.08MHz。
    //
    // 48kHz / 16bit / mono PCM 数据率：
    //   48000 * 2 = 96000 Byte/s。
    //
    // 2.08MHz SPI 足够发送该音频流。
    //=========================================================
    reg        spi_start;
    reg [7:0]  spi_data_in;
    wire       spi_busy;
    wire       spi_done;

    vs1053_spi_byte_master_48k_ab #(
        .CLK_DIV(12)
    ) u_vs1053_spi_byte_master_48k_ab (
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
    // 4）48kHz / 24bit signed 输入音频 ROM
    //
    // ROM 文件：
    //   audio_in_48k_24bit_4096.mem
    //
    // 每行一个 24bit 二进制补码数据。
    //=========================================================
    (* rom_style = "block" *)
    reg signed [23:0] audio_rom [0:ROM_DEPTH-1];

    integer rom_i;

    initial begin
        for (rom_i = 0; rom_i < ROM_DEPTH; rom_i = rom_i + 1) begin
            audio_rom[rom_i] = 24'sd0;
        end

        $readmemh("audio_in_48k_24bit_4096.mem", audio_rom);
    end

    reg [ROM_ADDR_W-1:0] rom_addr;
    reg signed [23:0]    rom_sample_reg;

    // 同步读 ROM。
    // rom_sample_reg 会在 rom_addr 给出后一个 clk 周期更新。
    always @(posedge clk) begin
        rom_sample_reg <= audio_rom[rom_addr];
    end

    wire signed [23:0] rom_sample_now;
    assign rom_sample_now = rom_sample_reg;

    //=========================================================
    // 5）48kHz 音频采样节拍生成
    //
    // 50MHz 不能被 48kHz 整除，因此使用相位累加器产生
    // 平均 48kHz 的 sample_tick。
    //
    // audio_run：
    //   VS1053 初始化完成并发送 WAV 头之后拉高。
    //=========================================================
    reg [31:0] sample_acc;
    reg        audio_run;

    localparam [32:0] FS_STEP = FS_PLAY_HZ;
    localparam [32:0] CLK_MOD = CLK_FREQ_HZ;

    wire [32:0] sample_acc_next;
    wire        sample_tick;

    assign sample_acc_next = {1'b0, sample_acc} + FS_STEP;
    assign sample_tick     = audio_run && (sample_acc_next >= CLK_MOD);

    always @(posedge clk) begin
        if (!audio_run) begin
            sample_acc <= 32'd0;
        end
        else begin
            if (sample_tick) begin
                sample_acc <= sample_acc_next - CLK_MOD;
            end
            else begin
                sample_acc <= sample_acc_next[31:0];
            end
        end
    end

    //=========================================================
    // 6）构造 A/B 所需的低质量参考流
    //
    // 原始输入 ROM 是 48kHz / 24bit，符合赛题输入规格。
    //
    // 为了让听感 A/B 差异明显，本模块在辅助听感支路中
    // 从同一个 48kHz 输入中每 4 个点取 1 个点，
    // 构造等效低速参考流：
    //
    //   48kHz 输入 ROM
    //      ↓ 每 4 点取 1 点
    //   12kHz 参考流
    //
    // A 路：
    //   12kHz 参考流保持 4 个 48kHz 周期输出。
    //
    // B 路：
    //   12kHz 参考流送入 interp4_top_symm_ce，
    //   在 FPGA 内部做 4x FIR 插值，回到 48kHz 播放。
    //
    // 注意：
    //   该处理用于 VS1053 听感辅助展示。
    //   主赛题 48kHz -> 192kHz / 384kHz / 6.144MHz
    //   仍以前面的 AD9708 + 示波器支路验证。
    //=========================================================
    reg [1:0] phase4;

    reg signed [23:0] hold_sample24;

    wire interp_x_valid;
    wire signed [23:0] interp_x_in;

    assign interp_x_valid = sample_tick && (phase4 == 2'd0);
    assign interp_x_in    = rom_sample_now;

    always @(posedge clk) begin
        if (!audio_run) begin
            phase4        <= 2'd0;
            rom_addr      <= {ROM_ADDR_W{1'b0}};
            hold_sample24 <= 24'sd0;
        end
        else if (sample_tick) begin
            // 48kHz 播放节拍下，ROM 地址每个采样点前进一次
            if (rom_addr == ROM_DEPTH - 1) begin
                rom_addr <= {ROM_ADDR_W{1'b0}};
            end
            else begin
                rom_addr <= rom_addr + 1'b1;
            end

            // 每 4 个 48kHz 点取 1 个作为参考采样
            if (phase4 == 2'd0) begin
                hold_sample24 <= rom_sample_now;
            end

            phase4 <= phase4 + 2'd1;
        end
    end

    //=========================================================
    // 7）B 路：调用已有 4x FIR 插值模块
    //
    // interp4_top_symm_ce 接口含义：
    //
    //   ce_out：
    //     输出采样使能，这里为 48kHz sample_tick。
    //
    //   x_in_valid：
    //     输入采样有效，这里每 4 个输出采样点有效一次，
    //     等效为 12kHz -> 48kHz 的 4x 插值。
    //
    //   y_out：
    //     4x FIR 插值后的 24bit 输出结果。
    //=========================================================
    wire signed [23:0] interp_y24;
    wire               interp_y_valid;

    wire [1:0]         phase_dbg_unused;
    wire signed [23:0] fir_in_dbg_unused;
    wire               fir_in_valid_dbg_unused;

    interp4_top_symm_ce #(
        .DATA_W  (24),
        .COEFF_W (18),
        .ACC_W   (56),
        .NTAPS   (155)
    ) u_interp4_top_symm_ce (
        .clk              (clk),
        .rst_n            (vs_rst_n),

        .ce_out           (sample_tick),

        .x_in             (interp_x_in),
        .x_in_valid       (interp_x_valid),

        .y_out            (interp_y24),
        .y_out_valid      (interp_y_valid),

        .phase_dbg        (phase_dbg_unused),
        .fir_in_dbg       (fir_in_dbg_unused),
        .fir_in_valid_dbg (fir_in_valid_dbg_unused)
    );

    reg signed [23:0] interp_sample24;

    always @(posedge clk) begin
        if (!audio_run) begin
            interp_sample24 <= 24'sd0;
        end
        else if (interp_y_valid) begin
            interp_sample24 <= interp_y24;
        end
    end

    //=========================================================
    // 8）A/B 选择与 16bit PCM 截位
    //
    // A 路：
    //   使用 hold_sample24。
    //
    // B 路：
    //   使用 interp_sample24。
    //
    // VS1053 WAV/PCM 输出格式选择 16bit signed mono，
    // 因此这里将 24bit signed 截取高 16 位。
    //=========================================================
    wire signed [23:0] a_sample24_raw;
    wire signed [23:0] a_sample24;
    wire signed [23:0] b_sample24;
    wire signed [23:0] selected_sample24;
    wire signed [15:0] selected_sample16;

    // A 路原始保持重构结果
    assign a_sample24_raw = hold_sample24;

    // A 路音量略微衰减到约 0.75 倍，避免因为更响而影响听感判断
    assign a_sample24 = (a_sample24_raw >>> 1) + (a_sample24_raw >>> 2);

    // B 路保持 FIR 插值输出原幅度
    assign b_sample24 = interp_sample24;

    // sw0 = 0：A 路；sw0 = 1：B 路
    assign selected_sample24 = ab_sel ? b_sample24 : a_sample24;

    // 24bit signed 截成 16bit signed PCM
    assign selected_sample16 = selected_sample24[23:8];

    //=========================================================
    // 9）WAV 文件头查表函数
    //
    // WAV 格式：
    //   48kHz
    //   16bit signed PCM
    //   mono
    //
    // 关键字段：
    //   SampleRate = 48000 = 0x0000BB80
    //   ByteRate   = 48000 * 1 * 16 / 8 = 96000 = 0x00017700
    //   BlockAlign = 2
    //
    // ChunkSize 和 SubChunk2Size 使用 0xFFFFFFFF，
    // 用于流式播放。
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

                // SampleRate = 48000 = 0x0000BB80，小端
                6'd24: wav_header_byte = 8'h80;
                6'd25: wav_header_byte = 8'hBB;
                6'd26: wav_header_byte = 8'h00;
                6'd27: wav_header_byte = 8'h00;

                // ByteRate = 96000 = 0x00017700，小端
                6'd28: wav_header_byte = 8'h00;
                6'd29: wav_header_byte = 8'h77;
                6'd30: wav_header_byte = 8'h01;
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
    // 10）SCI 初始化序列查表函数
    //
    // SCI 写格式：
    //   0x02, register_address, data_high, data_low
    //
    // 当前初始化：
    //   SCI_MODE   = 0x0800，SM_SDINEW，新 SPI 模式
    //   SCI_CLOCKF = 0x8800，提高 VS1053 内部时钟
    //   SCI_VOL    = 0x3030，中等偏小音量
    //=========================================================
    function [7:0] sci_seq_byte;
        input [2:0] id;
        input [2:0] idx;
        begin
            case (id)
                // SCI_MODE = 0x0800
                3'd0: begin
                    case (idx)
                        3'd0: sci_seq_byte = 8'h02;
                        3'd1: sci_seq_byte = 8'h00;
                        3'd2: sci_seq_byte = 8'h08;
                        3'd3: sci_seq_byte = 8'h00;
                        default: sci_seq_byte = 8'h00;
                    endcase
                end

                // SCI_CLOCKF = 0x8800
                3'd1: begin
                    case (idx)
                        3'd0: sci_seq_byte = 8'h02;
                        3'd1: sci_seq_byte = 8'h03;
                        3'd2: sci_seq_byte = 8'h88;
                        3'd3: sci_seq_byte = 8'h00;
                        default: sci_seq_byte = 8'h00;
                    endcase
                end

                // SCI_VOL = 0x3030
                3'd2: begin
                    case (idx)
                        3'd0: sci_seq_byte = 8'h02;
                        3'd1: sci_seq_byte = 8'h0B;
                        3'd2: sci_seq_byte = 8'h30;
                        3'd3: sci_seq_byte = 8'h30;
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
    // 11）主状态机定义
    //=========================================================
    localparam [7:0] ST_RST_LOW          = 8'd0;
    localparam [7:0] ST_RST_HIGH_WAIT    = 8'd1;

    localparam [7:0] ST_WAIT_DREQ_MODE   = 8'd2;
    localparam [7:0] ST_WAIT_DREQ_CLKF   = 8'd3;
    localparam [7:0] ST_WAIT_DREQ_VOL    = 8'd4;

    localparam [7:0] ST_WAIT_DREQ_HEADER = 8'd5;

    localparam [7:0] ST_SEQ_PREP         = 8'd20;
    localparam [7:0] ST_SEQ_START_BYTE   = 8'd21;
    localparam [7:0] ST_SEQ_WAIT_BYTE    = 8'd22;
    localparam [7:0] ST_SEQ_END          = 8'd23;
    localparam [7:0] ST_SEQ_POST_DELAY   = 8'd24;

    localparam [7:0] ST_STREAM_IDLE      = 8'd40;
    localparam [7:0] ST_STREAM_WAIT_BYTE = 8'd41;

    localparam [1:0] SEND_SCI            = 2'd0;
    localparam [1:0] SEND_WAV_HEADER     = 2'd1;

    reg [7:0] state;
    reg [7:0] next_state_after_seq;

    reg [1:0] send_mode;
    reg [2:0] seq_id;
    reg [5:0] seq_idx;
    reg [5:0] seq_len;
    reg [5:0] wav_header_idx;

    reg signed [15:0] pending_sample16;
    reg               sample_pending;
    reg               sample_byte_sel;   // 0：低字节；1：高字节

    //=========================================================
    // 12）主状态机
    //=========================================================
    always @(posedge clk) begin
        spi_start <= 1'b0;

        case (state)
            //=================================================
            // 硬件复位 VS1053
            //=================================================
            ST_RST_LOW: begin
                audio_run <= 1'b0;

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
                audio_run <= 1'b0;

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
            // DREQ 高时，VS1053 至少能接收 32 字节 SDI 数据。
            // WAV 头 44 字节，因此分为：
            //   第一次：32 字节
            //   第二次：12 字节
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
                        next_state_after_seq <= ST_STREAM_IDLE;
                    end

                    state <= ST_SEQ_PREP;
                end
            end

            //=================================================
            // 准备发送 SCI 或 WAV 头
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
                    if (send_mode == SEND_SCI) begin
                        spi_data_in <= sci_seq_byte(seq_id, seq_idx[2:0]);
                    end
                    else begin
                        spi_data_in <= wav_header_byte(wav_header_idx);
                    end

                    spi_start <= 1'b1;
                    state     <= ST_SEQ_WAIT_BYTE;
                end
            end

            //=================================================
            // 等待当前字节发送完成
            //=================================================
            ST_SEQ_WAIT_BYTE: begin
                if (spi_done) begin
                    if (send_mode == SEND_WAV_HEADER) begin
                        wav_header_idx <= wav_header_idx + 6'd1;
                    end

                    if (seq_idx == seq_len - 1'b1) begin
                        state <= ST_SEQ_END;
                    end
                    else begin
                        seq_idx <= seq_idx + 6'd1;
                        state   <= ST_SEQ_START_BYTE;
                    end
                end
            end

            //=================================================
            // 一个 SCI / WAV 头序列发送完成
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

            //=================================================
            // 实时 PCM 播放空闲状态
            //
            // 每当 sample_tick 到来，锁存一个新的 16bit PCM 样本。
            // 然后根据 DREQ 状态，把该样本拆成低字节、高字节
            // 通过 SDI 发送给 VS1053。
            //=================================================
            ST_STREAM_IDLE: begin
                audio_run <= 1'b1;

                vs_xcs_n  <= 1'b1;
                vs_xdcs_n <= 1'b1;

                if ((!sample_pending) && sample_tick) begin
                    pending_sample16 <= selected_sample16;
                    sample_byte_sel  <= 1'b0;
                    sample_pending   <= 1'b1;
                end

                if (sample_pending && dreq_ok && (!spi_busy)) begin
                    vs_xdcs_n <= 1'b0;

                    if (sample_byte_sel == 1'b0) begin
                        spi_data_in <= pending_sample16[7:0];
                    end
                    else begin
                        spi_data_in <= pending_sample16[15:8];
                    end

                    spi_start <= 1'b1;
                    state     <= ST_STREAM_WAIT_BYTE;
                end
            end

            //=================================================
            // 等待 PCM 字节发送完成
            //=================================================
            ST_STREAM_WAIT_BYTE: begin
                if (spi_done) begin
                    vs_xdcs_n <= 1'b1;

                    if (sample_byte_sel == 1'b0) begin
                        sample_byte_sel <= 1'b1;
                        state           <= ST_STREAM_IDLE;
                    end
                    else begin
                        sample_byte_sel <= 1'b0;
                        sample_pending  <= 1'b0;
                        state           <= ST_STREAM_IDLE;
                    end
                end
            end

            default: begin
                state <= ST_RST_LOW;
            end
        endcase
    end

    //=========================================================
    // 13）初始化
    //=========================================================
    initial begin
        delay_cnt          = 32'd0;
        post_sci_delay_cnt = 32'd0;

        dreq_sync = 2'b00;
        sw0_sync  = 2'b00;

        vs_rst_n  = 1'b0;
        vs_xcs_n  = 1'b1;
        vs_xdcs_n = 1'b1;

        spi_start  = 1'b0;
        spi_data_in = 8'h00;

        sample_acc = 32'd0;
        audio_run  = 1'b0;

        rom_addr       = {ROM_ADDR_W{1'b0}};
        rom_sample_reg = 24'sd0;

        phase4        = 2'd0;
        hold_sample24 = 24'sd0;

        interp_sample24 = 24'sd0;

        state                = ST_RST_LOW;
        next_state_after_seq = ST_RST_LOW;

        send_mode      = SEND_SCI;
        seq_id         = 3'd0;
        seq_idx        = 6'd0;
        seq_len        = 6'd0;
        wav_header_idx = 6'd0;

        pending_sample16 = 16'sd0;
        sample_pending   = 1'b0;
        sample_byte_sel  = 1'b0;
    end

endmodule

`default_nettype wire

