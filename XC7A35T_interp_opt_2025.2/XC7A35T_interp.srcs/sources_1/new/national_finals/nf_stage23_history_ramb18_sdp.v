`timescale 1ns / 1ps

//=============================================================
// 文件名       : nf_stage23_history_ramb18_sdp.v
// 模块名       : nf_stage23_history_ramb18_sdp
// 功能简述     : Stage2 与 Stage3 共用的单块 RAMB18E1 历史存储。
//                5 位逻辑地址编码为 {stage_bank, history_index}，
//                每个有符号 22 bit 样本占用一个 36 bit SDP 字。
//                端口 A 提供同步读，端口 B 提供同步写，使共享 MAC
//                读取抽头的同时，写仲裁器可提交一个历史更新。
//
//                综合时使用 RAMB18E1 原语；仿真可在行为数组与
//                原语分支之间切换，以验证地址和符号扩展完全一致。
//
// 当前默认配置：
//                  DATA_W=22，ADDR_W=5，逻辑深度 32
//                  地址最高位选择 Stage2/Stage3 存储区
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-29
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-29：合并 Stage2/3 历史到单 RAMB18E1。
//                2026-08-16：补充地址编码与双端口并行访问说明。
//=============================================================
//=============================================================
// 1）模块名称：nf_stage23_history_ramb18_sdp
// 功能说明：历史样本存储器：使用 RAMB18E1 保存 FIR 抽头所需的延迟数据。
// 工程版本：Vivado 2025.2。
//=============================================================

module nf_stage23_history_ramb18_sdp #(
    parameter integer DATA_W = 22,
    parameter integer ADDR_W = 5,
    parameter integer SIM_USE_PRIMITIVE = 0
)(
    input  wire                         clk,
    input  wire [ADDR_W-1:0]            read_addr,
    output wire signed [DATA_W-1:0]     read_data,
    input  wire                         write_enable,
    input  wire [ADDR_W-1:0]            write_addr,
    input  wire signed [DATA_W-1:0]     write_data
);

`ifdef SYNTHESIS
    localparam integer USE_PRIMITIVE = 1;
`else
    localparam integer USE_PRIMITIVE = SIM_USE_PRIMITIVE;
`endif

generate
if (USE_PRIMITIVE != 0) begin : gen_primitive
    wire [15:0] doa;
    wire [1:0] dopa;
    wire [15:0] dob;
    wire [1:0] dopb;

    // 综合/原语验证分支：逻辑地址最高位划分Stage2与Stage3历史区，
    // 一个36位SDP字承载DATA_W位有符号样本，端口A读、端口B写。
    // 例化说明：调用 RAMB18E1 双口块 RAM 原语，集中保存滤波系数或历史样本并提供同步读写。
    RAMB18E1 #(
        .RAM_MODE("SDP"),
        .READ_WIDTH_A(36),
        .READ_WIDTH_B(0),
        .WRITE_WIDTH_A(0),
        .WRITE_WIDTH_B(36),
        .DOA_REG(0),
        .DOB_REG(0),
        .WRITE_MODE_A("READ_FIRST"),
        .WRITE_MODE_B("READ_FIRST"),
        .SIM_DEVICE("7SERIES")
    ) u_stage23_history_ramb18e1 (
        .DOADO(doa),
        .DOPADOP(dopa),
        .DOBDO(dob),
        .DOPBDOP(dopb),
        .ADDRARDADDR({4'b0000, read_addr, 5'b00000}),
        .ADDRBWRADDR({4'b0000, write_addr, 5'b00000}),
        .CLKARDCLK(clk),
        .CLKBWRCLK(clk),
        .ENARDEN(1'b1),
        .ENBWREN(write_enable),
        .REGCEAREGCE(1'b1),
        .REGCEB(1'b1),
        .RSTRAMARSTRAM(1'b0),
        .RSTRAMB(1'b0),
        .RSTREGARSTREG(1'b0),
        .RSTREGB(1'b0),
        .WEA(2'b00),
        .WEBWE({4{write_enable}}),
        .DIADI(write_data[15:0]),
        .DIPADIP(2'b00),
        .DIBDI({{(32-DATA_W){1'b0}}, write_data[DATA_W-1:16]}),
        .DIPBDIP(2'b00)
    );

    assign read_data = {dob[DATA_W-17:0], doa};
end else begin : gen_behavioral
    // 纯RTL行为分支：复现原语同步读写延迟，供独立回归与逐位比较使用。
    reg signed [DATA_W-1:0] memory [0:(1<<ADDR_W)-1];
    reg signed [DATA_W-1:0] read_data_q;

    always @(posedge clk) begin
        read_data_q <= memory[read_addr];
        if (write_enable)
            memory[write_addr] <= write_data;
    end

    assign read_data = read_data_q;
end
endgenerate

`ifndef SYNTHESIS
    initial begin
        if (DATA_W < 17 || DATA_W > 32)
            $fatal(1, "Stage2/3 RAMB18 SDP DATA_W must be 17..32");
        if (ADDR_W != 5)
            $fatal(1, "Stage2/3 RAMB18 SDP expects 32 logical words");
        if (SIM_USE_PRIMITIVE != 0 && SIM_USE_PRIMITIVE != 1)
            $fatal(1, "SIM_USE_PRIMITIVE must be 0 or 1");
    end
`endif

endmodule
