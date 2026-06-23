`timescale 1ns / 1ps

module interp4_ctrl(
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire signed [23:0]      x_in,
    input  wire                    x_in_valid,

    output reg  signed [23:0]      fir_in,
    output reg                     fir_in_valid,

    // 下面两个输出主要用于调试观察
    output reg  [1:0]              phase,
    output reg  signed [23:0]      sample_buf
);

    // 内部相位计数器：0,1,2,3 循环
    reg [1:0] phase_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_cnt     <= 2'd0;
            phase         <= 2'd0;
            sample_buf    <= 24'sd0;
            fir_in        <= 24'sd0;
            fir_in_valid  <= 1'b0;
        end
        else begin
            // 把"本周期实际使用的相位"打出来，便于观察
            phase <= phase_cnt;

            // 对于 FIR 来说，每个时钟都输入一个样本
            // 这个样本要么是真实输入，要么是补的 0
            fir_in_valid <= 1'b1;

            case (phase_cnt)
                2'd0: begin
                    // phase=0 时，应该送入一个真实输入样本
                    if (x_in_valid) begin
                        sample_buf <= x_in;   // 缓存真实输入样本
                        fir_in     <= x_in;   // 本周期送入 FIR
                    end
                    else begin
                        // 如果 phase=0 但没有输入有效，就送 0
                        fir_in <= 24'sd0;
                    end
                end

                2'd1,
                2'd2,
                2'd3: begin
                    // 其余 3 个周期补 0
                    fir_in <= 24'sd0;
                end

                default: begin
                    fir_in <= 24'sd0;
                end
            endcase

            // 相位循环：0 -> 1 -> 2 -> 3 -> 0
            if (phase_cnt == 2'd3)
                phase_cnt <= 2'd0;
            else
                phase_cnt <= phase_cnt + 2'd1;
        end
    end

endmodule