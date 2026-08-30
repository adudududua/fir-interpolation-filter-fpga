`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_stage1_single_bram_equiv.v
// 模块名       : tb_stage1_single_bram_equiv
// 功能简述     : 仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 设计说明     : 本文件采用同步时序设计；复位、时钟使能、
//                有效信号和定点位宽关系均在对应代码段说明。
//                注释仅用于阐明实现，不参与综合结果。
// 设计作者     : kafeizizi
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     : 2026-08-30：统一中文文件头、模块编号与结构说明。
//=============================================================

// Direct bit-for-bit comparison between the signed-off dual-read Stage1 and
// the P4-B single-RAMB18 serialized-read candidate.
//=============================================================
// 1）模块名称：tb_stage1_single_bram_equiv
// 功能说明：仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 工程版本：Vivado 2025.2。
//=============================================================
module tb_stage1_single_bram_equiv;
    localparam integer TARGET_INPUTS = 640;

    reg clk;
    reg rst_n;
    reg [6:0] ce_cnt;
    reg tb_phase;
    reg signed [23:0] x_in;
    reg [23:0] lfsr;
    integer input_count;
    integer output_count;
    integer cycle_count;

    wire ce2_out = (ce_cnt[5:0] == 6'd0);
    wire signed [23:0] ref_y;
    wire ref_valid;
    wire signed [23:0] candidate_y;
    wire candidate_valid;

    // 例化说明：调用 interp2_stage1_strict_halfband_bram_ce 插值子模块，完成对应级的数据展开、滤波或模式选择。
    interp2_stage1_strict_halfband_bram_ce #(
        .ACC_W(41)
    ) u_reference (
        .clk(clk), .rst_n(rst_n), .ce_out(ce2_out),
        .x_in(x_in), .x_in_valid(1'b1),
        .y_out(ref_y), .y_out_valid(ref_valid),
        .phase_dbg(), .fir_in_dbg(), .fir_in_valid_dbg(),
        .external_coeff_addr(), .external_coeff_data(16'sd0)
    );

    // 例化说明：调用 interp2_stage1_single_bram_serial_ce 插值子模块，完成对应级的数据展开、滤波或模式选择。
    interp2_stage1_single_bram_serial_ce #(
        .ACC_W(41),
        .USE_DSP48_PREADDER(1)
    ) u_candidate (
        .clk(clk), .rst_n(rst_n), .ce_out(ce2_out),
        .x_in(x_in), .x_in_valid(1'b1),
        .y_out(candidate_y), .y_out_valid(candidate_valid),
        .phase_dbg(), .fir_in_dbg(), .fir_in_valid_dbg(),
        .external_coeff_addr(), .external_coeff_data(16'sd0)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            ce_cnt <= 7'd0;
            tb_phase <= 1'b1;
            x_in <= 24'sd0;
            lfsr <= 24'h5A_C39D;
            input_count <= 0;
        end
        else begin
            ce_cnt <= ce_cnt + 7'd1;
            if (ce2_out) begin
                if (tb_phase == 1'b0 && input_count < TARGET_INPUTS) begin
                    lfsr <= {lfsr[22:0],
                             lfsr[23] ^ lfsr[22] ^ lfsr[17] ^ lfsr[0]};
                    x_in <= $signed(lfsr) >>> (input_count[2:0]);
                    input_count <= input_count + 1;
                end
                else if (tb_phase == 1'b0) begin
                    x_in <= 24'sd0;
                end
                tb_phase <= ~tb_phase;
            end
        end
    end

    always @(negedge clk) begin
        if (rst_n) begin
            if (candidate_valid !== ref_valid)
                $fatal(1, "Stage1 valid mismatch cycle=%0d ref=%b candidate=%b",
                       cycle_count, ref_valid, candidate_valid);
            if (ref_valid) begin
                if (candidate_y !== ref_y)
                    $fatal(1, "Stage1 data mismatch output=%0d ref=%0d candidate=%0d",
                           output_count, ref_y, candidate_y);
                output_count = output_count + 1;
            end
        end
    end

    initial begin
        rst_n = 1'b0;
        output_count = 0;
        cycle_count = 0;
        repeat (20) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        while (output_count < (TARGET_INPUTS * 2 + 120) &&
               cycle_count < 100000) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        if (output_count < (TARGET_INPUTS * 2 + 120))
            $fatal(1, "Stage1 equivalence timeout outputs=%0d", output_count);

        $display("STAGE1 SINGLE BRAM EQUIVALENCE PASS: outputs=%0d, 0 LSB",
                 output_count);
        $finish;
    end
endmodule
