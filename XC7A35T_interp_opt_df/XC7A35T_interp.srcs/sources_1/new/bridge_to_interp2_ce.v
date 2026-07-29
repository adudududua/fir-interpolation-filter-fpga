`timescale 1ns / 1ps

module bridge_to_interp2_ce #(
    parameter DATA_W = 24
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // 上一级送来的数据与有效
    input  wire signed [DATA_W-1:0] in_data,
    input  wire                     in_valid,

    // 下一级 2x 模块的 ce_out
    input  wire                     ce_out_next,

    // 送给下一级 2x 模块的数据与有效
    output wire signed [DATA_W-1:0] out_data,
    output wire                     out_valid
);

    //====================================================
    // 思想：
    // 1) 上一级一旦产生一个有效样本，就先缓存起来
    // 2) 一直等到下一级真正到了 phase=0 的消费时刻
    // 3) 如果“消费旧样本”和“到来新样本”在同一拍发生，
    //    则不能把 pending 清零，而应该直接把新样本留住
    //
    // interp2_ctrl_ce 的内部相位初值是：
    //   phase_cnt <= 1'b1;
    //
    // 所以下一级真正消费真实输入的时刻，是：
    //   ce_out_next=1 且当前相位镜像 phase_mirror=0 的那一拍
    //====================================================

    reg signed [DATA_W-1:0] data_buf;
    reg                     pending;
    reg                     phase_mirror;

    assign out_data  = data_buf;
    assign out_valid = pending;

    // 当前拍下一级是否会消费“旧的 pending 样本”
    wire consume_now;
    assign consume_now = ce_out_next && (phase_mirror == 1'b0) && pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_buf     <= {DATA_W{1'b0}};
            pending      <= 1'b0;
            phase_mirror <= 1'b1;   // 与 interp2_ctrl_ce 内部初值保持一致
        end
        else begin
            //------------------------------------------------
            // 先处理数据缓存：
            // 只要上一级本拍来了新样本，就更新 data_buf
            //------------------------------------------------
            if (in_valid) begin
                data_buf <= in_data;
            end

            //------------------------------------------------
            // 再处理 pending：
            //
            // 1) 同拍“消费旧样本 + 到来新样本”：
            //    保持 pending=1，相当于无缝接上新样本
            //
            // 2) 仅消费旧样本，没有新样本：
            //    pending 清 0
            //
            // 3) 仅到来新样本：
            //    pending 置 1
            //------------------------------------------------
            if (consume_now) begin
                if (in_valid)
                    pending <= 1'b1;   // 消费旧样本，同时接住新样本
                else
                    pending <= 1'b0;   // 只消费，没有新样本
            end
            else begin
                if (in_valid)
                    pending <= 1'b1;
            end

            //------------------------------------------------
            // 相位镜像推进
            //------------------------------------------------
            if (ce_out_next) begin
                phase_mirror <= ~phase_mirror;
            end
        end
    end

endmodule