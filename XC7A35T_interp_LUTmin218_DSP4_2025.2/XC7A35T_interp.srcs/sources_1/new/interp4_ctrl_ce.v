`timescale 1ns / 1ps

module interp4_ctrl_ce(
    input  wire                    clk,         // 系统时钟（板载 50MHz）
    input  wire                    rst_n,       // 低有效复位

    input  wire                    ce_out,      // 输出采样使能：只有 ce_out=1 时，插值相位才前进一步

    input  wire signed [23:0]      x_in,        // 原始输入样本
    input  wire                    x_in_valid,  // 原始输入样本有效（只应在每 4 个 ce_out 中出现 1 次）

    output reg  signed [23:0]      fir_in,         // 送给 FIR 的补零后数据
    output reg                     fir_in_valid,   // 送给 FIR 的有效信号（只在 ce_out=1 时拉高）

    // 调试观察信号
    output reg  [1:0]              phase,          // 当前 4 倍插值相位：0/1/2/3
    output reg  signed [23:0]      sample_buf      // 最近一次缓存的真实输入样本
);

    //====================================================
    // 内部 2 位相位计数器
    // 只在 ce_out=1 时更新
    //====================================================
    reg [1:0] phase_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_cnt    <= 2'd0;
            phase        <= 2'd0;
            sample_buf   <= 24'sd0;
            fir_in       <= 24'sd0;
            fir_in_valid <= 1'b0;
        end
        else begin
            // 默认情况下，当前拍不送新 FIR 输入
            // 只有 ce_out=1 时，才认为到了"一个输出采样时刻"
            fir_in_valid <= 1'b0;

            if (ce_out) begin
                // 把"当前正在使用的相位"输出给外部，方便 ILA 观察
                phase <= phase_cnt;

                // 到了一个输出采样时刻，本拍送一个 FIR 输入
                fir_in_valid <= 1'b1;

                case (phase_cnt)
                    2'd0: begin
                        // 相位 0：应该送真实输入样本
                        if (x_in_valid) begin
                            sample_buf <= x_in;   // 缓存真实样本
                            fir_in     <= x_in;   // 本拍送入 FIR
                        end
                        else begin
                            // 如果 phase=0 但没有新的输入样本，则补 0
                            fir_in <= 24'sd0;
                        end
                    end

                    2'd1,
                    2'd2,
                    2'd3: begin
                        // 其余 3 个相位：补 0
                        fir_in <= 24'sd0;
                    end

                    default: begin
                        fir_in <= 24'sd0;
                    end
                endcase

                // 相位只在 ce_out=1 时前进一步
                if (phase_cnt == 2'd3)
                    phase_cnt <= 2'd0;
                else
                    phase_cnt <= phase_cnt + 2'd1;
            end
        end
    end

endmodule