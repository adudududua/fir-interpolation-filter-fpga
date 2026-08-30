`timescale 1ns / 1ps

//=============================================================
// 文件名       : bridge_valid_raw_experiment_ce.v
// 模块名       : bridge_valid_raw_experiment_ce
// 功能简述     : 速率桥接模块：缓存上游样本并按下游时钟使能节拍提交插值事务。
// 设计说明     : 本文件采用同步时序设计；复位、时钟使能、
//                有效信号和定点位宽关系均在对应代码段说明。
//                注释仅用于阐明实现，不参与综合结果。
// 设计作者     : kafeizizi
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     : 2026-08-30：统一中文文件头、模块编号与结构说明。
//=============================================================

// Experiment-only valid bridge.  It preserves the sample bits so the
// downstream DSP can evaluate whether absorbing the inter-stage quantizer is
// cheaper than the signed round/saturate bridge used by the signed-off core.
//=============================================================
// 1）模块名称：bridge_valid_raw_experiment_ce
// 功能说明：速率桥接模块：缓存上游样本并按下游时钟使能节拍提交插值事务。
// 工程版本：Vivado 2025.2。
//=============================================================
module bridge_valid_raw_experiment_ce #(
    parameter integer DATA_W = 24
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire signed [DATA_W-1:0]     in_data,
    input  wire                         in_valid,
    input  wire                         ce_out_next,
    input  wire                         phase_current,
    output wire signed [DATA_W-1:0]     out_data,
    output wire                         out_valid
);

    reg                     pending;
    wire                    consume_now = pending && ce_out_next && !phase_current;

    // The upstream registered output remains stable until this bridge is
    // consumed; keeping the data combinational avoids duplicating DATA_W FFs.
    assign out_data = in_data;
    assign out_valid = pending;

    always @(posedge clk) begin
        if (!rst_n) begin
            pending <= 1'b0;
        end
        else begin
            if (consume_now)
                pending <= in_valid;
            else if (in_valid)
                pending <= 1'b1;
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && pending && !consume_now && in_valid)
            $fatal(1, "raw experiment bridge input overwrite");
    end
`endif

endmodule
