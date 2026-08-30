`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_phase7_cic_modulo_boundary.v
// 模块名       : tb_phase7_cic_modulo_boundary
// 功能简述     : Phase 7 N=3 CIC 积分器补码模运算边界测试。
//                本测试通过层次化设置仿真内部状态，分别构造三级
//                积分累加器的正向和负向 32bit 越界，检查 RTL
//                是否严格执行二进制补码模 2^32 回绕。
//
//                该测试仅用于覆盖合法 20bit 输入通常不会触发的
//                算术边界，不改变综合版本，也不代表正常运行溢出。
//
// 当前默认配置：
//                  输入位宽：20bit signed
//                  CIC 参数：R=16，M=1，N=3
//                  内部位宽：32bit signed
//                  末级裁剪：0 LSB
//                  边界场景：6 组
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-14
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-14：新增三级积分器正负回绕边界测试。
//=============================================================

module tb_phase7_cic_modulo_boundary;

    reg clk;
    reg rst_n;
    reg signed [19:0] x_in;
    reg x_in_valid;

    wire signed [19:0] y_out;
    wire y_out_valid;
    wire [4:0] burst_remaining;
    wire burst_pending;

    integer mismatch_count;
    integer case_index;

    cic_interp16_core_ce #(
        .DATA_W          (20),
        .CIC_ORDER       (3),
        .FINAL_PRUNE_LSB (0)
    ) u_dut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .ce_out              (1'b1),
        .x_in                (x_in),
        .x_in_valid          (x_in_valid),
        .y_out               (y_out),
        .y_out_valid         (y_out_valid),
        .burst_remaining_dbg (burst_remaining),
        .pending_dbg         (burst_pending)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task reset_dut;
        begin
            rst_n = 1'b0;
            x_in = 20'sd0;
            x_in_valid = 1'b0;
            repeat (3) @(negedge clk);
            rst_n = 1'b1;
            @(negedge clk);
        end
    endtask

    task run_boundary_case;
        input signed [31:0] state0;
        input signed [31:0] state1;
        input signed [31:0] final_state;
        input signed [31:0] burst_value;
        input signed [31:0] expected0;
        input signed [31:0] expected1;
        input signed [31:0] expected_final;
        begin
            reset_dut();

            u_dut.integrator_state[0] = state0;
            u_dut.integrator_state[1] = state1;
            u_dut.final_integrator_state = final_state;
            u_dut.burst_sample = burst_value;
            u_dut.burst_pending = 1'b1;
            u_dut.burst_remaining = 5'd0;

            @(posedge clk);
            #1;

            if (u_dut.integrator_state[0] !== expected0 ||
                    u_dut.integrator_state[1] !== expected1 ||
                    u_dut.final_integrator_state !== expected_final ||
                    y_out_valid !== 1'b1) begin
                mismatch_count = mismatch_count + 1;
                $display("CIC modulo mismatch case=%0d s0=%0d/%0d s1=%0d/%0d sf=%0d/%0d valid=%0b",
                    case_index,
                    $signed(u_dut.integrator_state[0]), $signed(expected0),
                    $signed(u_dut.integrator_state[1]), $signed(expected1),
                    $signed(u_dut.final_integrator_state),
                    $signed(expected_final), y_out_valid);
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        x_in = 20'sd0;
        x_in_valid = 1'b0;
        mismatch_count = 0;
        case_index = 0;

        case_index = 1;
        run_boundary_case(32'sh7fffffff, 32'sd0, 32'sd0, 32'sd1,
            32'sh80000000, 32'sh80000000, 32'sh80000000);

        case_index = 2;
        run_boundary_case(32'sh80000000, 32'sd0, 32'sd0, -32'sd1,
            32'sh7fffffff, 32'sh7fffffff, 32'sh7fffffff);

        case_index = 3;
        run_boundary_case(32'sd0, 32'sh7fffffff, 32'sd0, 32'sd1,
            32'sd1, 32'sh80000000, 32'sh80000000);

        case_index = 4;
        run_boundary_case(32'sd0, 32'sd0, 32'sh7fffffff, 32'sd1,
            32'sd1, 32'sd1, 32'sh80000000);

        case_index = 5;
        run_boundary_case(32'sd0, 32'sh80000000, 32'sd0, -32'sd1,
            -32'sd1, 32'sh7fffffff, 32'sh7fffffff);

        case_index = 6;
        run_boundary_case(32'sd0, 32'sd0, 32'sh80000000, -32'sd1,
            -32'sd1, -32'sd1, 32'sh7fffffff);

        if (mismatch_count != 0)
            $fatal(1, "PHASE7 CIC MODULO BOUNDARY FAIL mismatch=%0d",
                mismatch_count);

        $display("PHASE7 CIC MODULO BOUNDARY PASS: 6 positive/negative wrap cases exact.");
        $finish;
    end

endmodule
