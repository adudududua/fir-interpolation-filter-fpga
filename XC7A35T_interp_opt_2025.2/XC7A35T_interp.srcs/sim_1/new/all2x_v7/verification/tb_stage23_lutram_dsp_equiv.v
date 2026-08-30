`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_stage23_lutram_dsp_equiv.v
// 模块名       : tb_stage23_lutram_dsp_equiv
// 功能简述     : Stage 2/3 单读 LUTRAM 候选的 RTL 等价性测试。
//                以已通过板级验证的移位寄存器版本为参考模型，
//                按输出 valid 样点序列比较两级结果。测试允许候选
//                因串行 MAC 增加固定延迟，但要求所有有效输出严格
//                达到 0 LSB 偏差。
//
//                覆盖内容：
//                  1. 零输入与冲激输入；
//                  2. 确定性伪随机满幅输入；
//                  3. Stage 2/3 同周期请求与优先级冲突；
//                  4. 运行中异步复位及复位后重新启动。
//
// 当前默认配置：
//                  系统时钟：48MHz 等效时序
//                  Stage 2 CE 周期：48 个系统时钟
//                  Stage 3 CE 周期：24 个系统时钟
//                  Stage 2 数据位宽：22bit signed
//                  Stage 3 数据位宽：20bit signed
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-18
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-18：新增 Stage 2/3 资源候选等价性测试。
//                2026-07-18：增加 BRAM 历史缓存候选选择宏。
//                2026-07-18：增加交叉系数 BRAM 打包候选选择宏。
//=============================================================
//=============================================================
// 1）模块名称：tb_stage23_lutram_dsp_equiv
// 功能说明：仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 工程版本：Vivado 2025.2。
//=============================================================

module tb_stage23_lutram_dsp_equiv;

    localparam integer STAGE2_W = 22;
    localparam integer STAGE3_W = 20;
`ifdef PHASE7_ENABLE_BRAM_HISTORY
    localparam integer CANDIDATE_USE_BRAM_HISTORY = 1;
`else
    localparam integer CANDIDATE_USE_BRAM_HISTORY = 0;
`endif
`ifdef NATIONAL_FINALS_UNIFIED_STAGE23_HISTORY
    localparam integer CANDIDATE_USE_UNIFIED_BRAM_HISTORY = 1;
`else
    localparam integer CANDIDATE_USE_UNIFIED_BRAM_HISTORY = 0;
`endif
`ifdef PHASE7_ENABLE_BRAM_COEFF
    localparam integer CANDIDATE_USE_BRAM_COEFF = 1;
`else
    localparam integer CANDIDATE_USE_BRAM_COEFF = 0;
`endif
`ifdef PHASE8_ENABLE_PACKED_BRAM
    localparam integer CANDIDATE_USE_PACKED_BRAM = 1;
`else
    localparam integer CANDIDATE_USE_PACKED_BRAM = 0;
`endif
    localparam integer QUEUE_DEPTH = 8192;

    reg clk;
    reg rst_n;
    reg stage2_ce_out;
    reg stage3_ce_out;
    reg signed [STAGE2_W-1:0] stage2_x_in;
    reg signed [STAGE3_W-1:0] stage3_x_in;
    reg stage2_x_in_valid;
    reg stage3_x_in_valid;

    wire signed [STAGE2_W-1:0] ref_stage2_y;
    wire signed [STAGE3_W-1:0] ref_stage3_y;
    wire ref_stage2_valid;
    wire ref_stage3_valid;
    wire signed [STAGE2_W-1:0] dut_stage2_y;
    wire signed [STAGE3_W-1:0] dut_stage3_y;
    wire dut_stage2_valid;
    wire dut_stage3_valid;

    reg signed [STAGE2_W-1:0] stage2_expected [0:QUEUE_DEPTH-1];
    reg signed [STAGE3_W-1:0] stage3_expected [0:QUEUE_DEPTH-1];
    integer stage2_write_count;
    integer stage2_read_count;
    integer stage3_write_count;
    integer stage3_read_count;
    integer mismatch_count;
    integer drive_cycle;
    integer segment_cycle;
    reg stage2_drive_phase;
    reg stage3_drive_phase;
    reg [31:0] lfsr;
    reg drive_enable;
    reg random_enable;
    reg impulse_pending_stage2;
    reg impulse_pending_stage3;

    // 例化说明：调用 interp2_stage23_folded_cic_dsp_ce 插值子模块，完成对应级的数据展开、滤波或模式选择。
    interp2_stage23_folded_cic_dsp_ce #(
        .DATA_W(24),
        .STAGE2_DATA_W(STAGE2_W),
        .STAGE3_DATA_W(STAGE3_W),
        .COEFF_W(16),
        .ACC_W(38),
        .CIC_ORDER(3)
    ) u_reference (
        .clk(clk),
        .rst_n(rst_n),
        .stage2_ce_out(stage2_ce_out),
        .stage2_x_in(stage2_x_in),
        .stage2_x_in_valid(stage2_x_in_valid),
        .stage2_y_out(ref_stage2_y),
        .stage2_y_out_valid(ref_stage2_valid),
        .stage3_ce_out(stage3_ce_out),
        .stage3_x_in(stage3_x_in),
        .stage3_x_in_valid(stage3_x_in_valid),
        .stage3_y_out(ref_stage3_y),
        .stage3_y_out_valid(ref_stage3_valid),
        .stage2_phase_dbg(),
        .stage3_phase_dbg(),
        .scheduler_busy_dbg(),
        .scheduler_stage_dbg(),
        .scheduler_mac_index_dbg()
    );

    // 例化说明：调用 interp2_stage23_lutram_cic_dsp_ce 插值子模块，完成对应级的数据展开、滤波或模式选择。
    interp2_stage23_lutram_cic_dsp_ce #(
        .DATA_W(24),
        .STAGE2_DATA_W(STAGE2_W),
        .STAGE3_DATA_W(STAGE3_W),
        .COEFF_W(18),
        .ACC_W(38),
        .CIC_ORDER(3),
        .USE_BRAM_HISTORY(CANDIDATE_USE_BRAM_HISTORY),
        .USE_UNIFIED_BRAM_HISTORY(
            CANDIDATE_USE_UNIFIED_BRAM_HISTORY),
        .USE_BRAM_COEFF(CANDIDATE_USE_BRAM_COEFF),
        .USE_PACKED_BRAM(CANDIDATE_USE_PACKED_BRAM)
    ) u_candidate (
        .clk(clk),
        .rst_n(rst_n),
        .stage2_ce_out(stage2_ce_out),
        .stage2_x_in(stage2_x_in),
        .stage2_x_in_valid(stage2_x_in_valid),
        .stage2_y_out(dut_stage2_y),
        .stage2_y_out_valid(dut_stage2_valid),
        .stage3_ce_out(stage3_ce_out),
        .stage3_x_in(stage3_x_in),
        .stage3_x_in_valid(stage3_x_in_valid),
        .stage3_y_out(dut_stage3_y),
        .stage3_y_out_valid(dut_stage3_valid),
        .stage2_phase_dbg(),
        .stage3_phase_dbg(),
        .scheduler_busy_dbg(),
        .scheduler_stage_dbg(),
        .scheduler_mac_index_dbg()
    );

    initial begin
        clk = 1'b0;
        forever #10.416 clk = ~clk;
    end

    always @(negedge clk) begin
        if (!rst_n) begin
            stage2_ce_out = 1'b0;
            stage3_ce_out = 1'b0;
            stage2_x_in_valid = 1'b0;
            stage3_x_in_valid = 1'b0;
            stage2_x_in = {STAGE2_W{1'b0}};
            stage3_x_in = {STAGE3_W{1'b0}};
            stage2_drive_phase = 1'b1;
            stage3_drive_phase = 1'b1;
            drive_cycle = 0;
            segment_cycle = 0;
            lfsr = 32'h1ace_b00c;
        end
        else begin
            stage2_ce_out = drive_enable && ((drive_cycle % 48) == 0);
            stage3_ce_out = drive_enable && ((drive_cycle % 24) == 0);
            stage2_x_in_valid = 1'b0;
            stage3_x_in_valid = 1'b0;

            if (stage2_ce_out) begin
                stage2_x_in_valid = !stage2_drive_phase;
                if (!stage2_drive_phase) begin
                    if (impulse_pending_stage2) begin
                        stage2_x_in = 22'sd1048575;
                        impulse_pending_stage2 = 1'b0;
                    end
                    else if (random_enable) begin
                        stage2_x_in = lfsr[STAGE2_W-1:0];
                    end
                    else begin
                        stage2_x_in = {STAGE2_W{1'b0}};
                    end
                end
                stage2_drive_phase = ~stage2_drive_phase;
            end

            if (stage3_ce_out) begin
                stage3_x_in_valid = !stage3_drive_phase;
                if (!stage3_drive_phase) begin
                    if (impulse_pending_stage3) begin
                        stage3_x_in = 20'sd262143;
                        impulse_pending_stage3 = 1'b0;
                    end
                    else if (random_enable) begin
                        stage3_x_in = lfsr[STAGE3_W-1:0];
                    end
                    else begin
                        stage3_x_in = {STAGE3_W{1'b0}};
                    end
                end
                stage3_drive_phase = ~stage3_drive_phase;
            end

            if (stage2_ce_out || stage3_ce_out)
                lfsr = {lfsr[30:0],
                        lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};

            drive_cycle = drive_cycle + 1;
            segment_cycle = segment_cycle + 1;
        end
    end

    always @(posedge clk) begin
        #1;
        if (!rst_n) begin
            stage2_write_count = 0;
            stage2_read_count = 0;
            stage3_write_count = 0;
            stage3_read_count = 0;
        end
        else begin
            if (ref_stage2_valid) begin
                if (stage2_write_count >= QUEUE_DEPTH)
                    $fatal(1, "Stage 2 expected queue overflow");
                stage2_expected[stage2_write_count] = ref_stage2_y;
                stage2_write_count = stage2_write_count + 1;
            end
            if (dut_stage2_valid) begin
                if (stage2_read_count >= stage2_write_count)
                    $fatal(1, "Stage 2 candidate output has no reference");
                if (dut_stage2_y !== stage2_expected[stage2_read_count]) begin
                    mismatch_count = mismatch_count + 1;
                    $display("Stage 2 mismatch sample=%0d ref=%0d dut=%0d",
                        stage2_read_count,
                        stage2_expected[stage2_read_count], dut_stage2_y);
                end
                stage2_read_count = stage2_read_count + 1;
            end

            if (ref_stage3_valid) begin
                if (stage3_write_count >= QUEUE_DEPTH)
                    $fatal(1, "Stage 3 expected queue overflow");
                stage3_expected[stage3_write_count] = ref_stage3_y;
                stage3_write_count = stage3_write_count + 1;
            end
            if (dut_stage3_valid) begin
                if (stage3_read_count >= stage3_write_count)
                    $fatal(1, "Stage 3 candidate output has no reference");
                if (dut_stage3_y !== stage3_expected[stage3_read_count]) begin
                    mismatch_count = mismatch_count + 1;
                    $display("Stage 3 mismatch sample=%0d ref=%0d dut=%0d",
                        stage3_read_count,
                        stage3_expected[stage3_read_count], dut_stage3_y);
                end
                stage3_read_count = stage3_read_count + 1;
            end
        end
    end

    task run_segment;
        input integer active_cycles;
        input integer use_random;
        begin
            random_enable = use_random != 0;
            drive_enable = 1'b1;
            repeat (active_cycles) @(posedge clk);
            @(negedge clk);
            drive_enable = 1'b0;
            stage2_ce_out = 1'b0;
            stage3_ce_out = 1'b0;
            stage2_x_in_valid = 1'b0;
            stage3_x_in_valid = 1'b0;
            repeat (128) @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        drive_enable = 1'b0;
        random_enable = 1'b0;
        impulse_pending_stage2 = 1'b1;
        impulse_pending_stage3 = 1'b1;
        mismatch_count = 0;
        stage2_write_count = 0;
        stage2_read_count = 0;
        stage3_write_count = 0;
        stage3_read_count = 0;

        repeat (8) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        run_segment(4096, 0);
        run_segment(12000, 1);

        @(negedge clk);
        rst_n = 1'b0;
        drive_enable = 1'b0;
        repeat (7) @(posedge clk);
        @(negedge clk);
        impulse_pending_stage2 = 1'b1;
        impulse_pending_stage3 = 1'b1;
        rst_n = 1'b1;

        run_segment(4096, 0);
        run_segment(12000, 1);

        if (stage2_write_count != stage2_read_count)
            $fatal(1, "Stage 2 queue not drained: ref=%0d dut=%0d",
                stage2_write_count, stage2_read_count);
        if (stage3_write_count != stage3_read_count)
            $fatal(1, "Stage 3 queue not drained: ref=%0d dut=%0d",
                stage3_write_count, stage3_read_count);
        if (stage2_read_count < 100 || stage3_read_count < 200)
            $fatal(1, "Insufficient compared samples: stage2=%0d stage3=%0d",
                stage2_read_count, stage3_read_count);
        if (mismatch_count != 0)
            $fatal(1, "Stage 2/3 equivalence failed: mismatches=%0d",
                mismatch_count);

        $display("PASS: Stage 2/3 LUTRAM candidate is 0 LSB equivalent.");
        $display("Compared Stage 2 samples: %0d", stage2_read_count);
        $display("Compared Stage 3 samples: %0d", stage3_read_count);
        $finish;
    end

endmodule
