`timescale 1ns / 1ps

//=============================================================
// 文件名       : bridge_valid_quantized_to_interp2_ce.v
// 模块名       : bridge_valid_quantized_to_interp2_ce
// 功能简述     : 固定速率全 2x 链路的缩位 valid-only 桥。
//                上一级寄存输出保持不变，本模块只保存 pending 和
//                下一级相位镜像；数据通路使用紧凑舍入器把输入
//                Q 格式缩减到下一级位宽，不复制数据缓存。
//
// 当前默认配置：
//                  输入位宽：24bit signed
//                  输出位宽：22bit signed
//                  标度右移：2bit
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-13
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-13：新增 Phase 6 级间缩位桥。
//=============================================================

module bridge_valid_quantized_to_interp2_ce #(
    parameter integer IN_W = 24,
    parameter integer OUT_W = 22,
    parameter integer SHIFT_N = IN_W - OUT_W
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire signed [IN_W-1:0]       in_data,
    input  wire                         in_valid,
    input  wire                         ce_out_next,
    output wire signed [OUT_W-1:0]      out_data,
    output wire                         out_valid
);

    reg pending;
    reg phase_mirror;
    wire consume_now;

    round_sat_shift_compact #(
        .IN_W    (IN_W),
        .OUT_W   (OUT_W),
        .SHIFT_N (SHIFT_N)
    ) u_round_sat_shift_compact (
        .din  (in_data),
        .dout (out_data)
    );

    assign out_valid = pending;
    assign consume_now = ce_out_next &&
                         (phase_mirror == 1'b0) && pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending <= 1'b0;
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
            $fatal(1, "quantized valid-only bridge input overwrite");
    end
`endif

endmodule

