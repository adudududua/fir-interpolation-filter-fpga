`timescale 1ns / 1ps

//=============================================================
// 文件名       : interp2_ctrl_ce.v
// 模块名       : interp2_ctrl_ce
// 功能简述     : 2 倍插值级的补零序列控制器。
//                模块在 ce_out 指示的输出采样时刻推进 0/1 相位，
//                相位 0 接收并缓存真实输入，相位 1 送入零样本，
//                从而把 1x 输入流变换为供后级 FIR 使用的 2x 序列。
//
//                x_in_valid 只在真实输入到达时有效；如果相位 0
//                未收到新样本，模块按确定性规则补零，避免沿用旧值。
//                phase 与 sample_buf 端口用于板级调试和逐位对拍。
//
// 当前默认配置：
//                  输入/输出数据宽度：24 bit signed
//                  插值倍率：2x
//                  复位方式：低有效异步复位
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：按正式交付工程统一文件头并补充中文说明。
//=============================================================
//=============================================================
// 1）模块名称：interp2_ctrl_ce
// 功能说明：2 倍插值控制器：把低速输入事务展开为两个高速相位计算时隙。
// 工程版本：Vivado 2025.2。
//=============================================================

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
