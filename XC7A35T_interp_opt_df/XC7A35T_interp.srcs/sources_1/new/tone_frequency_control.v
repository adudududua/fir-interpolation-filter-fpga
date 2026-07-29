`timescale 1ns / 1ps
//=============================================================
// 文件名       : tone_frequency_control.v
// 模块名       : tone_frequency_control
// 功能简述     : 根据矩阵键盘 SW5～SW8 控制输入正弦波频率。
//                  SW5：增加 1kHz，20kHz 后回到 1kHz；
//                  SW6：减少 1kHz，1kHz 后回到 20kHz；
//                  SW7：恢复默认 15kHz；
//                  SW8：开启或关闭自动扫频。
//                手动调节和复位频率会自动退出扫频模式。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-18
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-18：新增 1kHz 步进和自动扫频控制。
//=============================================================

module tone_frequency_control #(
    parameter integer AUTO_STEP_CYCLES = 20000000
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       key_strobe,
    input  wire [3:0] key_code,

    output reg  [4:0] tone_khz,
    output reg        auto_sweep
);

    function integer calc_width;
        input integer value;
        integer work;
        begin
            work = value - 1;
            calc_width = 0;
            while (work > 0) begin
                calc_width = calc_width + 1;
                work = work >> 1;
            end
            if (calc_width < 1)
                calc_width = 1;
        end
    endfunction

    localparam integer AUTO_CNT_W = calc_width(AUTO_STEP_CYCLES);

    (* use_dsp = "no" *) reg [AUTO_CNT_W-1:0] auto_step_counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tone_khz          <= 5'd15;
            auto_sweep        <= 1'b0;
            auto_step_counter <= {AUTO_CNT_W{1'b0}};
        end
        else begin
            if (key_strobe) begin
                case (key_code)
                    4'd4: begin
                        tone_khz   <= (tone_khz >= 5'd20) ? 5'd1 :
                                      tone_khz + 5'd1;
                        auto_sweep <= 1'b0;
                    end

                    4'd5: begin
                        tone_khz   <= (tone_khz <= 5'd1) ? 5'd20 :
                                      tone_khz - 5'd1;
                        auto_sweep <= 1'b0;
                    end

                    4'd6: begin
                        tone_khz   <= 5'd15;
                        auto_sweep <= 1'b0;
                    end

                    4'd7: begin
                        auto_sweep <= ~auto_sweep;
                    end

                    default: begin
                        tone_khz   <= tone_khz;
                        auto_sweep <= auto_sweep;
                    end
                endcase

                auto_step_counter <= {AUTO_CNT_W{1'b0}};
            end
            else if (auto_sweep) begin
                if (auto_step_counter == AUTO_STEP_CYCLES - 1) begin
                    auto_step_counter <= {AUTO_CNT_W{1'b0}};
                    tone_khz <= (tone_khz >= 5'd20) ? 5'd1 : tone_khz + 5'd1;
                end
                else begin
                    auto_step_counter <= auto_step_counter +
                                         {{(AUTO_CNT_W-1){1'b0}}, 1'b1};
                end
            end
            else begin
                auto_step_counter <= {AUTO_CNT_W{1'b0}};
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (AUTO_STEP_CYCLES < 1)
            $fatal(1, "AUTO_STEP_CYCLES must be positive");
    end
`endif

endmodule
