`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_board_reference.v
// 模块名       : tb_board_reference
// 功能简述     : 板级公共数据通路参考向量生成测试。按真实发布参数输出模式/采样率对应的连续 24 位监测样本与绝对索引。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
// 从板级构建实际例化的公共数据通路生成连续、逐位一致的参考向量。
// 外层脚本通过编译宏指定采样率家族、插值模式和输出点数。
module tb_board_reference;
`ifdef REF_FAMILY_48K
    localparam integer FAMILY_48K = 1;
`else
    localparam integer FAMILY_48K = 0;
`endif
`ifdef REF_MODE_1X
    localparam integer MODE = 0;
`elsif REF_MODE_4X
    localparam integer MODE = 1;
`elsif REF_MODE_8X
    localparam integer MODE = 2;
`else
    localparam integer MODE = 3;
`endif
`ifdef REF_SAMPLE_COUNT
    localparam integer SAMPLE_COUNT = `REF_SAMPLE_COUNT;
`else
    localparam integer SAMPLE_COUNT = 131072;
`endif
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    wire dac_clk_unused;
    wire [7:0] dac_data_unused;
    wire [1:0] mode_led;
    wire signed [23:0] monitor_sample;
    wire monitor_valid;
    wire [31:0] monitor_sample_index;
    integer output_file;
    integer observed = 0;

    // 对逐周期 RTL 仿真而言，时钟的绝对频率不影响结果。这里使用 10 ns
    // 周期以加快四种模式的向量生成，同时保持板级 CE 时序关系不变。
    always #5 clk = ~clk;

    demo_interp_dac8_audio_pcm_common #(
        .USE_PHASE7_FOLDED(1),
        .USE_PHASE7_LUTRAM_STAGE23(1),
        .USE_PHASE7_BRAM_STAGE23_HISTORY(1),
        .USE_PHASE7_UNIFIED_BRAM_STAGE23_HISTORY(1),
        .USE_NATIONAL_FINALS_SINGLE_BRAM_STAGE1(1),
        .USE_PHASE7_BRAM_STAGE23_COEFF(1),
        .USE_PHASE8_PACKED_BRAM_STAGE23(0),
        .USE_PHASE7_CIC_BURST_COUNTER_DSP(0),
        .USE_NATIONAL_FINALS_DATAPATH(1),
        .USE_NATIONAL_FINALS_SERIAL_CIC_COMB(1),
        .USE_NATIONAL_FINALS_N3_HOLD_EQUIV(1),
        .USE_NATIONAL_FINALS_CIC_COMB_DSP(0),
        .USE_NATIONAL_FINALS_STAGE1_DSP48_PREADDER(1),
        .USE_NATIONAL_FINALS_NARROW_STAGE23(1),
        .USE_NATIONAL_FINALS_P3_JOINT_STAGE3(1),
        .USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE(2),
        .USE_NATIONAL_FINALS_STAGE2_DATA_W(20)
    ) dut (
        .force_mute(1'b0),
        .clk_audio_128x(clk),
        .rst_n(rst_n),
        .family_48k(FAMILY_48K != 0),
        .mode_sel(MODE[1:0]),
        .external_source_enable(1'b0),
        .external_sample(24'sd0),
        .external_sample_update(1'b0),
        .input_sample_ce(),
        .dac_clk(dac_clk_unused),
        .dac_data(dac_data_unused),
        .mode_led(mode_led),
        .monitor_sample(monitor_sample),
        .monitor_valid(monitor_valid),
        .monitor_sample_index(monitor_sample_index)
    );

    always @(posedge clk) begin
        if (rst_n && monitor_valid) begin
            if (monitor_sample_index !== observed[31:0])
                $fatal(1, "参考序号不连续：实际 %0d，期望 %0d",
                       monitor_sample_index, observed);
            $fdisplay(output_file, "%0d", $signed(monitor_sample));
            observed = observed + 1;
            if (observed == SAMPLE_COUNT) begin
                $fclose(output_file);
                $display("通过：采样率家族=%0d，模式=%0d，已写入 %0d 个精确板级样本",
                         FAMILY_48K, MODE, observed);
                $finish;
            end
        end
    end

    initial begin
        if (MODE < 0 || MODE > 3 || SAMPLE_COUNT < 4096)
            $fatal(1, "参考向量参数无效");
        output_file = $fopen("rtl_reference.txt", "w");
        if (output_file == 0)
            $fatal(1, "无法创建 rtl_reference.txt");
        repeat (20) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
    end

    initial begin
        // 1x 模式每个样本需要 128 个时钟；为所有模式预留充足的超时余量。
        repeat (SAMPLE_COUNT * 160 + 20000) @(posedge clk);
        $fatal(1, "参考向量生成超时，当前已生成 %0d 个样本", observed);
    end
endmodule
