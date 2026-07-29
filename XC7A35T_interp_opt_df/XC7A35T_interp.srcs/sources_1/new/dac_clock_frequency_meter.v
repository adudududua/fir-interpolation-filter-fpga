`timescale 1ns / 1ps
//=============================================================
// 文件名       : dac_clock_frequency_meter.v
// 模块名       : dac_clock_frequency_meter
// 功能简述     : 使用独立100MHz参考时钟对异步DAC采样时钟测频。
//                100ms闸门内累计DAC时钟上升沿，输出边沿数以及
//                以Hz为单位的测量结果，便于ILA直接十进制显示。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-19
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-19：新增独立100MHz参考时钟测频模块。
//=============================================================

module dac_clock_frequency_meter #(
    parameter integer MEASUREMENT_WINDOW_CYCLES = 10000000
)(
    input  wire        clk_ref_100m,
    input  wire        rst_n,
    input  wire        signal_in_async,

    output reg  [23:0] frequency_hz,
    output reg  [19:0] edge_count_100ms,
    output reg         measurement_toggle
);

    // DAC_CLK最高约5.645MHz，100MHz参考时钟满足异步边沿检测要求。
    (* ASYNC_REG = "TRUE" *) reg [2:0] signal_sync = 3'b000;

    always @(posedge clk_ref_100m or negedge rst_n) begin
        if (!rst_n)
            signal_sync <= 3'b000;
        else
            signal_sync <= {signal_sync[1:0], signal_in_async};
    end

    wire signal_rise;

    assign signal_rise = signal_sync[1] & ~signal_sync[2];

    reg [23:0] reference_count = 24'd0;
    reg [19:0] edge_count_running = 20'd0;
    wire [19:0] edge_count_with_current;
    wire [23:0] frequency_hz_with_current;

    assign edge_count_with_current = edge_count_running +
                                     (signal_rise ? 20'd1 : 20'd0);

    // 100ms闸门的计数值乘以10即为Hz。移位相加避免通用乘法器。
    assign frequency_hz_with_current =
        ({4'd0, edge_count_with_current} << 3) +
        ({4'd0, edge_count_with_current} << 1);

    always @(posedge clk_ref_100m or negedge rst_n) begin
        if (!rst_n) begin
            reference_count    <= 24'd0;
            edge_count_running <= 20'd0;
            edge_count_100ms   <= 20'd0;
            frequency_hz       <= 24'd0;
            measurement_toggle <= 1'b0;
        end
        else if (reference_count == MEASUREMENT_WINDOW_CYCLES - 1) begin
            reference_count    <= 24'd0;
            edge_count_running <= 20'd0;
            edge_count_100ms   <= edge_count_with_current;
            frequency_hz       <= frequency_hz_with_current;
            measurement_toggle <= ~measurement_toggle;
        end
        else begin
            reference_count <= reference_count + 1'b1;

            if (signal_rise)
                edge_count_running <= edge_count_running + 1'b1;
        end
    end

endmodule

