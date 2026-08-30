`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_demo_interp_dac8_four_mode.v
// 模块名       : tb_demo_interp_dac8_four_mode
// 功能简述     : V4 DAC 演示公共模块四档模式功能测试平台。
//                依次验证 1x、4x、8x、128x 的 DAC 数据路径和
//                DA_CLK 分频倍率，并检查每一档输出数据均变化。
//
// 当前默认配置：
//                  输入测试信号：15kHz 单正弦
//                  输入采样率  ：44.1kHz
//                  基准时钟    ：5.6448MHz 等效时序
//                  测量窗口    ：4096 个基准时钟周期
//                  预期边沿数  ：32 / 128 / 256 / 4096
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-12
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-12：新增四档 DAC 数据与时钟倍率验证。
//=============================================================
//=============================================================
// 1）模块名称：tb_demo_interp_dac8_four_mode
// 功能说明：仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 工程版本：Vivado 2025.2。
//=============================================================

module tb_demo_interp_dac8_four_mode;

    localparam [1:0] MODE_1X = 2'b00;
    localparam [1:0] MODE_4X = 2'b01;
    localparam [1:0] MODE_8X = 2'b10;
    localparam [1:0] MODE_128X = 2'b11;

    reg clk;
    reg rst_n;
    reg [1:0] mode_sel;
    reg measure_en;
    reg [7:0] last_dac_data;
    integer dac_clk_edge_count;
    integer dac_data_change_count;

    wire dac_clk;
    wire [7:0] dac_data;
    wire [1:0] mode_led;

    // 例化说明：调用 demo_interp_dac8_audio_pcm_common 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    demo_interp_dac8_audio_pcm_common u_dut (
        .clk_audio_128x (clk),
        .rst_n          (rst_n),
        .mode_sel       (mode_sel),
        .dac_clk        (dac_clk),
        .dac_data       (dac_data),
        .mode_led       (mode_led)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge dac_clk) begin
        if (measure_en)
            dac_clk_edge_count = dac_clk_edge_count + 1;
    end

    always @(dac_data) begin
        if (measure_en && (dac_data !== last_dac_data)) begin
            dac_data_change_count = dac_data_change_count + 1;
            last_dac_data = dac_data;
        end
        else begin
            last_dac_data = dac_data;
        end
    end

    task run_one_mode;
        input [1:0] test_mode;
        input integer expected_edges;
        begin
            mode_sel = test_mode;
            rst_n = 1'b0;
            measure_en = 1'b0;
            repeat (20) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;

            repeat (10000) @(posedge clk);
            @(negedge clk);
            dac_clk_edge_count = 0;
            dac_data_change_count = 0;
            last_dac_data = dac_data;
            measure_en = 1'b1;

            repeat (4096) @(posedge clk);
            @(negedge clk);
            measure_en = 1'b0;

            $display("mode=%0d edges=%0d expected=%0d data_changes=%0d",
                     test_mode, dac_clk_edge_count, expected_edges,
                     dac_data_change_count);

            if (mode_led !== test_mode)
                $fatal(1, "Mode LED mismatch: mode=%0d led=%0d",
                       test_mode, mode_led);
            if (dac_clk_edge_count != expected_edges)
                $fatal(1, "DA_CLK edge mismatch: mode=%0d got=%0d expected=%0d",
                       test_mode, dac_clk_edge_count, expected_edges);
            if (dac_data_change_count < 8)
                $fatal(1, "DAC data did not change enough: mode=%0d changes=%0d",
                       test_mode, dac_data_change_count);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        mode_sel = MODE_128X;
        measure_en = 1'b0;
        dac_clk_edge_count = 0;
        dac_data_change_count = 0;
        last_dac_data = 8'd0;

        run_one_mode(MODE_1X, 32);
        run_one_mode(MODE_4X, 128);
        run_one_mode(MODE_8X, 256);
        run_one_mode(MODE_128X, 4096);

        $display("PASS: 1x/4x/8x/128x DAC modes verified.");
        $finish;
    end

endmodule
