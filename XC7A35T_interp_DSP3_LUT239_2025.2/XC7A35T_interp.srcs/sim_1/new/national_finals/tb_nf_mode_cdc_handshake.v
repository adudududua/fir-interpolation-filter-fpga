`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_nf_mode_cdc_handshake.v
// 模块名       : tb_nf_mode_cdc_handshake
// 功能简述     : 模式控制域到音频域跨时钟握手测试平台。
//                使用相互异步的控制时钟和音频时钟，随机改变目标模式并
//                检查请求/应答翻转、稳定等待、静音窗口和原子模式提交；
//                同时监测未知态、重复提交、静音外提交及应答计数错误。
// 当前默认配置 : SETTLE_CYCLES=7；控制时钟周期14 ns，音频时钟周期10 ns，
//                两时钟采用非同相启动以覆盖真实异步相位关系。
// 设计作者     : kafeizizi
// 创建日期     : 2026-08-16
// 版本         : V2025.2
// 开发工具     : Vivado Simulator 2025.2
// 修订记录     : V2025.2 统一文件头并补充中文测试结构说明。
//=============================================================
module tb_nf_mode_cdc_handshake;

    reg ctrl_clk = 1'b0;
    reg audio_clk = 1'b0;
    reg ctrl_rst_n = 1'b0;
    reg audio_rst_n = 1'b0;
    reg [1:0] ctrl_mode = 2'b11;

    wire ctrl_busy;
    wire [1:0] audio_mode;
    wire audio_mute;

    integer errors = 0;
    integer checked_transitions = 0;
    integer total_commits = 0;
    integer total_acks = 0;
    integer seed = 32'h56A1C0DE;
    integer old_mode;
    integer new_mode;
    integer repetition;
    integer delay_cycles;
    integer timeout;
    integer commits_before;
    integer acks_before;

    reg [1:0] last_audio_mode = 2'b11;
    reg       last_ack = 1'b0;
    reg       shadow_tracking = 1'b0;
    reg [1:0] shadow_held = 2'b11;
    reg [1:0] transfer_old_mode = 2'b11;

    nf_mode_cdc_handshake #(
        .SETTLE_CYCLES(7)
    ) u_dut (
        .ctrl_clk(ctrl_clk),
        .ctrl_rst_n(ctrl_rst_n),
        .ctrl_mode(ctrl_mode),
        .ctrl_busy(ctrl_busy),
        .audio_clk(audio_clk),
        .audio_rst_n(audio_rst_n),
        .audio_mode(audio_mode),
        .audio_mute(audio_mute)
    );

    always #7 ctrl_clk = ~ctrl_clk;
    initial begin
        #3;
        forever #5 audio_clk = ~audio_clk;
    end

    always @(negedge audio_clk) begin
        if (!audio_rst_n) begin
            last_audio_mode = 2'b11;
            last_ack = 1'b0;
        end
        else begin
            if (^audio_mode === 1'bx || ^audio_mute === 1'bx) begin
                errors = errors + 1;
                $display("ERROR: X in audio outputs at %0t", $time);
            end
            if (audio_mode !== last_audio_mode) begin
                total_commits = total_commits + 1;
                if (audio_mute !== 1'b1) begin
                    errors = errors + 1;
                    $display("ERROR: audio mode committed outside mute at %0t", $time);
                end
            end
            if (u_dut.ack_toggle !== last_ack)
                total_acks = total_acks + 1;
            last_audio_mode = audio_mode;
            last_ack = u_dut.ack_toggle;
        end
    end

    always @(negedge ctrl_clk) begin
        if (!ctrl_rst_n || !ctrl_busy) begin
            shadow_tracking = 1'b0;
        end
        else if (!shadow_tracking) begin
            shadow_tracking = 1'b1;
            shadow_held = u_dut.mode_shadow;
        end
        else if (u_dut.mode_shadow !== shadow_held) begin
            errors = errors + 1;
            $display("ERROR: bundled data changed while busy at %0t", $time);
        end
    end

    task transfer_mode;
        input [1:0] target_mode;
        input integer count_as_directed;
        begin
            if (audio_mode !== target_mode) begin
                transfer_old_mode = audio_mode;
                commits_before = total_commits;
                acks_before = total_acks;

                @(negedge ctrl_clk);
                ctrl_mode = target_mode;

                timeout = 0;
                while (ctrl_busy !== 1'b1 && timeout < 16) begin
                    @(negedge ctrl_clk);
                    timeout = timeout + 1;
                end
                if (ctrl_busy !== 1'b1) begin
                    errors = errors + 1;
                    $display("ERROR: request did not become busy target=%0d", target_mode);
                end

                timeout = 0;
                while (ctrl_busy !== 1'b0 && timeout < 256) begin
                    @(negedge ctrl_clk);
                    timeout = timeout + 1;
                    if ((audio_mode !== transfer_old_mode) &&
                        (audio_mode !== target_mode)) begin
                        errors = errors + 1;
                        $display("ERROR: mixed mode observed target=%0d actual=%0d",
                            target_mode, audio_mode);
                    end
                end

                if (ctrl_busy !== 1'b0 || audio_mode !== target_mode) begin
                    errors = errors + 1;
                    $display("ERROR: transfer timeout/wrong value target=%0d actual=%0d busy=%b",
                        target_mode, audio_mode, ctrl_busy);
                end
                if (total_commits != commits_before + 1) begin
                    errors = errors + 1;
                    $display("ERROR: expected one atomic commit target=%0d delta=%0d",
                        target_mode, total_commits - commits_before);
                end
                if (total_acks != acks_before + 1) begin
                    errors = errors + 1;
                    $display("ERROR: expected one acknowledgement target=%0d delta=%0d",
                        target_mode, total_acks - acks_before);
                end
            end
            if (count_as_directed != 0)
                checked_transitions = checked_transitions + 1;
        end
    endtask

    initial begin
        repeat (8) @(posedge ctrl_clk);
        ctrl_rst_n = 1'b1;
        repeat (5) @(posedge audio_clk);
        if (u_dut.transfer_pipe[7:0] !== 8'b00000001) begin
            errors = errors + 1;
            $display("ERROR: SETTLE_CYCLES=7 token width/state is %b",
                     u_dut.transfer_pipe);
        end
        audio_rst_n = 1'b1;

        timeout = 0;
        while ((ctrl_busy !== 1'b0 || audio_mute !== 1'b0) && timeout < 256) begin
            @(negedge ctrl_clk);
            timeout = timeout + 1;
        end
        if (timeout == 256) begin
            errors = errors + 1;
            $display("ERROR: boot handshake did not complete");
        end

        // 每一种定向旧模式→新模式转换重复100次；随机空闲间隔覆盖两个
        // 无关时钟之间的大量相对相位组合。
        for (old_mode = 0; old_mode < 4; old_mode = old_mode + 1) begin
            for (new_mode = 0; new_mode < 4; new_mode = new_mode + 1) begin
                if (new_mode != old_mode) begin
                    for (repetition = 0; repetition < 100;
                            repetition = repetition + 1) begin
                        transfer_mode(old_mode[1:0], 0);
                        delay_cycles = $random(seed) & 7;
                        repeat (delay_cycles) @(posedge ctrl_clk);
                        transfer_mode(new_mode[1:0], 1);
                    end
                end
            end
        end

        if (checked_transitions != 1200) begin
            errors = errors + 1;
            $display("ERROR: directed transition count=%0d", checked_transitions);
        end

        if (errors != 0)
            $fatal(1, "NF MODE CDC HANDSHAKE FAIL errors=%0d", errors);
        $display("NF MODE CDC HANDSHAKE PASS: 1200 directed transitions, atomic commit, stable bundled data, one ACK each.");
        $finish;
    end

endmodule
