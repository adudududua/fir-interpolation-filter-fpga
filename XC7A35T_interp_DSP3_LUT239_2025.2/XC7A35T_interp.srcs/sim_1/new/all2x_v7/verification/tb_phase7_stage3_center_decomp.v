`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_phase7_stage3_center_decomp.v
// 模块名       : tb_phase7_stage3_center_decomp
// 功能简述     : Phase 7 Stage3 中心系数精确分解定向测试。
//                验证 35604*x = -29932*x + 2^16*x，覆盖零值、
//                正负 1、20bit 最大正负、边界值及固定种子随机数。
//
// 当前默认配置：
//                  输入位宽：20bit signed
//                  累加位宽：38bit signed
//                  随机规模：4096 点
//                  验收标准：逐点严格相等
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-14
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-14：新增中心系数拆分全边界测试。
//=============================================================

module tb_phase7_stage3_center_decomp;

    reg signed [19:0] x_value;
    reg signed [16:0] direct_coeff;
    reg signed [15:0] residual_coeff;
    reg signed [36:0] direct_product;
    reg signed [35:0] residual_product;
    reg signed [37:0] direct_extended;
    reg signed [37:0] residual_extended;
    reg signed [37:0] x_extended;
    reg signed [37:0] decomposed_result;

    integer test_count;
    integer mismatch_count;
    integer random_seed;
    integer random_index;
    reg [31:0] random_word;

    task check_value;
        input signed [19:0] sample_value;
        begin
            x_value = sample_value;
            direct_coeff = 17'sd35604;
            residual_coeff = -16'sd29932;
            #1;
            direct_product = x_value * direct_coeff;
            residual_product = x_value * residual_coeff;
            direct_extended = {{1{direct_product[36]}}, direct_product};
            residual_extended = {{2{residual_product[35]}}, residual_product};
            x_extended = {{18{x_value[19]}}, x_value};
            decomposed_result = residual_extended + (x_extended <<< 16);
            #1;
            test_count = test_count + 1;
            if (decomposed_result !== direct_extended) begin
                mismatch_count = mismatch_count + 1;
                if (mismatch_count <= 20)
                    $display("Center decomposition mismatch x=%0d direct=%0d split=%0d",
                        $signed(x_value), $signed(direct_extended),
                        $signed(decomposed_result));
            end
        end
    endtask

    initial begin
        test_count = 0;
        mismatch_count = 0;
        random_seed = 294753618;

        check_value(20'sd0);
        check_value(20'sd1);
        check_value(-20'sd1);
        check_value(20'sd524287);
        check_value(-20'sd524288);
        check_value(20'sd524286);
        check_value(-20'sd524287);
        check_value(20'sd32767);
        check_value(-20'sd32768);
        check_value(20'sd65535);
        check_value(-20'sd65536);

        for (random_index = 0; random_index < 4096;
             random_index = random_index + 1) begin
            random_word = $random(random_seed);
            check_value(random_word[19:0]);
        end

        if (mismatch_count != 0)
            $fatal(1, "PHASE7 CENTER DECOMPOSITION FAIL mismatch=%0d/%0d",
                mismatch_count, test_count);
        $display("PHASE7 CENTER DECOMPOSITION PASS: %0d values exactly equal.",
            test_count);
        $finish;
    end

endmodule

