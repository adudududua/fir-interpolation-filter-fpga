`timescale 1ns / 1ps

module tb_board_demo_competition_dac8_top;

    // 测试激励信号
    reg clk;           
    reg rst_n;         
    reg sw0, sw1, sw2; 
    
    // 被测输出信号
    wire dac_clk;      
    wire [7:0] dac_data; 
    
    // 实例化被测试模块
    board_demo_competition_dac8_top uut (
        .clk      (clk),
        .rst_n    (rst_n),
        .sw0      (sw0),
        .sw1      (sw1),
        .sw2      (sw2),
        .dac_clk  (dac_clk),
        .dac_data (dac_data)
    );
    
    // 时钟周期 50MHz = 20ns
    parameter SYS_CLK_PERIOD = 20;
    
    // 系统时钟生成
    initial begin
        clk = 0;
        forever #(SYS_CLK_PERIOD/2) clk = ~clk;
    end
    
    // 主测试流程
    initial begin
        // 初始化
        rst_n = 0;
        sw0 = 0;
        sw1 = 0;
        sw2 = 0;
        
        $display("开始测试 board_demo_competition_dac8_top");
        $display("系统时钟周期: %0dns (%0fMHz)", SYS_CLK_PERIOD, 1000.0/SYS_CLK_PERIOD);
        
        // 复位
        #(SYS_CLK_PERIOD * 50);
        $display("时间: %0t - 释放复位", $time);
        rst_n = 1;
        
        // 等待时钟稳定
        #(SYS_CLK_PERIOD * 100);
        
        // 测试 44.1kHz
        $display("\n--- 测试44.1kHz家族 (sw2=0) ---");
        sw2 = 0;
        test_single_mode();
        
        // 测试 48kHz
        $display("\n--- 测试48kHz家族 (sw2=1) ---");
        sw2 = 1;
        test_single_mode();
        
        // 模式切换
        $display("\n--- 测试模式切换 ---");
        sw2 = 0;
        #(SYS_CLK_PERIOD * 200);
        sw2 = 1;
        #(SYS_CLK_PERIOD * 200);
        
        // 结束
        #(SYS_CLK_PERIOD * 500);
        $display("时间: %0t - 测试完成", $time);
        
        $display("最终状态:");
        $display("dac_clk = %b", dac_clk);
        $display("dac_data = 0x%h", dac_data);
        
        $finish;
    end
    
    // 测试单个模式
    task test_single_mode;
        integer i;
        begin
            for(i = 0; i < 4; i = i+1) begin
                sw1 = i[1];
                sw0 = i[0];
                $display("设置模式: sw2=%b, sw1=%b, sw0=%b", sw2, sw1, sw0);
                #(SYS_CLK_PERIOD * 200);
                $display("  当前dac_data: 0x%h", dac_data);
            end
        end
    endtask

    // 波形文件
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_board_demo_competition_dac8_top);
    end

endmodule