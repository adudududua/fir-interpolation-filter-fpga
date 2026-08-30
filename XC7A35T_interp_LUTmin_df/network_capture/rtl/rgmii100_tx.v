`timescale 1ns / 1ps

//=============================================================
// 文件名       : rgmii100_tx.v
// 模块名       : rgmii100_tx
// 功能简述     : 固定 100 Mb/s RGMII 发送适配器。每个 25 MHz 周期发送一个半字节，ODDR 两沿重复同一 nibble，一个字节严格占两个周期。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
// 100BASE-TX RGMII 发送器。
//
// 在 10/100 Mb/s 模式下，RGMII 采用 MII 半字节速率语义：100 Mb/s 时
// TXC 为 25 MHz，一个半字节占用完整时钟周期，并在 DDR 两个边沿重复。
// 因此，每个输入字节需要两个 TXC 周期（先发送低半字节）。这与 1 Gb/s
// 每周期传输一个完整字节的映射方式不同。
module rgmii100_tx(
    input  wire       clk_25m,
    input  wire       clk_txc_25m,
    input  wire       rst_n,
    input  wire [7:0] s_data,
    input  wire       s_valid,
    output wire       s_ready,
    output wire       rgmii_txc,
    output wire [3:0] rgmii_txd,
    output wire       rgmii_txctl
);
    reg       high_phase;
    reg [7:0] held_byte;
    (* ASYNC_REG = "TRUE" *) reg [1:0] txc_rst_sync = 2'b00;
    wire txc_rst_n = txc_rst_sync[1];

    // TXC 相对字节或半字节时钟有意进行了相移。复位请求立即断言，
    // 并在 TXC 域同步释放，避免启动时出现裕量很小的 2 ns 复位恢复路径。
    always @(posedge clk_txc_25m or negedge rst_n) begin
        if (!rst_n)
            txc_rst_sync <= 2'b00;
        else
            txc_rst_sync <= {txc_rst_sync[0], 1'b1};
    end

    // 仅在保持的高半字节传输完成后才允许源端推进。
    // 因此前一个低半字节周期内，源端会保持 s_data 稳定。
    assign s_ready = high_phase;

    always @(posedge clk_25m) begin
        if (!rst_n) begin
            high_phase <= 1'b0;
            held_byte  <= 8'd0;
        end else if (!high_phase) begin
            if (s_valid) begin
                held_byte  <= s_data;
                high_phase <= 1'b1;
            end
        end else begin
            high_phase <= 1'b0;
        end
    end

    wire [3:0] active_nibble = high_phase ? held_byte[7:4] : s_data[3:0];
    wire       active_valid  = high_phase ? 1'b1 : s_valid;

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : gen_rgmii_txd
            ODDR #(
                .DDR_CLK_EDGE("SAME_EDGE"),
                .INIT(1'b0),
                .SRTYPE("SYNC")
            ) u_txd_oddr (
                .Q (rgmii_txd[i]),
                .C (clk_25m),
                .CE(1'b1),
                .D1(active_valid ? active_nibble[i] : 1'b0),
                .D2(active_valid ? active_nibble[i] : 1'b0),
                .R (~rst_n),
                .S (1'b0)
            );
        end
    endgenerate

    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE"),
        .INIT(1'b0),
        .SRTYPE("SYNC")
    ) u_txctl_oddr (
        .Q (rgmii_txctl),
        .C (clk_25m),
        .CE(1'b1),
        .D1(active_valid),
        .D2(active_valid),
        .R (~rst_n),
        .S (1'b0)
    );

    // 板上将 RTL8211E 配置为 TX/RX NoDelay。clk_txc_25m 是相对数据延后约 2 ns 的
    // MMCM 相移副本，使 TXC 满足 RGMII 时钟与数据偏斜要求，无需依赖 PHY 侧 TX 延时。
    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE"),
        .INIT(1'b0),
        .SRTYPE("SYNC")
    ) u_txc_oddr (
        .Q (rgmii_txc),
        .C (clk_txc_25m),
        .CE(1'b1),
        .D1(1'b1),
        .D2(1'b0),
        .R (~txc_rst_n),
        .S (1'b0)
    );
endmodule
