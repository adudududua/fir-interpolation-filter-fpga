`timescale 1ns / 1ps

//=============================================================
// 文件名       : rgmii100_rx.v
// 模块名       : rgmii100_rx
// 功能简述     : 固定 100 Mb/s RGMII 接收适配器。以 RXCLK 下降沿 IOB 寄存器在数据眼中心采样半字节，搜索 7×55+D5 并输出去前导的字节帧。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
// 100BASE-TX RGMII 接收半字节转字节模块。
//
// 10/100 Mb/s RGMII 在一个 RXC 周期的两个 DDR 边沿重复同一个 MII
// 半字节；一个字节跨两个 RXC 周期传输，先低半字节、后高半字节。
// 板上 PHY 的 RGMII RX 内部延时关闭。5 个单沿 IOB 输入寄存器只在距数据
// 转换约 20 ns 的下降沿采样，因此不存在无效的上升沿采样路径。
//
// 模块先搜索连续 7 个 0x55 和 SFD 0xD5，不把前导码/SFD送给上层。错误前导
// 可在同一个 RX_DV 区间内重新同步。frame_start 与目的 MAC 第一个字节同周期；
// frame_end 在载波结束后的
// 第一个 rx_clk 周期产生。frame_error 在 frame_end 周期报告奇数半字节截断；
// 长度/FCS 检查负责拒绝 PHY 错误或采样错误造成的坏帧。
module rgmii100_rx(
    input  wire       rx_clk,
    input  wire       rst_n,
    input  wire [3:0] rgmii_rxd,
    input  wire       rgmii_rxctl,

    output reg  [7:0] data,
    output reg        data_valid,
    output reg        frame_start,
    output reg        frame_end,
    output reg        frame_error
);
    // 100 Mb/s 只需要下降沿的数据眼中心样本。直接用单沿 IOB 寄存器
    // 比 IDDR 更准确：它不会创建一个未使用的上升沿 Q1 采样检查。
    // 寄存器无需复位；下游复位期间不消费数据，首个下降沿就会覆盖它。
    (* IOB = "TRUE" *) reg [3:0] rxd_fall;
    (* IOB = "TRUE" *) reg       ctl_fall;

    always @(negedge rx_clk) begin
        rxd_fall <= rgmii_rxd;
        ctl_fall <= rgmii_rxctl;
    end

    reg       phy_in_frame;
    reg       mac_frame_active;
    reg       have_low_nibble;
    reg [3:0] low_nibble;
    reg       first_byte_pending;
    reg [2:0] preamble_count;

    // PHY 的 RGMII RX 内部延时关闭。上升沿靠近数据转换，下降沿位于 100M 数据眼中点，
    // 因此首版只采用下降沿样本；截断、PHY 错误及采样错误由长度与 FCS 兜底拒绝。
    wire symbol_dv = ctl_fall;

    always @(posedge rx_clk) begin
        if (!rst_n) begin
            data            <= 8'd0;
            data_valid      <= 1'b0;
            frame_start     <= 1'b0;
            frame_end       <= 1'b0;
            frame_error     <= 1'b0;
            phy_in_frame    <= 1'b0;
            mac_frame_active <= 1'b0;
            have_low_nibble <= 1'b0;
            low_nibble      <= 4'd0;
            first_byte_pending <= 1'b0;
            preamble_count  <= 3'd0;
        end else begin
            data_valid  <= 1'b0;
            frame_start <= 1'b0;
            frame_end   <= 1'b0;
            frame_error <= 1'b0;

            if (symbol_dv) begin
                if (!phy_in_frame) begin
                    phy_in_frame    <= 1'b1;
                    mac_frame_active <= 1'b0;
                    have_low_nibble <= 1'b1;
                    low_nibble      <= rxd_fall;
                    first_byte_pending <= 1'b0;
                    preamble_count  <= 3'd0;
                end else begin
                    if (!have_low_nibble) begin
                        low_nibble      <= rxd_fall;
                        have_low_nibble <= 1'b1;
                    end else begin
                        have_low_nibble <= 1'b0;
                        if (!mac_frame_active) begin
                            if ({rxd_fall, low_nibble} == 8'h55) begin
                                if (preamble_count != 3'd7)
                                    preamble_count <= preamble_count + 3'd1;
                            end else if (({rxd_fall, low_nibble} == 8'hD5) &&
                                         (preamble_count == 3'd7)) begin
                                mac_frame_active   <= 1'b1;
                                first_byte_pending <= 1'b1;
                                preamble_count     <= 3'd0;
                            end else begin
                                // 当前字节不属于有效前导。保持物理帧打开并继续搜索，
                                // 允许同一 RX_DV 区间内从后续 0x55 重新同步。
                                preamble_count <= 3'd0;
                            end
                        end else begin
                            data            <= {rxd_fall, low_nibble};
                            data_valid      <= 1'b1;
                            frame_start     <= first_byte_pending;
                            first_byte_pending <= 1'b0;
                        end
                    end
                end
            end else if (phy_in_frame) begin
                phy_in_frame    <= 1'b0;
                frame_end       <= mac_frame_active;
                frame_error     <= mac_frame_active &&
                                   (have_low_nibble || first_byte_pending);
                mac_frame_active <= 1'b0;
                have_low_nibble <= 1'b0;
                first_byte_pending <= 1'b0;
                preamble_count  <= 3'd0;
            end
        end
    end
endmodule
