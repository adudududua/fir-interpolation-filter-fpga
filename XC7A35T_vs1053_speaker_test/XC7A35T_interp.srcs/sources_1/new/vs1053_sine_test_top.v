`timescale 1ns / 1ps
//=============================================================
// 文件名       : vs1053_sine_test_top.v
// 模块名       : vs1053_sine_test_top
// 功能简述     : VS1053 最小正弦测试顶层。
//                本模块通过 FPGA SPI 初始化 VS1053，
//                然后发送 VS1053 内置 sine test 命令，
//                使 VS1053 的 PHONE/耳机输出端发出测试音。
//
//                本版本用于验证：
//                  FPGA -> SPI -> VS1053 -> 音频输出
//
//                注意：
//                  该模块原理图中没有 HT6872 功放，
//                  因此不需要配置 VS1053 GPIO4 打开功放。
//                  听声音请使用 PHONE/耳机输出端。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-06-20
// 版本         : V2018.3
// 开发工具     : Vivado
//=============================================================


module vs1053_sine_test_top (
    input  wire clk,          // 板载 50MHz 时钟

    output reg  vs_rst_n,     // VS1053 复位，低有效
    output reg  vs_xcs_n,     // SCI 控制接口片选，低有效
    output reg  vs_xdcs_n,    // SDI 音频数据接口片选，低有效

    output wire vs_sclk,      // SPI 时钟
    output wire vs_mosi,      // FPGA -> VS1053
    // input  wire vs_miso,      // VS1053 -> FPGA
    input  wire vs_dreq       // VS1053 数据请求，高有效
);

    //=========================================================
    // 1）上电复位计数
    //
    // 50MHz 时钟下：
    //   2,500,000 个周期约为 50ms。
    //
    // 先保持 VS1053 复位一段时间，然后释放复位，
    // 再等待 VS1053 内部启动完成。
    //=========================================================
    localparam integer POR_CNT_MAX      = 2500000;  // 50ms
    localparam integer AFTER_RST_CNT_MAX = 1000000;  // 20ms

    reg [31:0] delay_cnt;

    //=========================================================
    // DREQ 输入同步
    //
    // vs_dreq 来自 VS1053，是外部异步信号。
    // 这里先同步到 FPGA 的 clk 时钟域，避免状态机
    // 直接采样异步输入导致误判。
    //=========================================================
    reg [1:0] dreq_sync;

    always @(posedge clk) begin
        dreq_sync <= {dreq_sync[0], vs_dreq};
    end

    wire dreq_ok = dreq_sync[1];

    //=========================================================
    // 每条 SCI / SDI 序列发送完成后的额外等待时间
    //
    // 50MHz 下：
    //   50,000 个周期约为 1ms。
    //
    // 目的：
    //   给 VS1053 足够时间拉低/恢复 DREQ，
    //   避免 FPGA 过快发送下一条命令。
    //=========================================================
    localparam integer POST_SEQ_DELAY_MAX = 50000;

    reg [31:0] post_seq_delay_cnt;

    //=========================================================
    // 2）SPI 单字节发送模块连接
    //=========================================================
    reg        spi_start;
    reg [7:0]  spi_data_in;
    wire       spi_busy;
    wire       spi_done;
    wire [7:0] spi_data_out;

    vs1053_spi_byte_master #(
        .CLK_DIV(25)
    ) u_vs1053_spi_byte_master (
        .clk      (clk),
        .rst_n    (1'b1),

        .start    (spi_start),
        .data_in  (spi_data_in),
        .busy     (spi_busy),
        .done     (spi_done),
        .data_out (spi_data_out),

        .sclk     (vs_sclk),
        .mosi     (vs_mosi),
        .miso     (1'b0)
    );

    //=========================================================
    // 3）VS1053 初始化状态机
    //
    // 初始化步骤：
    //   1. 硬件复位 VS1053；
    //   2. 等待 DREQ = 1；
    //   3. SCI 写 SCI_MODE = 0x0820；
    //      其中：
    //        0x0800 = SM_SDINEW，新 SPI 模式；
    //        0x0020 = SM_TESTS，允许 sine test；
    //   4. SCI 写 SCI_CLOCKF = 0x6000，提高内部时钟；
    //   5. SCI 写 SCI_VOL = 0x2020，设置音量；
    //   6. 通过 SDI 发送 sine test 命令；
    //   7. 保持运行。
    //=========================================================
    localparam [7:0] ST_RST_LOW        = 8'd0;
    localparam [7:0] ST_RST_HIGH_WAIT  = 8'd1;

    localparam [7:0] ST_WAIT_DREQ_MODE = 8'd2;
    localparam [7:0] ST_WAIT_DREQ_CLKF = 8'd3;
    localparam [7:0] ST_WAIT_DREQ_VOL  = 8'd4;
    localparam [7:0] ST_WAIT_DREQ_SINE = 8'd5;

    localparam [7:0] ST_SEQ_PREP       = 8'd20;
    localparam [7:0] ST_SEQ_START_BYTE = 8'd21;
    localparam [7:0] ST_SEQ_WAIT_BYTE  = 8'd22;
    localparam [7:0] ST_SEQ_END        = 8'd23;
    localparam [7:0] ST_SEQ_POST_DELAY = 8'd24;

    localparam [7:0] ST_DONE           = 8'd100;

    reg [7:0] state;
    reg [7:0] next_state_after_seq;

    // 当前发送的序列编号
    // 0：写 SCI_MODE
    // 1：写 SCI_CLOCKF
    // 2：写 SCI_VOL
    // 3：发送 sine test 命令
    reg [2:0] seq_id;
    reg [3:0] seq_idx;
    reg [3:0] seq_len;
    reg       seq_is_sdi;

    //=========================================================
    // 4）字节序列查表函数
    //
    // SCI 写寄存器格式：
    //   0x02, 寄存器地址, 数据高 8 位, 数据低 8 位
    //
    // SDI sine test 命令：
    //   53 EF 6E 24 00 00 00 00
    //=========================================================
    function [7:0] seq_byte;
        input [2:0] id;
        input [3:0] idx;
        begin
            case (id)
                // SCI_MODE = 0x0820
                3'd0: begin
                    case (idx)
                        4'd0: seq_byte = 8'h02;  // SCI write
                        4'd1: seq_byte = 8'h00;  // SCI_MODE address
                        4'd2: seq_byte = 8'h08;
                        4'd3: seq_byte = 8'h20;
                        default: seq_byte = 8'h00;
                    endcase
                end

                // SCI_CLOCKF = 0x8800
                //
                // 手册推荐常用配置为 3.5x + 1.0x 一类的高速内部时钟配置。
                // 这里先使用 0x8800，调试 VS1053 sine test 更稳。
                3'd1: begin
                    case (idx)
                        4'd0: seq_byte = 8'h02;  // SCI write
                        4'd1: seq_byte = 8'h03;  // SCI_CLOCKF address
                        4'd2: seq_byte = 8'h88;
                        4'd3: seq_byte = 8'h00;
                        default: seq_byte = 8'h00;
                    endcase
                end

                // SCI_VOL = 0x3030
                // 数值越大，音量越小。0x3030 比 0x2020 更安静。
                3'd2: begin
                    case (idx)
                        4'd0: seq_byte = 8'h02;  // SCI write
                        4'd1: seq_byte = 8'h0B;  // SCI_VOL address
                        4'd2: seq_byte = 8'h30;
                        4'd3: seq_byte = 8'h30;
                        default: seq_byte = 8'h00;
                    endcase
                end

                // VS1053 sine test start command
                3'd3: begin
                    case (idx)
                        4'd0: seq_byte = 8'h53;
                        4'd1: seq_byte = 8'hEF;
                        4'd2: seq_byte = 8'h6E;
                        4'd3: seq_byte = 8'h22;
                        4'd4: seq_byte = 8'h00;
                        4'd5: seq_byte = 8'h00;
                        4'd6: seq_byte = 8'h00;
                        4'd7: seq_byte = 8'h00;
                        default: seq_byte = 8'h00;
                    endcase
                end

                default: begin
                    seq_byte = 8'h00;
                end
            endcase
        end
    endfunction

    //=========================================================
    // 5）主状态机
    //=========================================================
    always @(posedge clk) begin
        // 默认 spi_start 只拉高一个 clk 周期
        spi_start <= 1'b0;

        case (state)
            //=================================================
            // 上电后保持 VS1053 复位
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
            // 释放复位后等待一段时间
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
            // 等待 DREQ，然后写 SCI_MODE
            //=================================================
            ST_WAIT_DREQ_MODE: begin
                if (dreq_ok) begin
                    seq_id               <= 3'd0;
                    seq_len              <= 4'd4;
                    seq_is_sdi           <= 1'b0;
                    next_state_after_seq <= ST_WAIT_DREQ_CLKF;
                    state                <= ST_SEQ_PREP;
                end
            end

            //=================================================
            // 等待 DREQ，然后写 SCI_CLOCKF
            //=================================================
            ST_WAIT_DREQ_CLKF: begin
                if (dreq_ok) begin
                    seq_id               <= 3'd1;
                    seq_len              <= 4'd4;
                    seq_is_sdi           <= 1'b0;
                    next_state_after_seq <= ST_WAIT_DREQ_VOL;
                    state                <= ST_SEQ_PREP;
                end
            end

            //=================================================
            // 等待 DREQ，然后写 SCI_VOL
            //=================================================
            ST_WAIT_DREQ_VOL: begin
                if (dreq_ok) begin
                    seq_id               <= 3'd2;
                    seq_len              <= 4'd4;
                    seq_is_sdi           <= 1'b0;
                    next_state_after_seq <= ST_WAIT_DREQ_SINE;
                    state                <= ST_SEQ_PREP;
                end
            end

            //=================================================
            // 等待 DREQ，然后发送 sine test 命令
            //=================================================
            ST_WAIT_DREQ_SINE: begin
                if (dreq_ok) begin
                    seq_id               <= 3'd3;
                    seq_len              <= 4'd8;
                    seq_is_sdi           <= 1'b1;
                    next_state_after_seq <= ST_DONE;
                    state                <= ST_SEQ_PREP;
                end
            end

            //=================================================
            // 准备发送一个字节序列
            //=================================================
            ST_SEQ_PREP: begin
                seq_idx <= 4'd0;

                if (seq_is_sdi) begin
                    vs_xcs_n  <= 1'b1;
                    vs_xdcs_n <= 1'b0;
                end
                else begin
                    vs_xcs_n  <= 1'b0;
                    vs_xdcs_n <= 1'b1;
                end

                state <= ST_SEQ_START_BYTE;
            end

            //=================================================
            // 启动发送当前字节
            //=================================================
            ST_SEQ_START_BYTE: begin
                if (!spi_busy) begin
                    spi_data_in <= seq_byte(seq_id, seq_idx);
                    spi_start   <= 1'b1;
                    state       <= ST_SEQ_WAIT_BYTE;
                end
            end

            //=================================================
            // 等待当前字节发送完成
            //=================================================
            ST_SEQ_WAIT_BYTE: begin
                if (spi_done) begin
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
            //
            // 注意：
            //   不要立刻进入下一条命令。
            //   先释放 XCS / XDCS，然后等待一段时间，
            //   让 VS1053 有机会完成内部执行并更新 DREQ。
            //=================================================
            ST_SEQ_END: begin
                vs_xcs_n  <= 1'b1;
                vs_xdcs_n <= 1'b1;

                post_seq_delay_cnt <= 32'd0;
                state              <= ST_SEQ_POST_DELAY;
            end

            //=================================================
            // 命令后固定延时
            //
            // 这里等待约 1ms。
            // 延时结束后，再跳到下一次等待 DREQ 的状态。
            //=================================================
            ST_SEQ_POST_DELAY: begin
                vs_xcs_n  <= 1'b1;
                vs_xdcs_n <= 1'b1;

                if (post_seq_delay_cnt >= POST_SEQ_DELAY_MAX) begin
                    post_seq_delay_cnt <= 32'd0;
                    state              <= next_state_after_seq;
                end
                else begin
                    post_seq_delay_cnt <= post_seq_delay_cnt + 32'd1;
                end
            end

            //=================================================
            // 完成。VS1053 应该持续输出测试音。
            //=================================================
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
    // 6）初始化寄存器初值
    //=========================================================
    initial begin
        state                = ST_RST_LOW;
        next_state_after_seq = ST_RST_LOW;

        delay_cnt          = 32'd0;
        post_seq_delay_cnt = 32'd0;
        dreq_sync          = 2'b00;

        vs_rst_n  = 1'b0;
        vs_xcs_n  = 1'b1;
        vs_xdcs_n = 1'b1;

        spi_start   = 1'b0;
        spi_data_in = 8'h00;

        seq_id     = 3'd0;
        seq_idx    = 4'd0;
        seq_len    = 4'd0;
        seq_is_sdi = 1'b0;
    end

endmodule


//=============================================================
// 模块名       : vs1053_spi_byte_master
// 功能简述     : VS1053 SPI 单字节发送/接收模块。
//                SPI 空闲时 SCLK=0，MOSI 在上升沿前稳定，
//                MISO 在 SCLK 上升沿采样。
//=============================================================

module vs1053_spi_byte_master #(
    parameter CLK_DIV = 25
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       start,
    input  wire [7:0] data_in,

    output reg        busy,
    output reg        done,
    output reg  [7:0] data_out,

    output reg        sclk,
    output reg        mosi,
    input  wire       miso
);

    reg [15:0] div_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  tx_shift;
    reg [7:0]  rx_shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy     <= 1'b0;
            done     <= 1'b0;
            data_out <= 8'h00;

            sclk     <= 1'b0;
            mosi     <= 1'b0;

            div_cnt  <= 16'd0;
            bit_idx  <= 3'd7;
            tx_shift <= 8'h00;
            rx_shift <= 8'h00;
        end
        else begin
            done <= 1'b0;

            if (!busy) begin
                sclk    <= 1'b0;
                div_cnt <= 16'd0;

                if (start) begin
                    busy     <= 1'b1;
                    tx_shift <= data_in;
                    rx_shift <= 8'h00;
                    bit_idx  <= 3'd7;
                    mosi     <= data_in[7];
                end
            end
            else begin
                if (div_cnt == CLK_DIV - 1) begin
                    div_cnt <= 16'd0;

                    if (sclk == 1'b0) begin
                        // SCLK 上升沿：VS1053 采样 MOSI，同时 FPGA 采样 MISO
                        sclk <= 1'b1;
                        rx_shift[bit_idx] <= miso;
                    end
                    else begin
                        // SCLK 下降沿：准备下一位 MOSI
                        sclk <= 1'b0;

                        if (bit_idx == 3'd0) begin
                            busy     <= 1'b0;
                            done     <= 1'b1;
                            data_out <= rx_shift;
                            mosi     <= 1'b0;
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