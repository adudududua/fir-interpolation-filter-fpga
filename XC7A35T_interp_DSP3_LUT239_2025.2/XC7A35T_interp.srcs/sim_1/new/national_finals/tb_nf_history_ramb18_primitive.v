`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_nf_history_ramb18_primitive.v
// 模块名       : tb_nf_history_ramb18_primitive
// 功能简述     : Stage1、Stage2/3 历史样本 RAMB18E1 原语一致性测试平台。
//                同时例化行为模型分支和器件原语分支，以相同读写地址、
//                写使能及随机有符号样本驱动二者，逐周期比较同步读数据，
//                用于确认综合位流采用的 RAMB18E1 位宽、地址和读写时序
//                与 RTL 仿真行为模型完全一致。
// 当前默认配置 : Stage1 为 64x24 位，Stage2/3 为 32x22 位；
//                候选实例单独启用 SIM_USE_PRIMITIVE，不全局定义 SYNTHESIS。
// 设计作者     : kafeizizi
// 创建日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado Simulator 2025.2
// 修订记录     : V2025.2 统一文件头并补充中文测试结构说明。
//=============================================================
module tb_nf_history_ramb18_primitive;
    reg clk = 1'b0;

    reg [5:0] s1_read_addr = 6'd0;
    reg s1_write_enable = 1'b0;
    reg [5:0] s1_write_addr = 6'd0;
    reg signed [23:0] s1_write_data = 24'sd0;
    wire signed [23:0] s1_read_behavioral;
    wire signed [23:0] s1_read_primitive;

    reg [4:0] s23_read_addr = 5'd0;
    reg s23_write_enable = 1'b0;
    reg [4:0] s23_write_addr = 5'd0;
    reg signed [21:0] s23_write_data = 22'sd0;
    wire signed [21:0] s23_read_behavioral;
    wire signed [21:0] s23_read_primitive;

    reg signed [23:0] s1_golden [0:63];
    reg signed [21:0] s23_golden [0:31];
    reg signed [23:0] s1_expected;
    reg signed [21:0] s23_expected;
    integer i;
    integer cycle;
    integer seed_data = 32'h13579bdf;
    integer seed_ctrl = 32'h2468ace1;

    always #5 clk = ~clk;

    nf_stage1_history_ramb18_sdp #(
        .SIM_USE_PRIMITIVE(0)
    ) u_s1_behavioral (
        .clk(clk),
        .read_addr(s1_read_addr),
        .read_data(s1_read_behavioral),
        .write_enable(s1_write_enable),
        .write_addr(s1_write_addr),
        .write_data(s1_write_data)
    );

    nf_stage1_history_ramb18_sdp #(
        .SIM_USE_PRIMITIVE(1)
    ) u_s1_primitive (
        .clk(clk),
        .read_addr(s1_read_addr),
        .read_data(s1_read_primitive),
        .write_enable(s1_write_enable),
        .write_addr(s1_write_addr),
        .write_data(s1_write_data)
    );

    nf_stage23_history_ramb18_sdp #(
        .SIM_USE_PRIMITIVE(0)
    ) u_s23_behavioral (
        .clk(clk),
        .read_addr(s23_read_addr),
        .read_data(s23_read_behavioral),
        .write_enable(s23_write_enable),
        .write_addr(s23_write_addr),
        .write_data(s23_write_data)
    );

    nf_stage23_history_ramb18_sdp #(
        .SIM_USE_PRIMITIVE(1)
    ) u_s23_primitive (
        .clk(clk),
        .read_addr(s23_read_addr),
        .read_data(s23_read_primitive),
        .write_enable(s23_write_enable),
        .write_addr(s23_write_addr),
        .write_data(s23_write_data)
    );

    task check_outputs;
        begin
            if (s1_read_behavioral !== s1_expected ||
                s1_read_primitive !== s1_expected) begin
                $display("Stage1 history mismatch cycle=%0d addr=%0d expected=%0d behavioral=%0d primitive=%0d",
                         cycle, s1_read_addr, s1_expected,
                         s1_read_behavioral, s1_read_primitive);
                $fatal(1, "Stage1 history RAMB18 primitive mismatch");
            end
            if (s23_read_behavioral !== s23_expected ||
                s23_read_primitive !== s23_expected) begin
                $display("Stage23 history mismatch cycle=%0d addr=%0d expected=%0d behavioral=%0d primitive=%0d",
                         cycle, s23_read_addr, s23_expected,
                         s23_read_behavioral, s23_read_primitive);
                $fatal(1, "Stage23 history RAMB18 primitive mismatch");
            end
        end
    endtask

    initial begin
        // 等待UNISIM全局复位释放后再访问RAM，避免原语启动期未知态干扰比较。
        #120;

        // 通过正常写端口初始化每一个逻辑存储字，而不直接修改内部数组。
        for (i = 0; i < 64; i = i + 1) begin
            @(negedge clk);
            s1_write_enable = 1'b1;
            s1_write_addr = i[5:0];
            s1_write_data = $signed((i * 24'sd7919) ^ 24'h8a31c5);
            s1_golden[i] = s1_write_data;
            if (i < 32) begin
                s23_write_enable = 1'b1;
                s23_write_addr = i[4:0];
                s23_write_data = $signed((i * 22'sd4051) ^ 22'h25a39d);
                s23_golden[i] = s23_write_data;
            end else begin
                s23_write_enable = 1'b0;
            end
        end

        @(negedge clk);
        s1_write_enable = 1'b0;
        s23_write_enable = 1'b0;

        // 全地址扫描验证完整逻辑地址映射及有符号数据打包顺序。
        for (cycle = 0; cycle < 128; cycle = cycle + 1) begin
            @(negedge clk);
            s1_read_addr = cycle[5:0];
            s23_read_addr = cycle[4:0];
            s1_expected = s1_golden[cycle[5:0]];
            s23_expected = s23_golden[cycle[4:0]];
            @(posedge clk);
            #1 check_outputs;
        end

        // 执行随机并发读写，并覆盖有符号正、负满量程等关键边界值。
        // 测试有意避免同地址读写碰撞，因为签核滤波器对刚到达样本采用旁路，
        // 不依赖器件在地址碰撞时的特定读写语义。
        for (cycle = 0; cycle < 5000; cycle = cycle + 1) begin
            @(negedge clk);
            s1_read_addr = $random(seed_ctrl);
            s23_read_addr = $random(seed_ctrl);
            s1_write_enable = (($random(seed_ctrl) & 3) == 0);
            s23_write_enable = (($random(seed_ctrl) & 3) == 0);
            s1_write_addr = $random(seed_ctrl);
            s23_write_addr = $random(seed_ctrl);
            if (s1_write_enable && s1_write_addr == s1_read_addr)
                s1_write_addr = s1_write_addr + 6'd1;
            if (s23_write_enable && s23_write_addr == s23_read_addr)
                s23_write_addr = s23_write_addr + 5'd1;

            if (cycle == 0)
                s1_write_data = 24'sh7fffff;
            else if (cycle == 1)
                s1_write_data = -24'sh800000;
            else
                s1_write_data = $random(seed_data);
            if (cycle == 0)
                s23_write_data = 22'sh1fffff;
            else if (cycle == 1)
                s23_write_data = -22'sh200000;
            else
                s23_write_data = $random(seed_data);

            s1_expected = s1_golden[s1_read_addr];
            s23_expected = s23_golden[s23_read_addr];
            @(posedge clk);
            #1 check_outputs;
            if (s1_write_enable)
                s1_golden[s1_write_addr] = s1_write_data;
            if (s23_write_enable)
                s23_golden[s23_write_addr] = s23_write_data;
        end

        $display("HISTORY RAMB18 PRIMITIVE PASS: Stage1 64x24 and Stage2/3 32x22, sweep=128 random=5000");
        $finish;
    end
endmodule
