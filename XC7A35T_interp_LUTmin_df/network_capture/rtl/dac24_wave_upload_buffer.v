`timescale 1ns / 1ps

//=============================================================
// 文件名       : dac24_wave_upload_buffer.v
// 模块名       : dac24_wave_upload_buffer
// 功能简述     : PC 任意 24 位 1x 波形上传与播放控制器。管理两组 16384×24 位 Bank、连续 offset/sequence、幂等重传、COMMIT 原子换 Bank 和 RXCLK→audio CDC。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
// PC 波形上传事务控制器和双 bank 播放缓冲。
//
// 设计要点：
// 1. PC 始终写“非播放 bank”，坏包或中断上传不会影响当前声音；
// 2. BEGIN -> WAVE(序号 0..N-1) -> COMMIT，偏移和序号必须连续；
// 3. COMMIT 只翻转一个跨时钟域事件，音频侧在同一时刻切换 bank 和描述符；
// 4. 两个存储体均采用一写一读的双时钟 BRAM 推断模板；
// 5. 协议解析器在包尾才给出 header_valid，因此 WAVE 数据先暂写，只有包校验
//    通过后才推进 next_offset。坏包重发时会覆盖同一段未生效存储区。
//
// CONTROL 正文固定 8 字节：
//   byte0 opcode：1=BEGIN，2=ABORT，3=STOP，4=QUERY
//   byte1 family：0=44.1 kHz，1=48 kHz
//   byte2 mode：0=1x，1=4x，2=8x，3=128x
//   byte3 source：1=PC 上传波形
//   byte4..7 repeat_count，小端；0 配合 LOOP 表示无限循环
module dac24_wave_upload_buffer #(
    parameter ADDR_WIDTH = 14,
    parameter MAX_SAMPLES = 16384
)(
    // UDP/协议解析时钟域
    input  wire                  rx_clk,
    input  wire                  rx_rst_n,
    input  wire                  header_valid,
    input  wire                  packet_error,
    input  wire [7:0]            msg_type,
    input  wire [7:0]            flags,
    input  wire [31:0]           transaction_id,
    input  wire [31:0]           sequence,
    input  wire [31:0]           total_samples,
    input  wire [31:0]           sample_offset,
    input  wire [15:0]           sample_count,
    input  wire [7:0]            body_data,
    input  wire                  body_valid,
    input  wire                  body_last,

    // 给 ACK/状态发送器使用；status_valid 为一个 rx_clk 周期脉冲
    output reg                   status_valid,
    output reg  [15:0]           status_code,
    output reg  [31:0]           status_transaction_id,
    output reg  [31:0]           status_sequence,
    output reg  [31:0]           status_total_samples,
    output reg  [31:0]           next_offset,
    output reg                   transaction_active,
    output reg  [31:0]           active_transaction_id,
    output reg  [31:0]           last_received_transaction_id,

    // 音频播放时钟域。sample_ce 应为输入采样率 44.1/48 kHz 的单周期使能。
    input  wire                  audio_clk,
    input  wire                  audio_rst_n,
    input  wire                  sample_ce,
    // 采集 RAM 空闲后才启动新的播放 epoch，确保冲激响应不会漏掉开头。
    input  wire                  capture_ready,
    // 只有板上当前采样率族与上传描述符一致时才启动播放。
    // 这样即使 PC 先上传、后切换板上开关，仍会从样本 0 开始。
    input  wire                  current_family_48k,
    output reg signed [23:0]     sample_out,
    output reg                   sample_update,
    output reg                   source_active,
    output reg                   pipeline_reset_pulse,
    output reg                   playback_family_48k,
    output reg  [1:0]            playback_mode,
    output reg  [31:0]           playback_length,
    output reg  [31:0]           playback_transaction_id
);
    localparam [7:0] MSG_CONTROL = 8'h01;
    localparam [7:0] MSG_WAVE    = 8'h02;
    localparam [7:0] MSG_COMMIT  = 8'h03;

    localparam [7:0] OP_BEGIN = 8'h01;
    localparam [7:0] OP_ABORT = 8'h02;
    localparam [7:0] OP_STOP  = 8'h03;
    localparam [7:0] OP_QUERY = 8'h04;

    // status_code 定义。0 表示接收成功，其余值便于上位机给出中文诊断。
    localparam [15:0] ST_OK              = 16'd0;
    localparam [15:0] ST_PROTOCOL_ERROR  = 16'd1;
    localparam [15:0] ST_NO_TRANSACTION  = 16'd2;
    localparam [15:0] ST_TRANSACTION_ID  = 16'd3;
    localparam [15:0] ST_SEQUENCE        = 16'd4;
    localparam [15:0] ST_OFFSET          = 16'd5;
    localparam [15:0] ST_RANGE           = 16'd6;
    localparam [15:0] ST_INCOMPLETE      = 16'd7;
    localparam [15:0] ST_CONTROL         = 16'd8;

    // 双 bank 存储器。每个数组在 rx_clk 写、audio_clk 读，Vivado 可推断简单双口 BRAM。
    (* ram_style = "block" *) reg signed [23:0] sample_bank0 [0:MAX_SAMPLES-1];
    (* ram_style = "block" *) reg signed [23:0] sample_bank1 [0:MAX_SAMPLES-1];

    reg                  upload_bank;
    reg [31:0]           upload_total;
    reg [31:0]           expected_sequence;
    reg [31:0]           expected_offset;
    reg [7:0]            upload_flags;
    reg                  upload_family;
    reg [1:0]            upload_mode;
    reg [31:0]           upload_repeat_count;
    // 最近一次成功 WAVE/COMMIT，用于 ACK 丢失后的幂等重传。
    reg [31:0]           last_wave_sequence;
    reg [31:0]           last_wave_offset;
    reg [15:0]           last_wave_count;
    reg                  last_wave_valid;
    reg [31:0]           last_commit_sequence;
    reg                  last_commit_valid;

    // 当前包的临时解析状态。
    reg [15:0]           body_index;
    reg [1:0]            sample_byte_phase;
    reg [7:0]            sample_byte0;
    reg [7:0]            sample_byte1;
    reg [15:0]           wave_samples_seen;
    reg                  wave_packet_write_ok;

    reg [7:0]            control_opcode;
    reg [7:0]            control_family;
    reg [7:0]            control_mode;
    reg [7:0]            control_source;
    reg [31:0]           control_repeat_count;

    // 提交/停止事件及稳定的跨域描述符。
    reg                  commit_toggle_rx;
    reg                  commit_bank_rx;
    reg [31:0]           commit_length_rx;
    reg [7:0]            commit_flags_rx;
    reg                  commit_family_rx;
    reg [1:0]            commit_mode_rx;
    reg [31:0]           commit_repeat_rx;
    reg [31:0]           commit_transaction_id_rx;
    reg                  stop_toggle_rx;

    wire [31:0] control_repeat_at_eop =
        (body_valid && (msg_type == MSG_CONTROL) && (body_index == 16'd7)) ?
        {body_data, control_repeat_count[23:0]} : control_repeat_count;

    wire wave_metadata_ok =
        transaction_active &&
        (transaction_id == active_transaction_id) &&
        (sequence == expected_sequence) &&
        (sample_offset == expected_offset) &&
        (total_samples == upload_total) &&
        (sample_count != 16'd0) &&
        (sample_count <= 16'd256) &&
        ((sample_offset + sample_count) <= upload_total) &&
        ((sample_offset + sample_count) <= MAX_SAMPLES);

    // BRAM 写端严格不带复位。复位只清事务控制状态，RAM 中旧内容在没有
    // 新事务 COMMIT 前永远不会被播放；这样也避免异步复位进入 WEA 控制锥。
    wire wave_bram_write_en = body_valid && (msg_type == MSG_WAVE) &&
                              (sample_byte_phase == 2'd2) &&
                              wave_packet_write_ok;
    wire [ADDR_WIDTH-1:0] wave_bram_write_addr =
        sample_offset[ADDR_WIDTH-1:0] + wave_samples_seen;
    always @(posedge rx_clk) begin
        if (wave_bram_write_en) begin
            if (upload_bank)
                sample_bank1[wave_bram_write_addr] <=
                    {body_data, sample_byte1, sample_byte0};
            else
                sample_bank0[wave_bram_write_addr] <=
                    {body_data, sample_byte1, sample_byte0};
        end
    end

    // 上传事务和 BRAM 写端口。
    always @(posedge rx_clk) begin
        if (!rx_rst_n) begin
            status_valid             <= 1'b0;
            status_code              <= ST_OK;
            status_transaction_id    <= 32'd0;
            status_sequence          <= 32'd0;
            status_total_samples     <= 32'd0;
            next_offset              <= 32'd0;
            transaction_active       <= 1'b0;
            active_transaction_id    <= 32'd0;
            last_received_transaction_id <= 32'd0;
            upload_bank              <= 1'b1;
            upload_total             <= 32'd0;
            expected_sequence        <= 32'd0;
            expected_offset          <= 32'd0;
            upload_flags             <= 8'd0;
            upload_family            <= 1'b0;
            upload_mode              <= 2'd0;
            upload_repeat_count      <= 32'd0;
            last_wave_sequence       <= 32'd0;
            last_wave_offset         <= 32'd0;
            last_wave_count          <= 16'd0;
            last_wave_valid          <= 1'b0;
            last_commit_sequence     <= 32'd0;
            last_commit_valid        <= 1'b0;
            body_index               <= 16'd0;
            sample_byte_phase        <= 2'd0;
            sample_byte0             <= 8'd0;
            sample_byte1             <= 8'd0;
            wave_samples_seen        <= 16'd0;
            wave_packet_write_ok     <= 1'b0;
            control_opcode           <= 8'd0;
            control_family           <= 8'd0;
            control_mode             <= 8'd0;
            control_source           <= 8'd0;
            control_repeat_count     <= 32'd0;
            commit_toggle_rx         <= 1'b0;
            commit_bank_rx           <= 1'b0;
            commit_length_rx         <= 32'd0;
            commit_flags_rx          <= 8'd0;
            commit_family_rx         <= 1'b0;
            commit_mode_rx           <= 2'd0;
            commit_repeat_rx         <= 32'd0;
            commit_transaction_id_rx <= 32'd0;
            stop_toggle_rx           <= 1'b0;
        end else begin
            status_valid <= 1'b0;

            // 正文先于 header_valid 到达。WAVE 的第一字节处锁存本包是否允许暂写。
            if (body_valid) begin
                body_index <= body_index + 16'd1;

                if (msg_type == MSG_CONTROL) begin
                    case (body_index)
                        16'd0: control_opcode <= body_data;
                        16'd1: control_family <= body_data;
                        16'd2: control_mode <= body_data;
                        16'd3: control_source <= body_data;
                        16'd4: control_repeat_count[7:0] <= body_data;
                        16'd5: control_repeat_count[15:8] <= body_data;
                        16'd6: control_repeat_count[23:16] <= body_data;
                        16'd7: control_repeat_count[31:24] <= body_data;
                        default: begin end
                    endcase
                end

                if (msg_type == MSG_WAVE) begin
                    if (body_index == 16'd0)
                        wave_packet_write_ok <= wave_metadata_ok;

                    case (sample_byte_phase)
                        2'd0: begin
                            sample_byte0 <= body_data;
                            sample_byte_phase <= 2'd1;
                        end
                        2'd1: begin
                            sample_byte1 <= body_data;
                            sample_byte_phase <= 2'd2;
                        end
                        default: begin
                            sample_byte_phase <= 2'd0;
                            wave_samples_seen <= wave_samples_seen + 16'd1;
                            // 第一个样本在第三个字节到达时，write_ok 已于第一字节锁存。
                        end
                    endcase
                end
            end

            if (packet_error) begin
                status_valid          <= 1'b1;
                status_code           <= ST_PROTOCOL_ERROR;
                status_transaction_id <= transaction_id;
                status_sequence       <= sequence;
                status_total_samples  <= total_samples;
                next_offset           <= expected_offset;
                body_index            <= 16'd0;
                sample_byte_phase     <= 2'd0;
                wave_samples_seen     <= 16'd0;
                wave_packet_write_ok  <= 1'b0;
                control_repeat_count  <= 32'd0;
            end else if (header_valid) begin
                last_received_transaction_id <= transaction_id;
                status_valid          <= 1'b1;
                status_transaction_id <= transaction_id;
                status_sequence       <= sequence;
                status_total_samples  <= total_samples;
                next_offset           <= expected_offset;

                if (msg_type == MSG_CONTROL) begin
                    // header_valid 与第 8 个正文节拍同周期到达，此处的旧 body_index 应为 7。
                    if ((body_index != 16'd7) ||
                        !(body_valid && body_last && (body_index == 16'd7))) begin
                        status_code <= ST_CONTROL;
                    end else if (control_opcode == OP_BEGIN) begin
                        if ((sequence != 32'd0) ||
                            (total_samples == 32'd0) ||
                            (total_samples > MAX_SAMPLES) ||
                            (control_family > 8'd1) ||
                            (control_mode > 8'd3) ||
                            (control_source != 8'd1)) begin
                            status_code <= ST_RANGE;
                        end else begin
                            // commit_bank_rx 是最近一次发布的 bank；其反相必为安全的写入 bank。
                            upload_bank           <= ~commit_bank_rx;
                            transaction_active    <= 1'b1;
                            active_transaction_id <= transaction_id;
                            upload_total          <= total_samples;
                            expected_sequence     <= 32'd0;
                            expected_offset       <= 32'd0;
                            // 播放行为由最终 COMMIT 明确决定；BEGIN 只建立事务。
                            upload_flags          <= 8'd0;
                            upload_family         <= control_family[0];
                            upload_mode           <= control_mode[1:0];
                            upload_repeat_count   <= control_repeat_at_eop;
                            last_wave_valid        <= 1'b0;
                            last_commit_valid      <= 1'b0;
                            next_offset           <= 32'd0;
                            status_code            <= ST_OK;
                        end
                    end else if (control_opcode == OP_ABORT) begin
                        if (!transaction_active) begin
                            status_code <= ST_NO_TRANSACTION;
                        end else if (transaction_id != active_transaction_id) begin
                            status_code <= ST_TRANSACTION_ID;
                        end else begin
                            transaction_active <= 1'b0;
                            expected_offset    <= 32'd0;
                            next_offset        <= 32'd0;
                            status_code        <= ST_OK;
                        end
                    end else if (control_opcode == OP_STOP) begin
                        stop_toggle_rx <= ~stop_toggle_rx;
                        status_code    <= ST_OK;
                    end else if (control_opcode == OP_QUERY) begin
                        status_code <= ST_OK;
                    end else begin
                        status_code <= ST_CONTROL;
                    end
                end else if (msg_type == MSG_WAVE) begin
                    if (!transaction_active) begin
                        status_code <= ST_NO_TRANSACTION;
                    end else if (transaction_id != active_transaction_id) begin
                        status_code <= ST_TRANSACTION_ID;
                    end else if (last_wave_valid &&
                                 (sequence == last_wave_sequence) &&
                                 (sample_offset == last_wave_offset) &&
                                 (sample_count == last_wave_count) &&
                                 (total_samples == upload_total) &&
                                 ((sample_offset + sample_count) ==
                                  expected_offset)) begin
                        // 上一包已经写入并推进，只是 ACK 丢失；重复包直接回显成功。
                        next_offset <= expected_offset;
                        status_code <= ST_OK;
                    end else if (sequence != expected_sequence) begin
                        status_code <= ST_SEQUENCE;
                    end else if (sample_offset != expected_offset) begin
                        status_code <= ST_OFFSET;
                    end else if ((total_samples != upload_total) ||
                                 (sample_count == 16'd0) ||
                                 ((sample_offset + sample_count) > upload_total) ||
                                 ((sample_offset + sample_count) > MAX_SAMPLES)) begin
                        status_code <= ST_RANGE;
                    end else if (!wave_packet_write_ok ||
                                 ((wave_samples_seen +
                                   ((body_valid && (sample_byte_phase == 2'd2)) ? 16'd1 : 16'd0))
                                  != sample_count)) begin
                        status_code <= ST_PROTOCOL_ERROR;
                    end else begin
                        expected_sequence <= expected_sequence + 32'd1;
                        expected_offset   <= expected_offset + sample_count;
                        last_wave_sequence <= sequence;
                        last_wave_offset   <= sample_offset;
                        last_wave_count    <= sample_count;
                        last_wave_valid    <= 1'b1;
                        next_offset       <= expected_offset + sample_count;
                        status_code       <= ST_OK;
                    end
                end else if (msg_type == MSG_COMMIT) begin
                    if (!transaction_active && last_commit_valid &&
                        (transaction_id == commit_transaction_id_rx) &&
                        (sequence == last_commit_sequence) &&
                        (total_samples == commit_length_rx) &&
                        (sample_offset == commit_length_rx)) begin
                        // COMMIT 已经生效但 ACK 丢失；不得再次翻转 bank/event。
                        status_code <= ST_OK;
                        next_offset <= commit_length_rx;
                    end else if (!transaction_active) begin
                        status_code <= ST_NO_TRANSACTION;
                    end else if (transaction_id != active_transaction_id) begin
                        status_code <= ST_TRANSACTION_ID;
                    end else if (sequence != expected_sequence) begin
                        status_code <= ST_SEQUENCE;
                    end else if ((sample_offset != expected_offset) ||
                                 (expected_offset != upload_total) ||
                                 (total_samples != upload_total)) begin
                        status_code <= ST_INCOMPLETE;
                    end else begin
                        // 描述符先保持稳定，再翻转事件位；音频侧同步后一次性采用。
                        commit_bank_rx       <= upload_bank;
                        commit_length_rx     <= upload_total;
                        // RESET_PIPELINE/LOOP/ONE_SHOT 是 COMMIT 的发布语义。
                        // BEGIN 只携带事务公共 flags；若沿用 BEGIN 保存值，PC 在
                        // COMMIT 中请求的流水线复位和播放方式会被静默丢失。
                        commit_flags_rx      <= flags;
                        commit_family_rx     <= upload_family;
                        commit_mode_rx       <= upload_mode;
                        commit_repeat_rx     <= upload_repeat_count;
                        commit_transaction_id_rx <= active_transaction_id;
                        last_commit_sequence <= sequence;
                        last_commit_valid    <= 1'b1;
                        commit_toggle_rx     <= ~commit_toggle_rx;
                        transaction_active   <= 1'b0;
                        status_code          <= ST_OK;
                        next_offset          <= expected_offset;
                    end
                end else begin
                    status_code <= ST_PROTOCOL_ERROR;
                end

                body_index           <= 16'd0;
                sample_byte_phase     <= 2'd0;
                wave_samples_seen     <= 16'd0;
                wave_packet_write_ok  <= 1'b0;
                control_repeat_count  <= 32'd0;
            end
        end
    end

    // 跨时钟域同步器。描述符在 commit_toggle 翻转前后长期保持不变。
    reg commit_sync1, commit_sync2, commit_seen;
    reg commit_pending;
    reg stop_sync1, stop_sync2, stop_seen;
    reg commit_bank_sync1, commit_bank_sync2;
    reg [31:0] commit_length_sync1, commit_length_sync2;
    reg [7:0]  commit_flags_sync1, commit_flags_sync2;
    reg commit_family_sync1, commit_family_sync2;
    reg [1:0] commit_mode_sync1, commit_mode_sync2;
    reg [31:0] commit_repeat_sync1, commit_repeat_sync2;
    reg [31:0] commit_transaction_id_sync1;
    reg [31:0] commit_transaction_id_sync2;

    reg                  active_bank_audio;
    reg [ADDR_WIDTH-1:0] read_address;
    reg signed [23:0]    bank0_read_data;
    reg signed [23:0]    bank1_read_data;
    reg [1:0]            prefetch_count;
    reg                  infinite_repeat;
    reg [31:0]           repeats_remaining;
    reg                  playback_running;

    // BRAM 读端口：地址保持期间反复预取，sample_ce 到来时数据已稳定。
    always @(posedge audio_clk) begin
        bank0_read_data <= sample_bank0[read_address];
        bank1_read_data <= sample_bank1[read_address];
    end

    always @(posedge audio_clk) begin
        if (!audio_rst_n) begin
            commit_sync1          <= 1'b0;
            commit_sync2          <= 1'b0;
            commit_seen           <= 1'b0;
            commit_pending        <= 1'b0;
            stop_sync1            <= 1'b0;
            stop_sync2            <= 1'b0;
            stop_seen             <= 1'b0;
            commit_bank_sync1     <= 1'b0;
            commit_bank_sync2     <= 1'b0;
            commit_length_sync1   <= 32'd0;
            commit_length_sync2   <= 32'd0;
            commit_flags_sync1    <= 8'd0;
            commit_flags_sync2    <= 8'd0;
            commit_family_sync1   <= 1'b0;
            commit_family_sync2   <= 1'b0;
            commit_mode_sync1     <= 2'd0;
            commit_mode_sync2     <= 2'd0;
            commit_repeat_sync1   <= 32'd0;
            commit_repeat_sync2   <= 32'd0;
            commit_transaction_id_sync1 <= 32'd0;
            commit_transaction_id_sync2 <= 32'd0;
            active_bank_audio     <= 1'b0;
            read_address          <= {ADDR_WIDTH{1'b0}};
            sample_out            <= 24'sd0;
            sample_update         <= 1'b0;
            source_active         <= 1'b0;
            pipeline_reset_pulse  <= 1'b0;
            playback_family_48k   <= 1'b0;
            playback_mode         <= 2'd0;
            playback_length       <= 32'd0;
            playback_transaction_id <= 32'd0;
            prefetch_count        <= 2'd0;
            infinite_repeat       <= 1'b0;
            repeats_remaining     <= 32'd0;
            playback_running      <= 1'b0;
        end else begin
            commit_sync1        <= commit_toggle_rx;
            commit_sync2        <= commit_sync1;
            stop_sync1          <= stop_toggle_rx;
            stop_sync2          <= stop_sync1;
            commit_bank_sync1   <= commit_bank_rx;
            commit_bank_sync2   <= commit_bank_sync1;
            commit_length_sync1 <= commit_length_rx;
            commit_length_sync2 <= commit_length_sync1;
            commit_flags_sync1  <= commit_flags_rx;
            commit_flags_sync2  <= commit_flags_sync1;
            commit_family_sync1 <= commit_family_rx;
            commit_family_sync2 <= commit_family_sync1;
            commit_mode_sync1   <= commit_mode_rx;
            commit_mode_sync2   <= commit_mode_sync1;
            commit_repeat_sync1 <= commit_repeat_rx;
            commit_repeat_sync2 <= commit_repeat_sync1;
            commit_transaction_id_sync1 <= commit_transaction_id_rx;
            commit_transaction_id_sync2 <= commit_transaction_id_sync1;

            sample_update        <= 1'b0;
            pipeline_reset_pulse <= 1'b0;

            if (commit_sync2 != commit_seen) begin
                // 事件位可能比描述符总线中的某一位早一拍摆脱亚稳态。
                // 先确认事件，再额外等待一个 audio_clk，避免采用旧描述符。
                commit_seen    <= commit_sync2;
                commit_pending <= 1'b1;
            end else if (commit_pending && capture_ready &&
                         (commit_family_sync2 == current_family_48k)) begin
                commit_pending       <= 1'b0;
                active_bank_audio    <= commit_bank_sync2;
                playback_length      <= commit_length_sync2;
                playback_family_48k  <= commit_family_sync2;
                playback_mode        <= commit_mode_sync2;
                playback_transaction_id <= commit_transaction_id_sync2;
                read_address         <= {ADDR_WIDTH{1'b0}};
                // 新事务采用时必须先清掉上一事务停留在输出寄存器中的样本。
                // 数据通路复位后的第一个 1x 采样时刻可能早于新 bank 首样本的
                // BRAM 预取完成；若保留旧值，该旧样本会被当成冲激前导输入，
                // 使第一次正式冲激响应叠加一份提前 128 个输出点的旧响应。
                // 第二次测量之所以往往正常，是因为上一轮 one-shot 已把这里清零。
                sample_out           <= 24'sd0;
                source_active        <= (commit_length_sync2 != 32'd0);
                playback_running     <= (commit_length_sync2 != 32'd0);
                prefetch_count       <= 2'd0;
                pipeline_reset_pulse <= commit_flags_sync2[2];

                // ONE_SHOT 优先；否则 repeat_count=0 且 LOOP=1 表示无限循环。
                if (commit_flags_sync2[3]) begin
                    infinite_repeat   <= 1'b0;
                    repeats_remaining <= 32'd1;
                end else if ((commit_repeat_sync2 == 32'd0) && commit_flags_sync2[1]) begin
                    infinite_repeat   <= 1'b1;
                    repeats_remaining <= 32'd0;
                end else if (commit_repeat_sync2 == 32'd0) begin
                    infinite_repeat   <= 1'b0;
                    repeats_remaining <= 32'd1;
                end else begin
                    infinite_repeat   <= 1'b0;
                    repeats_remaining <= commit_repeat_sync2;
                end
            end else if (stop_sync2 != stop_seen) begin
                stop_seen     <= stop_sync2;
                commit_pending <= 1'b0;
                source_active <= 1'b0;
                playback_running <= 1'b0;
                sample_out    <= 24'sd0;
            end else begin
                if (source_active && playback_running &&
                    (prefetch_count != 2'd3))
                    prefetch_count <= prefetch_count + 2'd1;

                if (sample_ce && source_active && !playback_running) begin
                    // 单次波形结束后继续注入零样本，使 FIR/CIC 尾部能够完整排空；
                    // 只有显式 STOP 才切回板载 ROM。
                    sample_out    <= 24'sd0;
                    sample_update <= 1'b1;
                end else if (sample_ce && source_active && playback_running &&
                             (prefetch_count >= 2'd2)) begin
                    sample_out <= active_bank_audio ? bank1_read_data : bank0_read_data;
                    sample_update <= 1'b1;

                    if (({{(32-ADDR_WIDTH){1'b0}}, read_address} + 32'd1) >=
                        playback_length) begin
                        if (infinite_repeat) begin
                            read_address <= {ADDR_WIDTH{1'b0}};
                        end else if (repeats_remaining > 32'd1) begin
                            repeats_remaining <= repeats_remaining - 32'd1;
                            read_address <= {ADDR_WIDTH{1'b0}};
                        end else begin
                            playback_running <= 1'b0;
                            read_address <= {ADDR_WIDTH{1'b0}};
                        end
                    end else begin
                        read_address <= read_address + 1'b1;
                    end
                end
            end
        end
    end
endmodule
