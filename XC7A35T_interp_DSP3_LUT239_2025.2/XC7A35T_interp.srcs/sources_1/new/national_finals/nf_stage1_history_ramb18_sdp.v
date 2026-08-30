`timescale 1ns / 1ps

//=============================================================
// 文件名       : nf_stage1_history_ramb18_sdp.v
// 模块名       : nf_stage1_history_ramb18_sdp
// 功能简述     : Stage1 的 64×24 bit 单块 RAMB18E1 环形历史存储。
//                端口 A 每拍同步读取一个历史样本，端口 B 在有效时
//                写入最新样本，供串行对称抽头微引擎跨两拍读取一对
//                历史数据。第 0 对的当前输入走旁路，因此相位 0
//                同拍读写不会产生不确定的 BRAM 碰撞语义。
//
//                综合时固定实例化 RAMB18E1；行为仿真默认使用 reg
//                数组，也可通过 SIM_USE_PRIMITIVE=1 验证原语映射。
//
// 当前默认配置：
//                  DATA_W=24，ADDR_W=6，深度 64
//                  RAM 模式：简单双口 SDP
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-29
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-29：新增 Stage1 单 RAMB18E1 历史包装器。
//                2026-08-16：补充端口职责和仿真/综合分支说明。
//=============================================================

module nf_stage1_history_ramb18_sdp #(
    parameter integer DATA_W = 24,
    parameter integer ADDR_W = 6,
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

    // 综合/原语验证分支：一个36位SDP字承载24位样本。端口A同步读，
    // 端口B同步写；未用数据位固定为0，不依赖复位清空RAM内容。
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
    ) u_stage1_history_ramb18e1 (
        .DOADO(doa),
        .DOPADOP(dopa),
        .DOBDO(dob),
        .DOPBDOP(dopb),
        .ADDRARDADDR({3'b000, read_addr, 5'b00000}),
        .ADDRBWRADDR({3'b000, write_addr, 5'b00000}),
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
        .DIBDI({8'b0, write_data[23:16]}),
        .DIPBDIP(2'b00)
    );

    assign read_data = {dob[7:0], doa};
end else begin : gen_behavioral
    // 纯RTL行为分支：保持与RAMB18E1一致的同步读、同步写时序，便于
    // 不加载器件原语库时进行快速功能仿真。
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
        if (DATA_W != 24)
            $fatal(1, "Stage1 RAMB18 SDP expects DATA_W=24");
        if (ADDR_W != 6)
            $fatal(1, "Stage1 RAMB18 SDP expects 64 logical words");
        if (SIM_USE_PRIMITIVE != 0 && SIM_USE_PRIMITIVE != 1)
            $fatal(1, "SIM_USE_PRIMITIVE must be 0 or 1");
    end
`endif

endmodule
