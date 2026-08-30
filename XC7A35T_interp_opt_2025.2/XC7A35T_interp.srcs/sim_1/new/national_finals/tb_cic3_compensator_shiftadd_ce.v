`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_cic3_compensator_shiftadd_ce.v
// 模块名       : tb_cic3_compensator_shiftadd_ce
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
// 1）模块名称：tb_cic3_compensator_shiftadd_ce
// 功能说明：仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 工程版本：Vivado 2025.2。
//=============================================================

module tb_cic3_compensator_shiftadd_ce;

    localparam integer DATA_W = 20;
    localparam integer OUT_MAX = (1 << (DATA_W-1))-1;
    localparam integer OUT_MIN = -(1 << (DATA_W-1));

    reg clk;
    reg rst_n;
    reg signed [DATA_W-1:0] x_in;
    reg x_in_valid;
    wire signed [DATA_W-1:0] y_out;
    wire y_out_valid;
    wire signed [DATA_W:0] y_out_wide;
    wire y_out_wide_valid;

    integer model_z1;
    integer model_z2;
    integer expected;
    integer expected_wide;
    integer curvature;
    integer sample_count;
    integer seed;
    integer signed20_boundary_cross_count;
    integer legacy_clip_count;

    // 例化说明：调用 cic3_compensator_shiftadd_ce 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    cic3_compensator_shiftadd_ce #(
        .DATA_W(DATA_W)
    ) u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .x_in(x_in),
        .x_in_valid(x_in_valid),
        .y_out(y_out),
        .y_out_valid(y_out_valid)
    );

    // 例化说明：调用 cic3_compensator_shiftadd_ce 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    cic3_compensator_shiftadd_ce #(
        .DATA_W(DATA_W),
        .OUTPUT_W(DATA_W+1)
    ) u_dut_wide (
        .clk(clk),
        .rst_n(rst_n),
        .x_in(x_in),
        .x_in_valid(x_in_valid),
        .y_out(y_out_wide),
        .y_out_valid(y_out_wide_valid)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task send_sample;
        input integer value;
        input integer gap_cycles;
        integer one_gap;
        integer signed_value;
        begin
            signed_value = value & ((1 << DATA_W)-1);
            if (signed_value > OUT_MAX)
                signed_value = signed_value-(1 << DATA_W);
            @(negedge clk);
            x_in <= signed_value;
            x_in_valid <= 1'b1;
            curvature = 2*model_z1-signed_value-model_z2;
            expected_wide = model_z1+(curvature >>> 3);
            expected = expected_wide;
            if (expected_wide > OUT_MAX || expected_wide < OUT_MIN)
                signed20_boundary_cross_count =
                    signed20_boundary_cross_count+1;
            if (expected > OUT_MAX) begin
                expected = OUT_MAX;
                legacy_clip_count = legacy_clip_count+1;
            end
            else if (expected < OUT_MIN) begin
                expected = OUT_MIN;
                legacy_clip_count = legacy_clip_count+1;
            end

            @(posedge clk);
            #1;
            if (!y_out_valid)
                $fatal(1, "Missing valid at sample %0d", sample_count);
            if ($signed(y_out) !== expected)
                $fatal(1, "Mismatch sample=%0d x=%0d actual=%0d expected=%0d",
                    sample_count, signed_value, $signed(y_out), expected);
            if (!y_out_wide_valid)
                $fatal(1, "Missing wide valid at sample %0d", sample_count);
            if ($signed(y_out_wide) !== expected_wide)
                $fatal(1, "Wide mismatch sample=%0d x=%0d actual=%0d expected=%0d",
                    sample_count, signed_value, $signed(y_out_wide),
                    expected_wide);

            model_z2 = model_z1;
            model_z1 = signed_value;
            sample_count = sample_count+1;
            @(negedge clk);
            x_in_valid <= 1'b0;
            for (one_gap = 0; one_gap < gap_cycles; one_gap = one_gap+1) begin
                @(posedge clk);
                #1;
                if (y_out_valid || y_out_wide_valid)
                    $fatal(1, "Unexpected valid in input gap");
                @(negedge clk);
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        x_in = {DATA_W{1'b0}};
        x_in_valid = 1'b0;
        model_z1 = 0;
        model_z2 = 0;
        sample_count = 0;
        signed20_boundary_cross_count = 0;
        legacy_clip_count = 0;
        seed = 32'h5A17C3E1;

        repeat (4) @(negedge clk);
        rst_n = 1'b1;

        send_sample(0, 0);
        send_sample(1, 1);
        send_sample(-1, 0);
        send_sample(OUT_MAX, 2);
        send_sample(OUT_MIN, 0);
        send_sample(OUT_MAX, 0);
        send_sample(OUT_MIN, 3);

        repeat (2000) begin
            send_sample($random(seed) & ((1 << DATA_W)-1),
                        sample_count % 3);
        end

        // 中途复位后必须与冷启动历史一致。
        rst_n = 1'b0;
        x_in_valid = 1'b0;
        repeat (3) @(negedge clk);
        model_z1 = 0;
        model_z2 = 0;
        rst_n = 1'b1;
        send_sample(12345, 0);
        send_sample(-23456, 0);

        if (signed20_boundary_cross_count == 0 || legacy_clip_count == 0)
            $fatal(1, "Signed-20/21 directed boundary was not exercised");
        if (signed20_boundary_cross_count != legacy_clip_count)
            $fatal(1, "Boundary/legacy clip accounting mismatch %0d/%0d",
                signed20_boundary_cross_count, legacy_clip_count);

        $display("NF CIC3 SHIFTADD COMPENSATOR PASS samples=%0d boundary_crossings=%0d legacy_clips=%0d",
            sample_count, signed20_boundary_cross_count, legacy_clip_count);
        $finish;
    end

endmodule
