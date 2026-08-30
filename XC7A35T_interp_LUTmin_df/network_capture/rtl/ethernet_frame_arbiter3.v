`timescale 1ns / 1ps

//=============================================================
// 文件名       : ethernet_frame_arbiter3.v
// 模块名       : ethernet_frame_arbiter3
// 功能简述     : ARP、控制 ACK 与音频回传三路整帧仲裁器。固定优先级 ARP>ACK>音频，并在相邻帧之间强制合法 IFG。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
// 三路完整 Ethernet 帧字节流仲裁器，固定优先级 s0 > s1 > s2。
//
// 一旦空闲时看到某路 valid，立即锁定该路，即使下游尚未 ready；因此在
// 首字节反压期间更高优先级请求到达也不会改变 m_data。锁定持续到 tx_last
// 完成握手。每帧之后统一插入 100 Mb/s 所需的 96 bit-time IFG（24 个
// 25 MHz MII/RGMII 时钟周期），避免不同发送器背靠背破坏线间隙。
module ethernet_frame_arbiter3 #(
    parameter integer IFG_CYCLES = 24
)(
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

    input  wire [7:0] s2_data,
    input  wire       s2_valid,
    output reg        s2_ready,
    input  wire       s2_last,

    output reg  [7:0] m_data,
    output reg        m_valid,
    input  wire       m_ready,
    output reg        m_last
);
    localparam [2:0] SEL_IDLE = 3'd0;
    localparam [2:0] SEL_0    = 3'd1;
    localparam [2:0] SEL_1    = 3'd2;
    localparam [2:0] SEL_2    = 3'd3;
    localparam [2:0] SEL_IFG  = 3'd4;

    reg [2:0] selection;
    reg [7:0] ifg_count;

    always @(*) begin
        s0_ready = 1'b0;
        s1_ready = 1'b0;
        s2_ready = 1'b0;
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
            SEL_2: begin
                m_data   = s2_data;
                m_valid  = s2_valid;
                m_last   = s2_last;
                s2_ready = m_ready;
            end
            SEL_IDLE: begin
                if (s0_valid) begin
                    m_data   = s0_data;
                    m_valid  = 1'b1;
                    m_last   = s0_last;
                    s0_ready = m_ready;
                end else if (s1_valid) begin
                    m_data   = s1_data;
                    m_valid  = 1'b1;
                    m_last   = s1_last;
                    s1_ready = m_ready;
                end else begin
                    m_data   = s2_data;
                    m_valid  = s2_valid;
                    m_last   = s2_last;
                    s2_ready = m_ready;
                end
            end
            default: begin end
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            selection <= SEL_IDLE;
            ifg_count <= 8'd0;
        end else begin
            case (selection)
                SEL_IDLE: begin
                    // valid 一出现就锁源，而不是等 ready；这是首字节反压时
                    // 保持输出稳定的关键。单字节帧若同时完成握手则直接进 IFG。
                    if (s0_valid) begin
                        if (m_ready && s0_last) begin
                            selection <= SEL_IFG;
                            ifg_count <= 8'd0;
                        end else begin
                            selection <= SEL_0;
                        end
                    end else if (s1_valid) begin
                        if (m_ready && s1_last) begin
                            selection <= SEL_IFG;
                            ifg_count <= 8'd0;
                        end else begin
                            selection <= SEL_1;
                        end
                    end else if (s2_valid) begin
                        if (m_ready && s2_last) begin
                            selection <= SEL_IFG;
                            ifg_count <= 8'd0;
                        end else begin
                            selection <= SEL_2;
                        end
                    end
                end

                SEL_0: if (m_valid && m_ready && m_last) begin
                    selection <= SEL_IFG;
                    ifg_count <= 8'd0;
                end
                SEL_1: if (m_valid && m_ready && m_last) begin
                    selection <= SEL_IFG;
                    ifg_count <= 8'd0;
                end
                SEL_2: if (m_valid && m_ready && m_last) begin
                    selection <= SEL_IFG;
                    ifg_count <= 8'd0;
                end

                SEL_IFG: begin
                    // 进入 SEL_IFG 的第一个周期已经是无载波周期；计满
                    // IFG_CYCLES 后才在下一周期重新允许选择新帧。
                    if ((IFG_CYCLES <= 1) ||
                        (ifg_count == IFG_CYCLES-1)) begin
                        selection <= SEL_IDLE;
                        ifg_count <= 8'd0;
                    end else begin
                        ifg_count <= ifg_count + 8'd1;
                    end
                end

                default: selection <= SEL_IDLE;
            endcase
        end
    end
endmodule
