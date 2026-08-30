`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_cic_interp16_serial_comb_equiv.v
// 模块名       : tb_cic_interp16_serial_comb_equiv
// 功能简述     : 并行 comb CIC 与低 DSP 串行 comb CIC 的逐样本
//                等价测试。两种实现启动延迟不同，因此参考输出先
//                写入队列，候选输出按有效样本顺序读取比较，而不是
//                强制要求两个模块在同一个时钟周期拉高 valid。
//
//                测试覆盖随机 PCM、不同 ce 相位、复位后重新启动及
//                长序列运行，要求输出数量一致且所有样本 0 LSB。
//
// 当前默认配置：DATA_W=20，比较队列深度 8192
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-29
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-29：新增串行 comb 样本顺序等价回归。
//                2026-08-16：补充中文激励与队列判定说明。
//=============================================================

module tb_cic_interp16_serial_comb_equiv;

    localparam integer DATA_W = 20;
    localparam integer QUEUE_DEPTH = 8192;

    reg clk;
    reg rst_n;
    reg ce_out;
    reg signed [DATA_W-1:0] x_in;
    reg x_in_valid;

    wire signed [DATA_W-1:0] y_reference;
    wire reference_valid;
    wire signed [DATA_W-1:0] y_serial;
    wire serial_valid;

    reg signed [DATA_W-1:0] reference_queue [0:QUEUE_DEPTH-1];
    integer queue_write;
    integer queue_read;
    integer reference_count;
    integer serial_count;
    integer mismatch_count;
    integer random_seed;
    integer input_index;
    integer enabled_phase;
    integer current_input_count;

    cic_interp16_core_dsp_ce #(
        .DATA_W(20),
        .CIC_ORDER(3),
        .FINAL_PRUNE_LSB(0),
        .BURST_COUNTER_USE_DSP(0)
    ) u_reference (
        .clk(clk),
        .rst_n(rst_n),
        .ce_out(ce_out),
        .x_in(x_in),
        .x_in_valid(x_in_valid),
        .y_out(y_reference),
        .y_out_valid(reference_valid),
        .burst_remaining_dbg(),
        .pending_dbg()
    );

    cic_interp16_serial_comb_dsp_ce #(
        .DATA_W(20),
        .FINAL_PRUNE_LSB(0),
        .BURST_COUNTER_USE_DSP(0)
    ) u_serial (
        .clk(clk),
        .rst_n(rst_n),
        .ce_out(ce_out),
        .x_in(x_in),
        .x_in_valid(x_in_valid),
        .y_out(y_serial),
        .y_out_valid(serial_valid),
        .burst_remaining_dbg(),
        .pending_dbg(),
        .comb_busy_dbg()
    );

    always #5 clk = ~clk;

    // 参考结构比串行候选结构提前3拍，比较队列在此补偿固定结构延迟。
    // 缓存参考样本；候选结构每次输出有效时，从队列取出对应参考值比较。
    always @(negedge clk) begin
        if (!rst_n) begin
            queue_write = 0;
            queue_read = 0;
            reference_count = 0;
            serial_count = 0;
            mismatch_count = 0;
        end
        else begin
            if (reference_valid) begin
                if (queue_write >= QUEUE_DEPTH)
                    $fatal(1, "Reference queue overflow");
                reference_queue[queue_write] = y_reference;
                queue_write = queue_write + 1;
                reference_count = reference_count + 1;
            end

            if (serial_valid) begin
                if (queue_read >= queue_write)
                    $fatal(1, "Serial CIC produced a sample before reference");
                if (y_serial !== reference_queue[queue_read]) begin
                    mismatch_count = mismatch_count + 1;
                    $display("CIC mismatch sample=%0d reference=%0d serial=%0d",
                             serial_count, reference_queue[queue_read],
                             y_serial);
                    if (mismatch_count >= 8)
                        $fatal(1, "Too many CIC equivalence mismatches");
                end
                queue_read = queue_read + 1;
                serial_count = serial_count + 1;
            end
        end
    end

    task drive_next_sample;
        input integer sample_number;
        begin
            case (sample_number & 7)
                0: x_in = 20'sh7ffff;
                1: x_in = -20'sd524288;
                2: x_in = 20'sd0;
                3: x_in = 20'sd1;
                4: x_in = -20'sd1;
                default: x_in = $random(random_seed);
            endcase
        end
    endtask

    task stream_inputs;
        input integer number_of_inputs;
        input integer insert_ce_stalls;
        begin
            current_input_count = 0;
            enabled_phase = 15;
            while (current_input_count < number_of_inputs) begin
                @(negedge clk);
                x_in_valid = 1'b0;
                if (insert_ce_stalls != 0)
                    ce_out = (($random(random_seed) & 32'h7) != 0);
                else
                    ce_out = 1'b1;

                if (ce_out) begin
                    if (enabled_phase == 15) begin
                        drive_next_sample(current_input_count);
                        x_in_valid = 1'b1;
                        current_input_count = current_input_count + 1;
                        enabled_phase = 0;
                    end
                    else begin
                        enabled_phase = enabled_phase + 1;
                    end
                end
            end
        end
    endtask

    task drain_and_check;
        input integer expected_inputs;
        integer drain_index;
        begin
            for (drain_index = 0; drain_index < 48;
                 drain_index = drain_index + 1) begin
                @(negedge clk);
                x_in_valid = 1'b0;
                ce_out = 1'b1;
            end
            @(negedge clk);

            if (mismatch_count != 0)
                $fatal(1, "CIC equivalence mismatch count=%0d",
                       mismatch_count);
            if (reference_count != expected_inputs*16)
                $fatal(1, "Reference count=%0d expected=%0d",
                       reference_count, expected_inputs*16);
            if (serial_count != expected_inputs*16)
                $fatal(1, "Serial count=%0d expected=%0d",
                       serial_count, expected_inputs*16);
            if (queue_read != queue_write)
                $fatal(1, "Undrained reference samples=%0d",
                       queue_write-queue_read);
        end
    endtask

    task pulse_reset;
        begin
            @(negedge clk);
            #1 rst_n = 1'b0;
            x_in_valid = 1'b0;
            ce_out = 1'b0;
            repeat (3) @(negedge clk);
            #1 rst_n = 1'b1;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        ce_out = 1'b0;
        x_in = {DATA_W{1'b0}};
        x_in_valid = 1'b0;
        random_seed = 32'h18c3_6d5a;

        repeat (4) @(negedge clk);
        #1 rst_n = 1'b1;

        // 在两种实现均处于突发输出时主动插入复位，验证串行梳状器的延迟
        // 状态不会泄漏到下一运行epoch。
        stream_inputs(25, 0);
        @(negedge clk);
        x_in_valid = 1'b0;
        ce_out = 1'b1;
        repeat (7) @(negedge clk);
        if (!reference_valid || !serial_valid)
            $fatal(1, "Directed reset did not land inside an active burst");
        #1 rst_n = 1'b0;
        repeat (3) @(negedge clk);
        #1 rst_n = 1'b1;

        // ce_out连续有效：先覆盖边界值，再输入可复现的确定性随机数据。
        stream_inputs(160, 0);
        drain_and_check(160);

        pulse_reset();

        // 随机暂停ce_out，覆盖使能域状态机在停顿和恢复时的边界转换。
        stream_inputs(240, 1);
        drain_and_check(240);

        $display("CIC SERIAL COMB EQUIVALENCE PASS: continuous=160 stalled=240 reset-mid-burst=PASS samples=%0d",
                 serial_count);
        $finish;
    end

endmodule
