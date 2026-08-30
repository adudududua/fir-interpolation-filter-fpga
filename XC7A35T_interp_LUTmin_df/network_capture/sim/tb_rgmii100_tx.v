`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_rgmii100_tx.v
// 模块名       : tb_rgmii100_tx
// 功能简述     : 100M RGMII 发送测试。验证低/高半字节各保持完整周期、ODDR 双沿重复和 ready 节流。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
module tb_rgmii100_tx;
    reg clk_25m = 1'b0;
    reg clk_txc_25m = 1'b0;
    always #20 clk_25m = ~clk_25m;
    initial begin
        #2;
        forever #20 clk_txc_25m = ~clk_txc_25m;
    end

    reg rst_n = 1'b0;
    reg [7:0] s_data = 8'hA5;
    reg s_valid = 1'b0;
    wire s_ready;
    wire rgmii_txc;
    wire [3:0] rgmii_txd;
    wire rgmii_txctl;
    integer accepted = 0;

    rgmii100_tx dut (
        .clk_25m(clk_25m),
        .clk_txc_25m(clk_txc_25m),
        .rst_n(rst_n),
        .s_data(s_data),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .rgmii_txc(rgmii_txc),
        .rgmii_txd(rgmii_txd),
        .rgmii_txctl(rgmii_txctl)
    );

    always @(posedge clk_25m) begin
        if (rst_n && s_valid && s_ready) begin
            accepted = accepted + 1;
            if (accepted == 1)
                s_data <= 8'h3C;
            else
                s_valid <= 1'b0;
        end
    end

    task check_half_cycle;
        input [3:0] expected;
        begin
            #1;
            if (!rgmii_txctl || (rgmii_txd !== expected))
                $fatal(1, "期望有效半字节 %x，实际 ctl=%b data=%x",
                       expected, rgmii_txctl, rgmii_txd);
        end
    endtask

    initial begin
        repeat (3) @(posedge clk_25m);
        rst_n = 1'b1;
        @(negedge clk_25m);
        s_valid = 1'b1;

        @(posedge clk_25m); check_half_cycle(4'h5);
        @(negedge clk_25m); check_half_cycle(4'h5);
        @(posedge clk_25m); check_half_cycle(4'hA);
        @(negedge clk_25m); check_half_cycle(4'hA);
        @(posedge clk_25m); check_half_cycle(4'hC);
        @(negedge clk_25m); check_half_cycle(4'hC);
        @(posedge clk_25m); check_half_cycle(4'h3);
        @(negedge clk_25m); check_half_cycle(4'h3);

        @(posedge clk_25m); #1;
        if (rgmii_txctl || rgmii_txd != 4'h0)
            $fatal(1, "发送器没有返回空闲状态");
        if (accepted != 2)
            $fatal(1, "源端握手次数为 %0d，期望为 2", accepted);
        $display("通过：100M RGMII 每个 25 MHz 周期发送并重复一个半字节");
        $finish;
    end
endmodule
