`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_phase7_mode_switch_dynamic.v
// 模块名       : tb_phase7_mode_switch_dynamic
// 功能简述     : Phase 7 四倍率动态切换测试平台。验证 1x/4x/8x/128x 模式提交、DAC 时钟完整脉宽、数据有效性与无未知态，并覆盖不同 CIC DSP 映射配置。
//
// 设计作者     : kafeizizi
// 整理日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-08-16：保留最终板级功能与逻辑，统一中文文件头，
//                            补充模块职责、协议边界和验证目的说明。
//=============================================================
`ifdef NF_CIC_INTEGRATOR_DSP_MODE_0
`define NF_CIC_INTEGRATOR_DSP_MODE 0
`elsif NF_CIC_INTEGRATOR_DSP_MODE_1
`define NF_CIC_INTEGRATOR_DSP_MODE 1
`else
`define NF_CIC_INTEGRATOR_DSP_MODE 2
`endif

module tb_phase7_mode_switch_dynamic;

`ifdef NF_WORDLENGTH_24_22_20
    localparam integer DUT_STAGE2_DATA_W = 22;
`else
    localparam integer DUT_STAGE2_DATA_W = 20;
`endif

    localparam [1:0] MODE_1X = 2'b00;
    localparam [1:0] MODE_4X = 2'b01;
    localparam [1:0] MODE_8X = 2'b10;
    localparam [1:0] MODE_128X = 2'b11;
    localparam integer HOLD_CYCLES = 8192;
    localparam integer MEASURE_CYCLES = 4096;

    reg clk;
    reg rst_n;
    reg [1:0] mode_sel;
    reg measure_en;
    reg clock_monitor_en;
    reg [7:0] last_dac_data;

    wire dac_clk;
    wire [7:0] dac_data;
    wire [1:0] mode_led;

    integer dac_clk_edge_count;
    integer dac_data_change_count;
    integer mismatch_count;
    integer switch_count;
    integer mode_timeout;
    time last_dac_transition;
    time transition_width;
    reg have_last_transition;

    demo_interp_dac8_audio_pcm_common #(
        .USE_PHASE7_FOLDED(1),
        .USE_PHASE7_LUTRAM_STAGE23(1),
`ifdef PHASE7_USE_BRAM_STAGE23_HISTORY
        .USE_PHASE7_BRAM_STAGE23_HISTORY(1),
        .USE_PHASE7_UNIFIED_BRAM_STAGE23_HISTORY(1),
        .USE_NATIONAL_FINALS_SINGLE_BRAM_STAGE1(1),
`else
        .USE_PHASE7_BRAM_STAGE23_HISTORY(0),
`endif
`ifdef PHASE7_USE_BRAM_STAGE23_COEFF
        .USE_PHASE7_BRAM_STAGE23_COEFF(1),
`else
        .USE_PHASE7_BRAM_STAGE23_COEFF(0),
`endif
`ifdef PHASE8_USE_PACKED_BRAM_STAGE23
        .USE_PHASE8_PACKED_BRAM_STAGE23(1),
`else
        .USE_PHASE8_PACKED_BRAM_STAGE23(0),
`endif
        .USE_NATIONAL_FINALS_DATAPATH(1),
        .USE_NATIONAL_FINALS_SERIAL_CIC_COMB(1),
        .USE_NATIONAL_FINALS_N3_HOLD_EQUIV(1),
        .USE_NATIONAL_FINALS_STAGE1_DSP48_PREADDER(1),
        .USE_NATIONAL_FINALS_NARROW_STAGE23(1),
        .USE_NATIONAL_FINALS_P3_JOINT_STAGE3(1),
        .USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE(
            `NF_CIC_INTEGRATOR_DSP_MODE),
        .USE_NATIONAL_FINALS_STAGE2_DATA_W(DUT_STAGE2_DATA_W)
    ) u_dut (
        .clk_audio_128x(clk),
        .rst_n(rst_n),
        .family_48k(1'b0),
        .external_source_enable(1'b0),
        .external_sample(24'sd0),
        .external_sample_update(1'b0),
        .input_sample_ce(),
        .mode_sel(mode_sel),
        .force_mute(1'b0),
        .dac_clk(dac_clk),
        .dac_data(dac_data),
        .mode_led(mode_led)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge dac_clk) begin
        if (measure_en)
            dac_clk_edge_count = dac_clk_edge_count + 1;
    end

    always @(dac_clk) begin
        if (clock_monitor_en) begin
            if (^dac_clk === 1'bx) begin
                mismatch_count = mismatch_count + 1;
                $display("DA_CLK contains X at time=%0t", $time);
            end
            if (have_last_transition) begin
                transition_width = $time - last_dac_transition;
                if (transition_width < 5) begin
                    mismatch_count = mismatch_count + 1;
                    $display("DA_CLK runt pulse width=%0t at time=%0t mode=%0d",
                        transition_width, $time, mode_led);
                end
            end
            last_dac_transition = $time;
            have_last_transition = 1'b1;
        end
    end

    always @(dac_data) begin
        if (measure_en) begin
            if (^dac_data === 1'bx) begin
                mismatch_count = mismatch_count + 1;
                $display("DAC data contains X at time=%0t", $time);
            end
            if (dac_data !== last_dac_data)
                dac_data_change_count = dac_data_change_count + 1;
        end
        last_dac_data = dac_data;
    end

    task switch_and_measure;
        input [1:0] test_mode;
        input integer expected_edges;
        begin
            @(posedge clk);
            mode_sel <= test_mode;
            switch_count = switch_count + 1;

            mode_timeout = 0;
            while (mode_led !== test_mode && mode_timeout < 256) begin
                @(posedge clk);
                mode_timeout = mode_timeout + 1;
            end
            if (mode_led !== test_mode) begin
                mismatch_count = mismatch_count + 1;
                $display("Mode switch timeout target=%0d actual=%0d",
                    test_mode, mode_led);
            end

            repeat (HOLD_CYCLES) @(posedge clk);
            @(negedge clk);
            dac_clk_edge_count = 0;
            dac_data_change_count = 0;
            last_dac_data = dac_data;
            measure_en = 1'b1;
            repeat (MEASURE_CYCLES) @(posedge clk);
            @(negedge clk);
            measure_en = 1'b0;

            $display("Dynamic mode=%0d edges=%0d expected=%0d data_changes=%0d",
                test_mode, dac_clk_edge_count, expected_edges,
                dac_data_change_count);
            if (dac_clk_edge_count != expected_edges) begin
                mismatch_count = mismatch_count + 1;
                $display("DA_CLK edge mismatch mode=%0d got=%0d expected=%0d",
                    test_mode, dac_clk_edge_count, expected_edges);
            end
            if (dac_data_change_count < 8) begin
                mismatch_count = mismatch_count + 1;
                $display("DAC data insufficient changes mode=%0d changes=%0d",
                    test_mode, dac_data_change_count);
            end
        end
    endtask

    task run_runt_sensitive_switch;
        input [1:0] target_mode;
        begin
            @(posedge clk);
            mode_sel <= MODE_128X;
            while (mode_led !== MODE_128X)
                @(posedge clk);
            while (u_dut.ce_cnt !== 7'd0)
                @(negedge clk);
            @(posedge clk);
            mode_sel <= target_mode;
            switch_count = switch_count + 1;
            mode_timeout = 0;
            while (mode_led !== target_mode && mode_timeout < 256) begin
                @(posedge clk);
                mode_timeout = mode_timeout + 1;
            end
            if (mode_led !== target_mode) begin
                mismatch_count = mismatch_count + 1;
                $display("Runt-sensitive switch did not reach mode=%0d",
                    target_mode);
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        mode_sel = MODE_128X;
        measure_en = 1'b0;
        clock_monitor_en = 1'b0;
        last_dac_data = 8'd0;
        dac_clk_edge_count = 0;
        dac_data_change_count = 0;
        mismatch_count = 0;
        switch_count = 0;
        last_dac_transition = 0;
        transition_width = 0;
        have_last_transition = 1'b0;

        repeat (20) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (12001) @(posedge clk);
        clock_monitor_en = 1'b1;

        run_runt_sensitive_switch(MODE_1X);
        run_runt_sensitive_switch(MODE_4X);
        run_runt_sensitive_switch(MODE_8X);

        switch_and_measure(MODE_1X, 32);
        switch_and_measure(MODE_4X, 128);
        switch_and_measure(MODE_8X, 256);
        switch_and_measure(MODE_128X, 4096);
        switch_and_measure(MODE_8X, 256);
        switch_and_measure(MODE_1X, 32);
        switch_and_measure(MODE_128X, 4096);

        clock_monitor_en = 1'b0;
        if (mismatch_count != 0)
            $fatal(1, "PHASE7 DYNAMIC MODE FAIL switches=%0d mismatch=%0d",
                switch_count, mismatch_count);
        $display("PHASE7 DYNAMIC MODE PASS: %0d switches, no reset, no runt pulse or X.",
            switch_count);
        $finish;
    end

endmodule
