`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_dual_rate_test_tone_rom_source.v
// 模块名       : tb_dual_rate_test_tone_rom_source
// 功能简述     : 仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 设计说明     : 本文件采用同步时序设计；复位、时钟使能、
//                有效信号和定点位宽关系均在对应代码段说明。
//                注释仅用于阐明实现，不参与综合结果。
// 设计作者     : kafeizizi
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     : 2026-08-30：统一中文文件头、模块编号与结构说明。
//=============================================================
//=============================================================
// 1）模块名称：tb_dual_rate_test_tone_rom_source
// 功能说明：仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 工程版本：Vivado 2025.2。
//=============================================================

module tb_dual_rate_test_tone_rom_source;

    reg clk;
    reg rst_n;
    reg sample_ce;
    reg family_48k;
    wire signed [23:0] sample_out;
    wire sample_update;
    wire [7:0] sample_addr_dbg;

    reg signed [23:0] reference_rom [0:255];
    integer expected_addr;
    integer sample_index;

    // 例化说明：调用 dual_rate_test_tone_rom_source 双采样率族模块，完成时钟或测试数据的族别选择。
    dual_rate_test_tone_rom_source u_dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .sample_ce       (sample_ce),
        .family_48k      (family_48k),
        .sample_out      (sample_out),
        .sample_update   (sample_update),
        .sample_addr_dbg (sample_addr_dbg)
    );

    always #5 clk = ~clk;

    task reset_family;
        input selected_family;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            sample_ce = 1'b0;
            family_48k = selected_family;
            repeat (5) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
            repeat (3) @(posedge clk);
        end
    endtask

    task take_and_check_sample;
        input integer address_value;
        begin
            @(negedge clk);
            sample_ce = 1'b1;
            @(posedge clk);
            #1;
            if (!sample_update) begin
                $display("FAIL: sample_update missing at address %0d",
                         address_value);
                $fatal(1);
            end
            if (sample_addr_dbg !== address_value[7:0]) begin
                $display("FAIL: ROM address expected=%0d actual=%0d",
                         address_value, sample_addr_dbg);
                $fatal(1);
            end
            if (sample_out !== reference_rom[address_value]) begin
                $display("FAIL: ROM data address=%0d expected=%0d actual=%0d",
                         address_value, reference_rom[address_value],
                         sample_out);
                $fatal(1);
            end
            @(negedge clk);
            sample_ce = 1'b0;
            repeat (2) @(posedge clk);
            if (sample_update) begin
                $display("FAIL: sample_update wider than one clock");
                $fatal(1);
            end
        end
    endtask

    initial begin
        $readmemh("nf_sine_15k_dual_rate_24bit_256.mem", reference_rom);
        clk = 1'b0;
        rst_n = 1'b0;
        sample_ce = 1'b0;
        family_48k = 1'b0;
        expected_addr = 0;
        sample_index = 0;

        reset_family(1'b0);
        expected_addr = 0;
        for (sample_index = 0; sample_index < 150;
             sample_index = sample_index + 1) begin
            take_and_check_sample(expected_addr);
            if (expected_addr == 146)
                expected_addr = 0;
            else
                expected_addr = expected_addr + 1;
        end

        reset_family(1'b1);
        expected_addr = 147;
        for (sample_index = 0; sample_index < 20;
             sample_index = sample_index + 1) begin
            take_and_check_sample(expected_addr);
            if (expected_addr == 162)
                expected_addr = 147;
            else
                expected_addr = expected_addr + 1;
        end

        reset_family(1'b0);
        take_and_check_sample(0);

        $display("PASS: dual-rate ROM data, wrap, and synchronous family reset");
        $finish;
    end

endmodule
