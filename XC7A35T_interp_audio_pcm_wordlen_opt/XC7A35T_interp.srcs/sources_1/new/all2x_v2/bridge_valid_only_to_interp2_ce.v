`timescale 1ns / 1ps

//=============================================================
// 文件名       : bridge_valid_only_to_interp2_ce.v
// 模块名       : bridge_valid_only_to_interp2_ce
// 功能简述     : 固定速率全 2x 链路的轻量级级间桥接模块。上一级
//                输出本身已经寄存并保持，因此本模块只保存 pending
//                和下一级相位镜像，不再复制 24bit 数据缓存。
//
//                适用条件：
//                  1. 上一级输出在下一有效样点前保持不变；
//                  2. 固定 CE 关系保证每次消费前最多到达一个样点；
//                  3. 仿真断言用于检查输入覆盖条件。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-11
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-11：新增无数据复制的 valid-only 桥接模块。
//=============================================================

module bridge_valid_only_to_interp2_ce #(
    parameter integer DATA_W = 24
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire signed [DATA_W-1:0]     in_data,
    input  wire                         in_valid,
    input  wire                         ce_out_next,
    output wire signed [DATA_W-1:0]     out_data,
    output wire                         out_valid
);

    reg pending;
    reg phase_mirror;

    wire consume_now;

    assign out_data = in_data;
    assign out_valid = pending;
    assign consume_now = ce_out_next
                       && (phase_mirror == 1'b0)
                       && pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending      <= 1'b0;
            phase_mirror <= 1'b1;
        end
        else begin
            if (consume_now)
                pending <= in_valid;
            else if (in_valid)
                pending <= 1'b1;

            if (ce_out_next)
                phase_mirror <= ~phase_mirror;
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && pending && !consume_now && in_valid)
            $fatal(1, "valid-only bridge input overwrite at %0t", $time);
    end
`endif

endmodule
