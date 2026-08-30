`timescale 1ns / 1ps

//=============================================================
// 文件名       : dac24_capture_pingpong.v
// 模块名       : dac24_capture_pingpong / capture_sdp_bram
// 功能简述     : DAC 截位前 24 位节点采集模块。使用 16384×24 位简单双口双时钟 BRAM、toggle 握手和稳定描述符，支持 COMMIT 时确定性重启到输出索引 0。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
// 精确捕获 DAC 数据通路所选的 24 位样本，且绝不对音频数据通路施加反压。
// 仅在发送完整数据帧期间暂停捕获，因此只需推断一个简单双口块 RAM，
// 避免浪费第二个 4096x24 存储区。
module dac24_capture_pingpong #(
    parameter integer ADDR_W = 14,
    parameter integer DEPTH  = 16384
)(
    input  wire               audio_clk,
    input  wire               audio_rst_n,
    input  wire signed [23:0] sample_data,
    input  wire               sample_valid,
    input  wire [31:0]        sample_index,
    input  wire [1:0]         sample_mode,
    input  wire               sample_family_48k,
    input  wire               sample_upload_source,
    input  wire [31:0]        sample_transaction_id,
    // COMMIT 采用新上传波形时产生的一拍同步事件。只丢弃旧的未完成采集帧；
    // 不复位 done_toggle，避免网络时钟域误判出伪数据帧。
    input  wire               capture_restart,

    input  wire               net_clk,
    input  wire               net_rst_n,
    input  wire               frame_take,
    output reg                frame_valid,
    output reg  [31:0]        frame_id,
    output reg  [31:0]        frame_start_sample_index,
    output reg  [1:0]         frame_mode,
    output reg                frame_family_48k,
    output reg                frame_upload_source,
    output reg  [31:0]        frame_transaction_id,
    // 音频时钟域状态：没有完整帧占用采集 RAM 时为 1。
    output wire               capture_ready,
    input  wire [ADDR_W-1:0]  frame_rd_addr,
    output wire [23:0]        frame_rd_data
);
    localparam [ADDR_W-1:0] LAST_ADDR = DEPTH - 1;

    reg [ADDR_W-1:0] wr_addr;
    reg              done_toggle;
    reg [31:0]       done_frame_id;
    reg [31:0]       done_start_sample_index;
    reg [1:0]        done_mode;
    reg              done_family;
    reg              done_upload_source;
    reg [31:0]       done_transaction_id;
    reg              capture_full;
    reg [1:0]        capture_mode;
    reg              capture_family;
    reg              capture_upload_source;
    reg [31:0]       capture_transaction_id;
    reg [31:0]       capture_start_sample_index;

    // wr_addr==LAST_ADDR 时，下一份有效样本会在本拍完成旧帧。提前一项
    // 撤销 ready，避免 COMMIT 与旧帧完成同拍而在网络域看到 done_toggle
    // 之前开始覆写采集 RAM。
    assign capture_ready = !capture_full && (wr_addr != LAST_ADDR);

    (* ASYNC_REG = "TRUE" *) reg take_meta;
    (* ASYNC_REG = "TRUE" *) reg take_sync;
    reg take_seen;

    wire partial_mode_change =
        (wr_addr != {ADDR_W{1'b0}}) &&
        ((sample_mode != capture_mode) ||
         (sample_family_48k != capture_family) ||
         (sample_upload_source != capture_upload_source) ||
         (sample_transaction_id != capture_transaction_id));
    wire capture_write_en = sample_valid && !capture_restart && !capture_full &&
                            (take_sync == take_seen);
    wire [ADDR_W-1:0] capture_write_addr = partial_mode_change ?
                                              {ADDR_W{1'b0}} : wr_addr;

    // 将双时钟 RAM 独立放在严格的推断模板中。若在控制器内组合两个数组的
    // 条件读取，Vivado 2018.3 会把存储器展开成 LUT/FF 多路选择树，
    // 而不是映射为块 RAM。
    capture_sdp_bram #(
        .ADDR_W(ADDR_W),
        .DEPTH (DEPTH)
    ) u_capture_ram (
        .wr_clk (audio_clk),
        .wr_en  (capture_write_en),
        .wr_addr(capture_write_addr),
        .wr_data(sample_data),
        .rd_clk (net_clk),
        .rd_addr(frame_rd_addr),
        .rd_data(frame_rd_data)
    );

    // 音频时钟域写入端。完整数据帧保持不变，直到所有 UDP 数据包发送完毕后，
    // 网络侧返回 frame_take。
    always @(posedge audio_clk) begin
        if (!audio_rst_n) begin
            wr_addr       <= {ADDR_W{1'b0}};
            done_toggle   <= 1'b0;
            done_frame_id <= 32'd0;
            done_start_sample_index <= 32'd0;
            done_mode     <= 2'd0;
            done_family   <= 1'b0;
            done_upload_source <= 1'b0;
            done_transaction_id <= 32'd0;
            capture_full  <= 1'b0;
            capture_mode  <= 2'd0;
            capture_family<= 1'b0;
            capture_upload_source <= 1'b0;
            capture_transaction_id <= 32'd0;
            capture_start_sample_index <= 32'd0;
            take_meta     <= 1'b0;
            take_sync     <= 1'b0;
            take_seen     <= 1'b0;
        end else begin
            take_meta <= frame_take;
            take_sync <= take_meta;

            // pipeline_reset_pulse 与 source_active 在 COMMIT 被采用时同拍产生。
            // 此拍边沿前 common 仍暴露旧 epoch 的 sample_index；若直接依赖
            // partial_mode_change，它会把旧索引锁成新 UPLOAD RAM 帧的起点。
            if (capture_restart) begin
                wr_addr       <= {ADDR_W{1'b0}};
                capture_full  <= 1'b0;
                capture_mode  <= 2'd0;
                capture_family <= 1'b0;
                capture_upload_source <= 1'b0;
                capture_transaction_id <= 32'd0;
                capture_start_sample_index <= 32'd0;
            end else if (take_sync != take_seen) begin
                take_seen <= take_sync;
                wr_addr   <= {ADDR_W{1'b0}};
                capture_full <= 1'b0;
            end else if (sample_valid && !capture_full &&
                         (take_sync == take_seen)) begin
                // 填充部分数据帧期间可能发生按键模式或采样率切换。
                // 此时从地址零重新开始，确保发送的数据帧不会混入两种工作模式的样本。
                if (partial_mode_change) begin
                    wr_addr        <= {{(ADDR_W-1){1'b0}}, 1'b1};
                    capture_mode   <= sample_mode;
                    capture_family <= sample_family_48k;
                    capture_upload_source <= sample_upload_source;
                    capture_transaction_id <= sample_transaction_id;
                    capture_start_sample_index <= sample_index;
                end else begin
                    if (wr_addr == {ADDR_W{1'b0}}) begin
                        capture_mode   <= sample_mode;
                        capture_family <= sample_family_48k;
                        capture_upload_source <= sample_upload_source;
                        capture_transaction_id <= sample_transaction_id;
                        capture_start_sample_index <= sample_index;
                    end

                    if (wr_addr == LAST_ADDR) begin
                        done_frame_id <= done_frame_id + 32'd1;
                        done_start_sample_index <= capture_start_sample_index;
                        done_mode     <= (wr_addr == {ADDR_W{1'b0}}) ?
                                         sample_mode : capture_mode;
                        done_family   <= (wr_addr == {ADDR_W{1'b0}}) ?
                                         sample_family_48k : capture_family;
                        done_upload_source <= (wr_addr == {ADDR_W{1'b0}}) ?
                                              sample_upload_source :
                                              capture_upload_source;
                        done_transaction_id <= (wr_addr == {ADDR_W{1'b0}}) ?
                                               sample_transaction_id :
                                               capture_transaction_id;
                        done_toggle   <= ~done_toggle;
                        capture_full  <= 1'b1;
                    end else begin
                        wr_addr <= wr_addr + {{(ADDR_W-1){1'b0}}, 1'b1};
                    end
                end
            end
        end
    end

    (* ASYNC_REG = "TRUE" *) reg done_meta;
    (* ASYNC_REG = "TRUE" *) reg done_sync;
    reg done_seen;
    reg [2:0] descriptor_wait;
    reg frame_take_seen;

    // 网络时钟域描述符锁存与同步 BRAM 读端口。
    always @(posedge net_clk) begin
        if (!net_rst_n) begin
            done_meta       <= 1'b0;
            done_sync       <= 1'b0;
            done_seen       <= 1'b0;
            frame_valid     <= 1'b0;
            frame_id        <= 32'd0;
            frame_start_sample_index <= 32'd0;
            frame_mode      <= 2'd0;
            frame_family_48k<= 1'b0;
            frame_upload_source <= 1'b0;
            frame_transaction_id <= 32'd0;
            descriptor_wait <= 3'd0;
            frame_take_seen <= 1'b0;
        end else begin
            done_meta <= done_toggle;
            done_sync <= done_meta;

            if (!frame_valid && (done_sync != done_seen) &&
                (descriptor_wait == 0)) begin
                // 翻转信号已通过两级同步器。再等待若干个网络时钟周期，
                // 然后锁存保持稳定的多位数据束。
                descriptor_wait <= 3'd4;
            end else if (descriptor_wait != 0) begin
                descriptor_wait <= descriptor_wait - 3'd1;
                if (descriptor_wait == 3'd1) begin
                    done_seen        <= done_sync;
                    frame_id         <= done_frame_id;
                    frame_start_sample_index <= done_start_sample_index;
                    frame_mode       <= done_mode;
                    frame_family_48k <= done_family;
                    frame_upload_source <= done_upload_source;
                    frame_transaction_id <= done_transaction_id;
                    frame_valid      <= 1'b1;
                end
            end

            if (frame_valid && (frame_take != frame_take_seen)) begin
                frame_take_seen <= frame_take;
                frame_valid <= 1'b0;
            end
        end
    end
endmodule


// Xilinx 简单双口、双时钟块 RAM 推断模板。
module capture_sdp_bram #(
    parameter integer ADDR_W = 12,
    parameter integer DEPTH  = 4096
)(
    input  wire              wr_clk,
    input  wire              wr_en,
    input  wire [ADDR_W-1:0] wr_addr,
    input  wire [23:0]       wr_data,
    input  wire              rd_clk,
    input  wire [ADDR_W-1:0] rd_addr,
    output reg  [23:0]       rd_data
);
    (* ram_style = "block" *) reg [23:0] mem [0:DEPTH-1];

    always @(posedge wr_clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

    always @(posedge rd_clk) begin
        rd_data <= mem[rd_addr];
    end
endmodule
