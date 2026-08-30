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
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-13：新增 Phase 6 级间缩位桥。
//=============================================================
//=============================================================
// 1）模块名称：bridge_valid_quantized_to_interp2_ce
// 功能说明：速率桥接模块：缓存上游样本并按下游时钟使能节拍提交插值事务。
// 工程版本：Vivado 2025.2。
//=============================================================

module bridge_valid_quantized_to_interp2_ce #(
    parameter integer IN_W = 24,
    parameter integer OUT_W = 22,
    parameter integer SHIFT_N = IN_W - OUT_W,
    parameter integer USE_EXTERNAL_PHASE = 0
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire signed [IN_W-1:0]       in_data,
    input  wire                         in_valid,
    input  wire                         ce_out_next,
    input  wire                         phase_current,
    output wire signed [OUT_W-1:0]      out_data,
    output wire                         out_valid
);

    reg pending;
    reg phase_mirror;
    wire consume_now;
    wire phase_for_consume;

    generate
        if (SHIFT_N == 0) begin : gen_identity_quantizer
    // 相同Q格式边界仍需要下方pending/phase握手，但不能例化会产生非法
    // 负数位选范围的退化舍入器，因此该分支直接保持数值格式不变。
            assign out_data = in_data[OUT_W-1:0];
        end
        else begin : gen_rounding_quantizer
            // 例化说明：调用 round_sat_shift_compact 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
            round_sat_shift_compact #(
                .IN_W    (IN_W),
                .OUT_W   (OUT_W),
                .SHIFT_N (SHIFT_N)
            ) u_round_sat_shift_compact (
                .din  (in_data),
                .dout (out_data)
            );
        end
    endgenerate

    assign out_valid = pending;
    // 折叠Stage2/3核心已拥有由同一CE事件驱动的相位寄存器。全国赛构建
    // 复用这些规范相位状态；历史顶层通过默认参数保留自包含相位镜像。
    assign phase_for_consume = (USE_EXTERNAL_PHASE != 0) ?
        phase_current : phase_mirror;
    assign consume_now = ce_out_next &&
                         (phase_for_consume == 1'b0) && pending;

    always @(posedge clk) begin
        if (!rst_n) begin
            pending <= 1'b0;
            phase_mirror <= 1'b1;
        end
        else begin
            if (consume_now)
                pending <= in_valid;
            else if (in_valid)
                pending <= 1'b1;

            if ((USE_EXTERNAL_PHASE == 0) && ce_out_next)
                phase_mirror <= ~phase_mirror;
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (SHIFT_N == 0 && IN_W != OUT_W)
            $fatal(1, "identity quantized bridge requires IN_W == OUT_W");
        if (SHIFT_N < 0)
            $fatal(1, "quantized bridge SHIFT_N must not be negative");
    end

    always @(posedge clk) begin
        if (rst_n && pending && !consume_now && in_valid)
            $fatal(1, "quantized valid-only bridge input overwrite");
    end
`endif

endmodule

