`timescale 1ns / 1ps

module interp2_ctrl_ce(
    input  wire                    clk,         // 系统时钟
    input  wire                    rst_n,       // 低有效复位

    input  wire                    ce_out,      // 2x 级输出采样使能；只有 ce_out=1 时，相位才推进

    input  wire signed [23:0]      x_in,        // 输入给 2x 级的原始样本
    input  wire                    x_in_valid,  // 输入样本有效（应当每 2 个输出时刻来 1 次）

    output reg  signed [23:0]      fir_in,        // 送入 2x FIR 的补零后序列
    output reg                     fir_in_valid,  // FIR 输入有效
    output reg                     phase,         // 2x 相位：0/1
    output reg  signed [23:0]      sample_buf     // 最近一次缓存的真实输入样本
);

    //====================================================
    // 内部相位计数器：
    // phase_cnt = 0 -> 送真实输入
    // phase_cnt = 1 -> 补零
    // 只在 ce_out=1 时推进
    //====================================================
    reg phase_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_cnt    <= 1'b1;
            phase        <= 1'b1;
            sample_buf   <= 24'sd0;
            fir_in       <= 24'sd0;
            fir_in_valid <= 1'b0;
        end
        else begin
            // 默认本拍不送新 FIR 输入
            fir_in_valid <= 1'b0;

            // 只有 ce_out=1 时，才认为到了“一个 2x 输出采样时刻”
            if (ce_out) begin
                // 输出当前相位，便于调试
                phase <= phase_cnt;

                // 到了一个输出采样时刻，本拍送一个 FIR 输入
                fir_in_valid <= 1'b1;

                case (phase_cnt)
                    1'b0: begin
                        // 相位 0：送真实输入
                        if (x_in_valid) begin
                            sample_buf <= x_in;
                            fir_in     <= x_in;
                        end
                        else begin
                            // 如果相位 0 但没有新样本，则补 0
                            fir_in <= 24'sd0;
                        end
                    end

                    1'b1: begin
                        // 相位 1：补 0
                        fir_in <= 24'sd0;
                    end

                    default: begin
                        fir_in <= 24'sd0;
                    end
                endcase

                // 相位只在 ce_out=1 时推进
                phase_cnt <= ~phase_cnt;
            end
        end
    end

endmodule