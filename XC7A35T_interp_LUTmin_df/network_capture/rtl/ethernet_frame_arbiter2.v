`timescale 1ns / 1ps

//=============================================================
// 文件名       : ethernet_frame_arbiter2.v
// 模块名       : ethernet_frame_arbiter2
// 功能简述     : 两路以太网帧仲裁器。仅在帧边界选择高优先级输入，选中后锁定至 last，防止不同来源的帧字节交叉。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
// 两路完整以太网帧字节流仲裁器。
//
// 输入 0 作为控制 ACK 通道，输入 1 作为音频采集通道。空闲时输入 0 优先；
// 一旦任一路的首字节完成 ready/valid 握手，选择会一直锁定到该路 tx_last
// 完成握手，因此 ACK 不会从中间打断正在发送的音频帧。
module ethernet_frame_arbiter2(
    input  wire       clk,
    input  wire       rst_n,

    input  wire [7:0] s0_data,
    input  wire       s0_valid,
    output reg        s0_ready,
    input  wire       s0_last,

    input  wire [7:0] s1_data,
    input  wire       s1_valid,
    output reg        s1_ready,
    input  wire       s1_last,

    output reg  [7:0] m_data,
    output reg        m_valid,
    input  wire       m_ready,
    output reg        m_last
);
    localparam [1:0] SEL_IDLE = 2'd0;
    localparam [1:0] SEL_0    = 2'd1;
    localparam [1:0] SEL_1    = 2'd2;

    reg [1:0] selection;

    always @(*) begin
        s0_ready = 1'b0;
        s1_ready = 1'b0;
        m_data   = 8'h00;
        m_valid  = 1'b0;
        m_last   = 1'b0;

        case (selection)
            SEL_0: begin
                m_data   = s0_data;
                m_valid  = s0_valid;
                m_last   = s0_last;
                s0_ready = m_ready;
            end
            SEL_1: begin
                m_data   = s1_data;
                m_valid  = s1_valid;
                m_last   = s1_last;
                s1_ready = m_ready;
            end
            default: begin
                // 还没有帧开始时，ACK（输入 0）优先。
                if (s0_valid) begin
                    m_data   = s0_data;
                    m_valid  = 1'b1;
                    m_last   = s0_last;
                    s0_ready = m_ready;
                end else begin
                    m_data   = s1_data;
                    m_valid  = s1_valid;
                    m_last   = s1_last;
                    s1_ready = m_ready;
                end
            end
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            selection <= SEL_IDLE;
        end else begin
            case (selection)
                SEL_IDLE: begin
                    if (m_valid && m_ready && !m_last)
                        selection <= s0_valid ? SEL_0 : SEL_1;
                end
                SEL_0: begin
                    if (m_valid && m_ready && m_last)
                        selection <= SEL_IDLE;
                end
                SEL_1: begin
                    if (m_valid && m_ready && m_last)
                        selection <= SEL_IDLE;
                end
                default: selection <= SEL_IDLE;
            endcase
        end
    end
endmodule
