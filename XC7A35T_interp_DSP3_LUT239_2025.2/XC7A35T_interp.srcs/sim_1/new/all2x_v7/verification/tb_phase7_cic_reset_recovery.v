`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_phase7_cic_reset_recovery.v
// 模块名       : tb_phase7_cic_reset_recovery
// 功能简述     : Phase 7 N=3 CIC 核心中途复位与冷启动恢复测试。
//                分别在 pending 以及 burst 剩余 15、8、1 拍时
//                异步复位，检查所有状态清零；复位释放后与独立
//                冷启动参考实例逐拍比较，要求完全一致。
//
// 当前默认配置：
//                  输入位宽：20bit signed
//                  CIC 参数：R=16，M=1，N=3
//                  末级裁剪：0 LSB
//                  复位场景：pending、remaining=15/8/1
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-14
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-14：新增 CIC burst 中途复位恢复测试。
//=============================================================

module tb_phase7_cic_reset_recovery;

    localparam integer RECOVERY_INPUT_COUNT = 8;
    localparam integer RECOVERY_OUTPUT_COUNT = RECOVERY_INPUT_COUNT * 16;

    reg clk;
    reg rst_dut_n;
    reg rst_ref_n;
    reg signed [19:0] x_in;
    reg x_in_valid;
    reg signed [19:0] recovery_mem [0:RECOVERY_INPUT_COUNT-1];

    wire signed [19:0] dut_y;
    wire dut_valid;
    wire [4:0] dut_remaining;
    wire dut_pending;
    wire signed [19:0] ref_y;
    wire ref_valid;

    integer mismatch_count;
    integer compare_count;
    integer scenario_index;
    integer drive_index;

    cic_interp16_core_ce #(
        .DATA_W(20), .CIC_ORDER(3), .FINAL_PRUNE_LSB(0)
    ) u_dut (
        .clk(clk), .rst_n(rst_dut_n), .ce_out(1'b1),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(dut_y), .y_out_valid(dut_valid),
        .burst_remaining_dbg(dut_remaining),
        .pending_dbg(dut_pending)
    );

    cic_interp16_core_ce #(
        .DATA_W(20), .CIC_ORDER(3), .FINAL_PRUNE_LSB(0)
    ) u_cold_reference (
        .clk(clk), .rst_n(rst_ref_n), .ce_out(1'b1),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(ref_y), .y_out_valid(ref_valid),
        .burst_remaining_dbg(), .pending_dbg()
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(negedge clk) begin
        if (rst_dut_n && rst_ref_n && compare_count < RECOVERY_OUTPUT_COUNT) begin
            if (dut_valid !== ref_valid) begin
                mismatch_count = mismatch_count + 1;
                $display("Reset recovery valid mismatch scenario=%0d index=%0d",
                    scenario_index, compare_count);
            end
            if (dut_valid && ref_valid) begin
                if (^dut_y === 1'bx || ^ref_y === 1'bx || dut_y !== ref_y) begin
                    mismatch_count = mismatch_count + 1;
                    if (mismatch_count <= 20)
                        $display("Reset recovery data mismatch scenario=%0d index=%0d dut=%0d ref=%0d",
                            scenario_index, compare_count,
                            $signed(dut_y), $signed(ref_y));
                end
                compare_count = compare_count + 1;
            end
        end
    end

    task assert_dut_state_zero;
        begin
            #1;
            if (dut_valid !== 1'b0 || dut_pending !== 1'b0 ||
                    dut_remaining !== 5'd0 ||
                    u_dut.comb_delay[0] !== 32'sd0 ||
                    u_dut.comb_delay[1] !== 32'sd0 ||
                    u_dut.comb_delay[2] !== 32'sd0 ||
                    u_dut.integrator_state[0] !== 32'sd0 ||
                    u_dut.integrator_state[1] !== 32'sd0 ||
                    u_dut.final_integrator_state !== 32'sd0 ||
                    u_dut.burst_sample !== 32'sd0) begin
                mismatch_count = mismatch_count + 1;
                $display("Reset state leak scenario=%0d", scenario_index);
            end
        end
    endtask

    task send_one_sample;
        input signed [19:0] sample_value;
        begin
            @(negedge clk);
            x_in = sample_value;
            x_in_valid = 1'b1;
            @(negedge clk);
            x_in_valid = 1'b0;
            x_in = 20'sd0;
        end
    endtask

    task prepare_and_reset;
        input integer remaining_target;
        begin
            rst_dut_n = 1'b0;
            rst_ref_n = 1'b0;
            x_in_valid = 1'b0;
            x_in = 20'sd0;
            repeat (4) @(negedge clk);
            rst_dut_n = 1'b1;

            send_one_sample(20'sd12345);
            if (remaining_target < 0) begin
                while (dut_pending !== 1'b1)
                    @(negedge clk);
            end
            else begin
                while (dut_remaining !== remaining_target[4:0])
                    @(negedge clk);
            end

            rst_dut_n = 1'b0;
            assert_dut_state_zero();
            repeat (3) @(negedge clk);
        end
    endtask

    task run_cold_recovery;
        begin
            compare_count = 0;
            rst_dut_n = 1'b1;
            rst_ref_n = 1'b1;
            for (drive_index = 0; drive_index < RECOVERY_INPUT_COUNT;
                 drive_index = drive_index + 1) begin
                send_one_sample(recovery_mem[drive_index]);
                repeat (14) @(negedge clk);
            end
            while (compare_count < RECOVERY_OUTPUT_COUNT)
                @(negedge clk);
            repeat (2) @(negedge clk);
        end
    endtask

    initial begin
        recovery_mem[0] = 20'sd1;
        recovery_mem[1] = 20'sd0;
        recovery_mem[2] = 20'sd0;
        recovery_mem[3] = 20'sd0;
        recovery_mem[4] = 20'sd32768;
        recovery_mem[5] = -20'sd32768;
        recovery_mem[6] = 20'sd524287;
        recovery_mem[7] = -20'sd524288;

        rst_dut_n = 1'b0;
        rst_ref_n = 1'b0;
        x_in = 20'sd0;
        x_in_valid = 1'b0;
        mismatch_count = 0;
        compare_count = 0;
        scenario_index = 0;

        scenario_index = 1;
        prepare_and_reset(-1);
        run_cold_recovery();

        scenario_index = 2;
        prepare_and_reset(15);
        run_cold_recovery();

        scenario_index = 3;
        prepare_and_reset(8);
        run_cold_recovery();

        scenario_index = 4;
        prepare_and_reset(1);
        run_cold_recovery();

        if (mismatch_count != 0)
            $fatal(1, "PHASE7 CIC RESET RECOVERY FAIL mismatch=%0d",
                mismatch_count);
        $display("PHASE7 CIC RESET RECOVERY PASS: pending and remaining 15/8/1 all cold-start clean.");
        $finish;
    end

endmodule

