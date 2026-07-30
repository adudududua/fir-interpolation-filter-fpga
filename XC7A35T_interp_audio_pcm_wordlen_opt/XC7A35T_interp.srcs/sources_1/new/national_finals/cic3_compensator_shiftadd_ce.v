`timescale 1ns / 1ps

//=============================================================
// 文件名       : cic3_compensator_shiftadd_ce.v
// 模块名       : cic3_compensator_shiftadd_ce
// 功能简述     : CIC16 N=3 前置三抽头无乘法器通带补偿。
//
//                y[n] = x[n-1]
//                     + (2*x[n-1] - x[n] - x[n-2]) / 8
//
//                等效 Q3 系数为 [-1, 10, -1] / 8，严格对称，
//                直流增益为 1。补偿器只送入 128x CIC 支路；
//                8x 展示端口直接取平坦 Stage3 输出，因此 8x 和
//                128x 可同时满足全国赛 +/-0.05 dB 通带门槛。
//
//                除 3 拍历史、加减器、算术右移和饱和外不使用
//                DSP/BRAM。
//=============================================================

module cic3_compensator_shiftadd_ce #(
    parameter integer DATA_W = 20,
    parameter integer REGISTER_OUTPUT = 1
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,
    output wire signed [DATA_W-1:0]     y_out,
    output wire                         y_out_valid
);

    localparam integer EXT_W = DATA_W + 3;
    localparam signed [DATA_W-1:0] OUT_MAX =
        {1'b0, {(DATA_W-1){1'b1}}};
    localparam signed [DATA_W-1:0] OUT_MIN =
        {1'b1, {(DATA_W-1){1'b0}}};

    reg signed [DATA_W-1:0] x_z1;
    reg signed [DATA_W-1:0] x_z2;
    reg signed [DATA_W-1:0] y_out_reg;
    reg y_out_valid_reg;

    wire signed [EXT_W-1:0] x_now_ext;
    wire signed [EXT_W-1:0] x_z1_ext;
    wire signed [EXT_W-1:0] x_z2_ext;
    wire signed [EXT_W-1:0] curvature;
    wire signed [EXT_W-1:0] correction;
    wire signed [EXT_W-1:0] equalized;
    wire upper_is_sign_extension;
    wire signed [DATA_W-1:0] equalized_sat;

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
    assign y_out = (REGISTER_OUTPUT != 0) ? y_out_reg :
                   equalized_sat;
    assign y_out_valid = (REGISTER_OUTPUT != 0) ?
                         y_out_valid_reg : x_in_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_z1 <= {DATA_W{1'b0}};
            x_z2 <= {DATA_W{1'b0}};
            y_out_reg <= {DATA_W{1'b0}};
            y_out_valid_reg <= 1'b0;
        end
        else begin
            y_out_valid_reg <= 1'b0;
            if (x_in_valid) begin
                x_z2 <= x_z1;
                x_z1 <= x_in;
                if (REGISTER_OUTPUT != 0) begin
                    y_out_reg <= equalized_sat;
                    y_out_valid_reg <= 1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (DATA_W < 4)
            $fatal(1, "cic3_compensator_shiftadd_ce DATA_W must be >= 4");
        if (REGISTER_OUTPUT != 0 && REGISTER_OUTPUT != 1)
            $fatal(1, "REGISTER_OUTPUT must be 0 or 1");
    end
`endif

endmodule
