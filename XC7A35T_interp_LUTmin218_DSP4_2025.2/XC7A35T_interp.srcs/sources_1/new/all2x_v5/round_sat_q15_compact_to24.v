`timescale 1ns / 1ps

//=============================================================
// 文件名       : round_sat_q15_compact_to24.v
// 模块名       : round_sat_q15_compact_to24
// 功能简述     : Q15 全精度累加值到 24bit signed 的紧凑舍入饱和。
//                本模块不构造 IN_W 位舍入偏置加法器，而是先执行
//                算术截断，再根据符号位和 15bit 余数生成单比特
//                进位，最后使用高位符号一致性完成饱和判断。
//
//                与原 round_sat_q16_to24(FRAC_W=15) 等价：
//                  正数：加 16384 后右移 15 位；
//                  负数：加 16383 后右移 15 位；
//                  中点采用远离 0 的舍入规则。
//
// 当前默认配置：
//                  输入位宽：42bit signed Q15
//                  输出位宽：24bit signed integer
//                  实现目标：缩短宽 CARRY 链并减少 LUT
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-12
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-12：新增 Q15 紧凑舍入饱和模块。
//=============================================================

module round_sat_q15_compact_to24 #(
    parameter integer IN_W  = 42,
    parameter integer OUT_W = 24
)(
    input  wire signed [IN_W-1:0]  din_full,
    output reg  signed [OUT_W-1:0] dout_24
);

    localparam integer FRAC_W  = 15;
    localparam integer SHIFT_W = IN_W - FRAC_W;
    localparam integer UPPER_W = SHIFT_W + 1 - OUT_W;

    localparam signed [OUT_W-1:0] OUT_MAX =
        {1'b0, {(OUT_W-1){1'b1}}};
    localparam signed [OUT_W-1:0] OUT_MIN =
        {1'b1, {(OUT_W-1){1'b0}}};

    wire signed [SHIFT_W-1:0] truncated_value;
    wire                         round_increment;
    wire signed [SHIFT_W:0]      rounded_value;
    wire                         upper_is_sign_extension;

    assign truncated_value = din_full >>> FRAC_W;

    assign round_increment = din_full[FRAC_W-1] &&
        (!din_full[IN_W-1] || (|din_full[FRAC_W-2:0]));

    assign rounded_value =
        $signed({truncated_value[SHIFT_W-1], truncated_value}) +
        $signed({{SHIFT_W{1'b0}}, round_increment});

    assign upper_is_sign_extension =
        rounded_value[SHIFT_W:OUT_W] ==
        {UPPER_W{rounded_value[OUT_W-1]}};

    always @(*) begin
        if (upper_is_sign_extension)
            dout_24 = rounded_value[OUT_W-1:0];
        else if (rounded_value[SHIFT_W])
            dout_24 = OUT_MIN;
        else
            dout_24 = OUT_MAX;
    end

endmodule
