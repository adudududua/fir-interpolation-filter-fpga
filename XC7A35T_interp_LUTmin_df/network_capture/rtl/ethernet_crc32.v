`timescale 1ns / 1ps

//=============================================================
// 文件名       : ethernet_crc32.v
// 模块名       : ethernet_crc32
// 功能简述     : 以太网 IEEE 802.3 反射式 CRC32 单字节更新函数模块，为接收 FCS 校验和发送 FCS 生成提供统一算法。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
// 反射式以太网 CRC-32 更新：多项式 0xEDB88320，最低有效位优先。
module ethernet_crc32(
    input  wire [31:0] crc_in,
    input  wire [7:0]  data_in,
    output reg  [31:0] crc_out
);
    integer i;
    reg [31:0] c;
    always @(*) begin
        c = crc_in ^ {24'd0, data_in};
        for (i = 0; i < 8; i = i + 1)
            c = c[0] ? ((c >> 1) ^ 32'hEDB88320) : (c >> 1);
        crc_out = c;
    end
endmodule
