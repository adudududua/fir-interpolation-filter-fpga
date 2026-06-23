
`default_nettype none
`timescale 1ns / 1ps

//=============================================================
// 文件名       : vs1053_spi_byte_master_48k_ab.v
// 模块名       : vs1053_spi_byte_master_48k_ab
// 功能简述     : VS1053 SPI 单字节发送模块。
//                本模块用于向 VS1053 发送 SCI 控制命令字节
//                或 SDI 音频数据字节。
//
//                SPI 模式：
//                  SCLK 空闲低电平；
//                  MOSI 在 SCLK 上升沿到来前保持稳定；
//                  VS1053 在 SCLK 上升沿采样 SI 数据。
//
//                每次 start 有效 1 个 clk 周期后，本模块开始发送
//                data_in[7:0]，发送顺序为 MSB first。
//                发送期间 busy 为高，发送完成时 done 拉高 1 个
//                clk 周期。
//
// 当前默认配置：
//                  输入时钟：50MHz
//                  CLK_DIV ：12
//                  SPI SCLK：约 2.08MHz
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-06-21
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-06-21：新增 VS1053 48kHz A/B 听感工程使用的
//                            SPI 单字节发送模块。
//=============================================================

module vs1053_spi_byte_master_48k_ab #(
    parameter CLK_DIV = 12
)(
    input  wire       clk,        // 系统时钟，默认 50MHz
    input  wire       rst_n,      // 低有效复位

    input  wire       start,      // 启动发送，高有效 1 个 clk 周期
    input  wire [7:0] data_in,    // 待发送字节，MSB first

    output reg        busy,       // 发送忙标志
    output reg        done,       // 发送完成标志，高有效 1 个 clk 周期

    output reg        sclk,       // SPI 时钟，空闲低电平
    output reg        mosi        // SPI MOSI，FPGA -> VS1053
);

    //=========================================================
    // 1）内部寄存器
    //=========================================================
    reg [15:0] div_cnt;           // SPI 时钟分频计数器
    reg [2:0]  bit_idx;           // 当前发送 bit 编号
    reg [7:0]  tx_shift;          // 发送移位寄存器

    //=========================================================
    // 2）SPI 单字节发送逻辑
    //
    // 工作过程：
    //   1. 空闲时 sclk=0，busy=0。
    //   2. 检测到 start=1 后，锁存 data_in。
    //   3. 先把最高位 data_in[7] 放到 mosi。
    //   4. 每经过 CLK_DIV 个 clk，翻转一次 sclk。
    //   5. sclk 上升沿时 VS1053 采样当前 mosi。
    //   6. sclk 下降沿后准备下一位 mosi。
    //   7. 8 位发送完成后，busy 清零，done 拉高 1 个 clk。
    //=========================================================
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
                        // SCLK 上升沿：
                        // VS1053 在该边沿采样当前 mosi。
                        sclk <= 1'b1;
                    end
                    else begin
                        // SCLK 下降沿：
                        // 准备下一位 MOSI 数据。
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

`default_nettype wire

