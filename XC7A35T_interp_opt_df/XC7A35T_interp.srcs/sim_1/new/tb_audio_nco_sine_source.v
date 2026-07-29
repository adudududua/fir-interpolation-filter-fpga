`timescale 1ns / 1ps
//=============================================================
// 文件名       : tb_audio_nco_sine_source.v
// 模块名       : tb_audio_nco_sine_source
// 功能简述     : 验证可调正弦 NCO 的查表数据、相位步进字以及
//                15kHz 切换到 20kHz 时的相位连续性。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-18
// 版本         : V2018.3
// 开发工具     : Vivado Simulator
// 修订记录     :
//                2026-07-18：新增 NCO 自动化验证平台。
//=============================================================

module tb_audio_nco_sine_source;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg sample_ce = 1'b0;
    reg [4:0] tone_khz = 5'd15;

    wire signed [23:0] sample_out;
    wire sample_update;
    wire [7:0] phase_addr_dbg;

    reg signed [23:0] golden [0:255];
    reg [31:0] expected_phase;
    reg [31:0] expected_increment;
    integer divider_count;
    integer sample_count;
    integer errors;

    audio_nco_sine_source dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .sample_ce      (sample_ce),
        .tone_khz       (tone_khz),
        .sample_out     (sample_out),
        .sample_update  (sample_update),
        .phase_addr_dbg (phase_addr_dbg)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!rst_n) begin
            divider_count <= 0;
            sample_ce <= 1'b0;
        end
        else if (divider_count == 3) begin
            divider_count <= 0;
            sample_ce <= 1'b1;
        end
        else begin
            divider_count <= divider_count + 1;
            sample_ce <= 1'b0;
        end
    end

    always @(negedge clk) begin
        if (sample_update) begin
            if (phase_addr_dbg !== expected_phase[31:24]) begin
                $display("ERROR sample %0d address=%02x expected=%02x",
                         sample_count, phase_addr_dbg, expected_phase[31:24]);
                errors = errors + 1;
            end

            if (sample_out !== golden[expected_phase[31:24]]) begin
                $display("ERROR sample %0d data=%06x expected=%06x",
                         sample_count, sample_out,
                         golden[expected_phase[31:24]]);
                errors = errors + 1;
            end

            expected_phase = expected_phase + expected_increment;
            sample_count = sample_count + 1;

            if (sample_count == 64) begin
                tone_khz = 5'd20;
                expected_increment = 32'h74198ABD;
            end

            if (sample_count == 128) begin
                if (errors == 0)
                    $display("PASS: NCO LUT, 15/20kHz phase increments and phase-continuous switching verified");
                else
                    $display("FAIL: %0d NCO verification errors", errors);
                $finish;
            end
        end
    end

    initial begin
        $readmemh("nco_sine_0p50fs_256.mem", golden);
        divider_count = 0;
        sample_count = 0;
        errors = 0;
        expected_phase = 32'd0;
        expected_increment = 32'h5713280E;

        repeat (5) @(posedge clk);
        rst_n <= 1'b1;
    end

    initial begin
        #200000;
        $display("FAIL: NCO test timeout");
        $finish;
    end

endmodule
