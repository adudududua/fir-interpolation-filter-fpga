`timescale 1ns / 1ps

//=============================================================
// CIC16 N=3 前置三抽头无乘法通带补偿器
//
//   y[n] = x[n-1] + (2*x[n-1] - x[n] - x[n-2]) / 8
//
// 等效 Q3 系数为 [-1, 10, -1]/8，严格对称且直流增益为 1。
// OUTPUT_W=DATA_W 保留兼容的逐级饱和接口；OUTPUT_W=DATA_W+1
// 则无损保留补偿器的自然峰值余量，由后级 CIC 最终量化器统一饱和。
//=============================================================

module cic3_compensator_shiftadd_ce #(
    parameter integer DATA_W = 20,
    parameter integer OUTPUT_W = DATA_W,
    parameter integer REGISTER_OUTPUT = 1
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,
    output wire signed [OUTPUT_W-1:0]   y_out,
    output wire                         y_out_valid
);

    localparam integer EXT_W = DATA_W + 3;
    localparam signed [DATA_W-1:0] OUT_MAX =
        {1'b0, {(DATA_W-1){1'b1}}};
    localparam signed [DATA_W-1:0] OUT_MIN =
        {1'b1, {(DATA_W-1){1'b0}}};

    reg signed [DATA_W-1:0] x_z1;
    reg signed [DATA_W-1:0] x_z2;
    reg signed [OUTPUT_W-1:0] y_out_reg;
    reg y_out_valid_reg;

    wire signed [EXT_W-1:0] x_now_ext;
    wire signed [EXT_W-1:0] x_z1_ext;
    wire signed [EXT_W-1:0] x_z2_ext;
    wire signed [EXT_W-1:0] curvature;
    wire signed [EXT_W-1:0] correction;
    wire signed [EXT_W-1:0] equalized;
    wire upper_is_sign_extension;
    wire signed [DATA_W-1:0] equalized_sat;
    wire signed [OUTPUT_W-1:0] equalized_output;

    assign x_now_ext = {{(EXT_W-DATA_W){x_in[DATA_W-1]}}, x_in};
    assign x_z1_ext = {{(EXT_W-DATA_W){x_z1[DATA_W-1]}}, x_z1};
    assign x_z2_ext = {{(EXT_W-DATA_W){x_z2[DATA_W-1]}}, x_z2};

    assign curvature = (x_z1_ext <<< 1) - x_now_ext - x_z2_ext;
    assign correction = curvature >>> 3;
    assign equalized = x_z1_ext + correction;

    assign upper_is_sign_extension =
        equalized[EXT_W-1:DATA_W] ==
        {(EXT_W-DATA_W){equalized[DATA_W-1]}};
    assign equalized_sat = upper_is_sign_extension ?
        equalized[DATA_W-1:0] :
        (equalized[EXT_W-1] ? OUT_MIN : OUT_MAX);

    generate
        if (OUTPUT_W == DATA_W) begin : gen_saturating_output
            assign equalized_output = equalized_sat;
        end
        else begin : gen_headroom_output
            // 对任意 DATA_W-bit 有符号输入，精确输出范围只需 DATA_W+1
            // 位；这里不是近似截位，也不会引入溢出或量化误差。
            assign equalized_output = equalized[OUTPUT_W-1:0];
        end
    endgenerate

    assign y_out = (REGISTER_OUTPUT != 0) ?
                   y_out_reg : equalized_output;
    assign y_out_valid = (REGISTER_OUTPUT != 0) ?
                         y_out_valid_reg : x_in_valid;

    always @(posedge clk) begin
        if (!rst_n) begin
            x_z1 <= {DATA_W{1'b0}};
            x_z2 <= {DATA_W{1'b0}};
            y_out_reg <= {OUTPUT_W{1'b0}};
            y_out_valid_reg <= 1'b0;
        end
        else begin
            y_out_valid_reg <= 1'b0;
            if (x_in_valid) begin
                x_z2 <= x_z1;
                x_z1 <= x_in;
                if (REGISTER_OUTPUT != 0) begin
                    y_out_reg <= equalized_output;
                    y_out_valid_reg <= 1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (DATA_W < 4)
            $fatal(1, "cic3_compensator_shiftadd_ce DATA_W must be >= 4");
        if (OUTPUT_W != DATA_W && OUTPUT_W != DATA_W+1)
            $fatal(1, "OUTPUT_W must be DATA_W or DATA_W+1");
        if (REGISTER_OUTPUT != 0 && REGISTER_OUTPUT != 1)
            $fatal(1, "REGISTER_OUTPUT must be 0 or 1");
    end
`endif

endmodule
