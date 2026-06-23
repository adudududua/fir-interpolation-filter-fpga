`timescale 1ns / 1ps

module interp2_ctrl(
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire signed [23:0]      x_in,
    input  wire                    x_in_valid,

    output reg  signed [23:0]      fir_in,
    output reg                     fir_in_valid,

    output reg                     phase,
    output reg  signed [23:0]      sample_buf
);

    //====================================================
    // 2倍插值相位计数器：
    //   phase = 0 -> 送真实输入
    //   phase = 1 -> 补零
    //====================================================
    reg phase_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_cnt    <= 1'b0;
            phase        <= 1'b0;
            sample_buf   <= 24'sd0;
            fir_in       <= 24'sd0;
            fir_in_valid <= 1'b0;
        end
        else begin
            // 对于 FIR 来说，每拍都送一个输入
            fir_in_valid <= 1'b1;

            // 输出当前相位，便于调试
            phase <= phase_cnt;

            case (phase_cnt)
                1'b0: begin
                    // 相位 0：送真实输入
                    if (x_in_valid) begin
                        sample_buf <= x_in;
                        fir_in     <= x_in;
                    end
                    else begin
                        fir_in <= 24'sd0;
                    end
                end

                1'b1: begin
                    // 相位 1：补零
                    fir_in <= 24'sd0;
                end

                default: begin
                    fir_in <= 24'sd0;
                end
            endcase

            // 每拍相位翻转
            phase_cnt <= ~phase_cnt;
        end
    end

endmodule