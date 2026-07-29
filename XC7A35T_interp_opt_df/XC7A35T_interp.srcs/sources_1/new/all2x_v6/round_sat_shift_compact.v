`timescale 1ns / 1ps

//=============================================================
// 文件名       : round_sat_shift_compact.v
// 模块名       : round_sat_shift_compact
// 功能简述     : 有符号数据缩位使用的紧凑舍入饱和模块。
//                本模块先执行算术截断，再根据符号和被丢弃余数
//                生成单比特进位，避免构造 IN_W 位舍入偏置加法器。
//
//                舍入规则与 round_sat_q16_to24 一致：
//                  正数：加 2^(SHIFT_N-1) 后右移；
//                  负数：加 2^(SHIFT_N-1)-1 后右移；
//                  中点采用远离 0 的舍入规则。
//
// 当前默认配置：
//                  输入位宽：24bit signed
//                  输出位宽：22bit signed
//                  右移位数：2bit
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-13
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-13：新增 Phase 6 级间紧凑缩位模块。
//=============================================================

module round_sat_shift_compact #(
    parameter integer IN_W = 24,
    parameter integer OUT_W = 22,
    parameter integer SHIFT_N = 2
)(
    input  wire signed [IN_W-1:0]  din,
    output reg  signed [OUT_W-1:0] dout
);

    localparam integer QUOT_W = IN_W - SHIFT_N;
    localparam integer UPPER_W = QUOT_W + 1 - OUT_W;

    localparam signed [OUT_W-1:0] OUT_MAX =
        {1'b0, {(OUT_W-1){1'b1}}};
    localparam signed [OUT_W-1:0] OUT_MIN =
        {1'b1, {(OUT_W-1){1'b0}}};

    wire signed [QUOT_W-1:0] truncated_value;
    wire round_increment;
    wire signed [QUOT_W:0] rounded_value;
    wire upper_is_sign_extension;

    assign truncated_value = din >>> SHIFT_N;

    generate
        if (SHIFT_N == 1) begin : gen_one_discarded_bit
            assign round_increment = din[0] && !din[IN_W-1];
        end
        else begin : gen_multiple_discarded_bits
            assign round_increment = din[SHIFT_N-1] &&
                (!din[IN_W-1] || (|din[SHIFT_N-2:0]));
        end
    endgenerate

    assign rounded_value =
        $signed({truncated_value[QUOT_W-1], truncated_value}) +
        $signed({{QUOT_W{1'b0}}, round_increment});

    assign upper_is_sign_extension =
        rounded_value[QUOT_W:OUT_W] ==
        {UPPER_W{rounded_value[OUT_W-1]}};

    always @(*) begin
        if (upper_is_sign_extension)
            dout = rounded_value[OUT_W-1:0];
        else if (rounded_value[QUOT_W])
            dout = OUT_MIN;
        else
            dout = OUT_MAX;
    end

`ifndef SYNTHESIS
    initial begin
        if (SHIFT_N < 1 || SHIFT_N >= IN_W)
            $fatal(1, "round_sat_shift_compact SHIFT_N is invalid");
        if (UPPER_W < 1)
            $fatal(1, "round_sat_shift_compact output width is too large");
    end
`endif

endmodule

