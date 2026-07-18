`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_phase7_full_chain_reset_recovery.v
// 模块名       : tb_phase7_full_chain_reset_recovery
// 功能简述     : Phase 7 正式完整顶层的中途复位恢复测试。
//                工作实例分别运行到 Stage1 MAC、Stage2 pending、
//                Stage2/3 job、CIC pending 和 burst 剩余 15/8/1
//                时复位；释放后与冷启动参考实例逐拍比较 4x、8x、
//                128x，检查旧状态不会泄漏到新一轮输出。
//
// 当前默认配置：
//                  CIC 参数：N=3，末级裁剪0 LSB
//                  复位场景：8 种
//                  恢复比较：每场景4096个128x有效输出
//                  验收标准：valid与数据逐拍严格相等、无X
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-14
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-14：新增正式完整顶层中途复位回归。
//                2026-07-18：增加单读 LUTRAM Stage 2/3 候选开关。
//=============================================================

module tb_phase7_full_chain_reset_recovery;

`ifdef PHASE7_USE_LUTRAM_STAGE23
`define DUT_STAGE23 u_dut.gen_lutram_stage23.u_interp2_stage23_lutram_cic_dsp_ce
`else
`define DUT_STAGE23 u_dut.gen_register_stage23.u_interp2_stage23_folded_cic_dsp_ce
`endif
`define DUT_CIC u_dut.u_cic_interp16_core_dsp_ce

    localparam integer SCENARIO_COUNT = 8;
    localparam integer COMPARE_Y128_COUNT = 4096;

    reg clk;
    reg rst_dut_n;
    reg rst_ref_n;
    reg drive_enable;
    reg [6:0] ce_cnt;
    reg signed [23:0] x_in;
    reg [23:0] lfsr_state;

    wire x_in_valid = drive_enable;
    wire ce2_out = (ce_cnt[5:0] == 6'b000000);
    wire ce4_out = (ce_cnt[4:0] == 5'b00000);
    wire ce8_out = (ce_cnt[3:0] == 4'b0000);
    wire ce16_out = (ce_cnt[2:0] == 3'b000);
    wire ce32_out = (ce_cnt[1:0] == 2'b00);
    wire ce64_out = (ce_cnt[0] == 1'b0);

    wire signed [23:0] dut_y4;
    wire dut_y4_valid;
    wire signed [23:0] dut_y8;
    wire dut_y8_valid;
    wire signed [23:0] dut_y128;
    wire dut_y128_valid;
    wire signed [23:0] ref_y4;
    wire ref_y4_valid;
    wire signed [23:0] ref_y8;
    wire ref_y8_valid;
    wire signed [23:0] ref_y128;
    wire ref_y128_valid;

    integer scenario_index;
    integer mismatch_count;
    integer compare_y128_count;
    integer wait_count;
    integer compare_enable;

    interp128_all2x_v7_folded_fir_cic_top_ce #(
        .STAGE23_ACC_W(38), .CIC_ORDER(3), .FINAL_PRUNE_LSB(0),
`ifdef PHASE7_USE_LUTRAM_STAGE23
        .USE_LUTRAM_STAGE23(1),
`else
        .USE_LUTRAM_STAGE23(0),
`endif
`ifdef PHASE7_USE_BRAM_STAGE23_HISTORY
        .USE_BRAM_STAGE23_HISTORY(1),
`else
        .USE_BRAM_STAGE23_HISTORY(0),
`endif
`ifdef PHASE7_USE_BRAM_STAGE23_COEFF
        .USE_BRAM_STAGE23_COEFF(1)
`else
        .USE_BRAM_STAGE23_COEFF(0)
`endif
    ) u_dut (
        .clk(clk), .rst_n(rst_dut_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out),
        .ce8_out(ce8_out), .ce16_out(ce16_out),
        .ce32_out(ce32_out), .ce64_out(ce64_out),
        .ce128_out(1'b1), .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(dut_y128), .y_out_valid(dut_y128_valid),
        .dbg_y2(), .dbg_y2_valid(),
        .dbg_y4(dut_y4), .dbg_y4_valid(dut_y4_valid),
        .dbg_y8(dut_y8), .dbg_y8_valid(dut_y8_valid),
        .dbg_y16(), .dbg_y16_valid(),
        .dbg_y32(), .dbg_y32_valid(),
        .dbg_y64(), .dbg_y64_valid()
    );

    interp128_all2x_v7_folded_fir_cic_top_ce #(
        .STAGE23_ACC_W(38), .CIC_ORDER(3), .FINAL_PRUNE_LSB(0),
`ifdef PHASE7_USE_LUTRAM_STAGE23
        .USE_LUTRAM_STAGE23(1),
`else
        .USE_LUTRAM_STAGE23(0),
`endif
`ifdef PHASE7_USE_BRAM_STAGE23_HISTORY
        .USE_BRAM_STAGE23_HISTORY(1),
`else
        .USE_BRAM_STAGE23_HISTORY(0),
`endif
`ifdef PHASE7_USE_BRAM_STAGE23_COEFF
        .USE_BRAM_STAGE23_COEFF(1)
`else
        .USE_BRAM_STAGE23_COEFF(0)
`endif
    ) u_cold_reference (
        .clk(clk), .rst_n(rst_ref_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out),
        .ce8_out(ce8_out), .ce16_out(ce16_out),
        .ce32_out(ce32_out), .ce64_out(ce64_out),
        .ce128_out(1'b1), .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(ref_y128), .y_out_valid(ref_y128_valid),
        .dbg_y2(), .dbg_y2_valid(),
        .dbg_y4(ref_y4), .dbg_y4_valid(ref_y4_valid),
        .dbg_y8(ref_y8), .dbg_y8_valid(ref_y8_valid),
        .dbg_y16(), .dbg_y16_valid(),
        .dbg_y32(), .dbg_y32_valid(),
        .dbg_y64(), .dbg_y64_valid()
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (!rst_dut_n) begin
            ce_cnt <= 7'd0;
            lfsr_state <= 24'h5A31C7;
            x_in <= 24'sd0;
        end
        else begin
            ce_cnt <= ce_cnt + 7'd1;
            if (ce_cnt == 7'd127) begin
                lfsr_state <= {lfsr_state[22:0],
                    lfsr_state[23] ^ lfsr_state[22] ^
                    lfsr_state[17] ^ lfsr_state[0]};
                x_in <= $signed(lfsr_state) >>> 2;
            end
        end
    end

    always @(negedge clk) begin
        if (compare_enable != 0) begin
            compare_node(4, dut_y4_valid, ref_y4_valid, dut_y4, ref_y4);
            compare_node(8, dut_y8_valid, ref_y8_valid, dut_y8, ref_y8);
            compare_node(128, dut_y128_valid, ref_y128_valid,
                dut_y128, ref_y128);
            if (dut_y128_valid && ref_y128_valid)
                compare_y128_count = compare_y128_count + 1;
        end
    end

    task compare_node;
        input integer rate_value;
        input dut_valid_value;
        input ref_valid_value;
        input signed [23:0] dut_data_value;
        input signed [23:0] ref_data_value;
        begin
            if (dut_valid_value !== ref_valid_value) begin
                mismatch_count = mismatch_count + 1;
                if (mismatch_count <= 20)
                    $display("Full reset valid mismatch scenario=%0d rate=%0d",
                        scenario_index, rate_value);
            end
            if (dut_valid_value && ref_valid_value) begin
                if (^dut_data_value === 1'bx ||
                        ^ref_data_value === 1'bx ||
                        dut_data_value !== ref_data_value) begin
                    mismatch_count = mismatch_count + 1;
                    if (mismatch_count <= 20)
                        $display("Full reset data mismatch scenario=%0d rate=%0d dut=%0d ref=%0d",
                            scenario_index, rate_value,
                            $signed(dut_data_value), $signed(ref_data_value));
                end
            end
        end
    endtask

    task scenario_is_ready;
        input integer test_scenario;
        output ready_value;
        begin
            ready_value = 1'b0;
            case (test_scenario)
                1: ready_value =
                    u_dut.u_interp2_stage1_strict_halfband_bram_ce.mac_active;
                2: ready_value =
                    `DUT_STAGE23.stage2_pending;
                3: ready_value =
                    `DUT_STAGE23.job_active &&
                    `DUT_STAGE23.job_stage == 2'd2;
                4: ready_value =
                    `DUT_STAGE23.job_active &&
                    `DUT_STAGE23.job_stage == 2'd3;
                5: ready_value =
                    `DUT_CIC.burst_pending;
                6: ready_value =
                    `DUT_CIC.burst_remaining == 5'd15;
                7: ready_value =
                    `DUT_CIC.burst_remaining == 5'd8;
                8: ready_value =
                    `DUT_CIC.burst_remaining == 5'd1;
                default: ready_value = 1'b0;
            endcase
        end
    endtask

    reg scenario_ready;

    task assert_pipeline_reset;
        begin
            #1;
            if (`DUT_CIC.burst_pending !== 1'b0 ||
                    `DUT_CIC.burst_remaining !== 5'd0 ||
                    `DUT_CIC.final_integrator_state !== 32'sd0)
                $fatal(1, "CIC asynchronous reset failed scenario=%0d",
                    scenario_index);
            repeat (2) @(posedge clk);
            @(negedge clk);
            if (dut_y4_valid !== 1'b0 || dut_y8_valid !== 1'b0 ||
                    dut_y128_valid !== 1'b0 ||
                    u_dut.u_interp2_stage1_strict_halfband_bram_ce.mac_active !== 1'b0 ||
                    `DUT_STAGE23.stage2_pending !== 1'b0 ||
                    `DUT_STAGE23.stage3_pending !== 1'b0 ||
                    `DUT_STAGE23.job_active !== 1'b0)
                $fatal(1, "Full pipeline reset failed scenario=%0d",
                    scenario_index);
        end
    endtask

    task run_one_scenario;
        input integer test_scenario;
        begin
            scenario_index = test_scenario;
            compare_enable = 0;
            rst_dut_n = 1'b0;
            rst_ref_n = 1'b0;
            drive_enable = 1'b0;
            repeat (4) @(negedge clk);
            rst_dut_n = 1'b1;
            drive_enable = 1'b1;

            wait_count = 0;
            scenario_ready = 1'b0;
            while (!scenario_ready && wait_count < 50000) begin
                @(negedge clk);
                scenario_is_ready(test_scenario, scenario_ready);
                wait_count = wait_count + 1;
            end
            if (!scenario_ready)
                $fatal(1, "Unable to reach reset scenario=%0d", test_scenario);

            rst_dut_n = 1'b0;
            drive_enable = 1'b0;
            assert_pipeline_reset();
            repeat (2) @(negedge clk);

            compare_y128_count = 0;
            rst_dut_n = 1'b1;
            rst_ref_n = 1'b1;
            drive_enable = 1'b1;
            compare_enable = 1;
            wait_count = 0;
            while (compare_y128_count < COMPARE_Y128_COUNT &&
                    wait_count < 30000) begin
                @(negedge clk);
                wait_count = wait_count + 1;
            end
            compare_enable = 0;
            if (compare_y128_count != COMPARE_Y128_COUNT)
                $fatal(1, "Recovery output timeout scenario=%0d count=%0d",
                    test_scenario, compare_y128_count);
            $display("PHASE7 FULL RESET scenario=%0d PASS compared=%0d y128 outputs",
                test_scenario, compare_y128_count);
        end
    endtask

    initial begin
        rst_dut_n = 1'b0;
        rst_ref_n = 1'b0;
        drive_enable = 1'b0;
        ce_cnt = 7'd0;
        x_in = 24'sd0;
        lfsr_state = 24'h5A31C7;
        scenario_index = 0;
        mismatch_count = 0;
        compare_y128_count = 0;
        wait_count = 0;
        compare_enable = 0;

        for (scenario_index = 1; scenario_index <= SCENARIO_COUNT;
             scenario_index = scenario_index + 1)
            run_one_scenario(scenario_index);

        if (mismatch_count != 0)
            $fatal(1, "PHASE7 FULL RESET RECOVERY FAIL mismatch=%0d",
                mismatch_count);
        $display("PHASE7 FULL RESET RECOVERY PASS: 8 internal-state scenarios clean.");
        $finish;
    end

endmodule

`undef DUT_STAGE23
`undef DUT_CIC

