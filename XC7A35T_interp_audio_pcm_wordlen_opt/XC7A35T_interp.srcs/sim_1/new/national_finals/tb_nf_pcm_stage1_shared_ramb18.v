`timescale 1ns / 1ps

module tb_nf_pcm_stage1_shared_ramb18;

    reg clk;
    reg rst_n;
    reg family_48k;
    reg history_read_enable;
    reg [5:0] history_read_addr;
    reg history_write_enable;
    reg [5:0] history_write_addr;
    reg signed [23:0] history_write_data;
    reg pcm_sample_ce;

    wire signed [23:0] beh_history_data;
    wire signed [23:0] prim_history_data;
    wire signed [23:0] beh_pcm_data;
    wire signed [23:0] prim_pcm_data;
    wire beh_pcm_update;
    wire prim_pcm_update;
    wire [7:0] beh_pcm_addr;
    wire [7:0] prim_pcm_addr;
    wire beh_deadline_miss;
    wire prim_deadline_miss;

    reg signed [23:0] pcm_golden [0:255];
    reg signed [23:0] history_golden [0:63];
    integer index;
    integer sample_count;
    integer expected_pcm_addr;

    always #5 clk = ~clk;

    nf_pcm_stage1_shared_ramb18_sdp #(
        .SIM_USE_PRIMITIVE(0)
    ) u_behavioral (
        .clk(clk), .rst_n(rst_n),
        .history_read_enable(history_read_enable),
        .history_read_addr(history_read_addr),
        .history_read_data(beh_history_data),
        .history_write_enable(history_write_enable),
        .history_write_addr(history_write_addr),
        .history_write_data(history_write_data),
        .pcm_sample_ce(pcm_sample_ce),
        .family_48k(family_48k),
        .pcm_sample_out(beh_pcm_data),
        .pcm_sample_update(beh_pcm_update),
        .pcm_sample_addr_dbg(beh_pcm_addr),
        .pcm_deadline_miss_dbg(beh_deadline_miss),
        .pcm_request_pending_dbg()
    );

    nf_pcm_stage1_shared_ramb18_sdp #(
        .SIM_USE_PRIMITIVE(1)
    ) u_primitive (
        .clk(clk), .rst_n(rst_n),
        .history_read_enable(history_read_enable),
        .history_read_addr(history_read_addr),
        .history_read_data(prim_history_data),
        .history_write_enable(history_write_enable),
        .history_write_addr(history_write_addr),
        .history_write_data(history_write_data),
        .pcm_sample_ce(pcm_sample_ce),
        .family_48k(family_48k),
        .pcm_sample_out(prim_pcm_data),
        .pcm_sample_update(prim_pcm_update),
        .pcm_sample_addr_dbg(prim_pcm_addr),
        .pcm_deadline_miss_dbg(prim_deadline_miss),
        .pcm_request_pending_dbg()
    );

    task apply_reset;
        input family_value;
        begin
            @(negedge clk);
            family_48k = family_value;
            rst_n = 1'b0;
            history_read_enable = 1'b0;
            history_write_enable = 1'b0;
            pcm_sample_ce = 1'b0;
            repeat (4) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
        end
    endtask

    task verify_pcm_family;
        input family_value;
        input integer number_of_samples;
        integer cycle_in_frame;
        integer local_sample_count;
        begin
            apply_reset(family_value);
            expected_pcm_addr = family_value ? 147 : 0;
            local_sample_count = 0;
            while (local_sample_count < number_of_samples) begin
                for (cycle_in_frame = 0; cycle_in_frame < 128;
                     cycle_in_frame = cycle_in_frame + 1) begin
                    @(negedge clk);
                    // Deliberately occupy the read port for 116 clocks.
                    // The held PCM request has only 12 clocks to complete.
                    history_read_enable = cycle_in_frame < 116;
                    history_read_addr = cycle_in_frame[5:0];
                    pcm_sample_ce = cycle_in_frame == 127;
                    @(posedge clk);
                    #1;
                    if (beh_pcm_update !== prim_pcm_update ||
                        beh_pcm_data !== prim_pcm_data ||
                        beh_pcm_addr !== prim_pcm_addr)
                        $fatal(1, "Behavioral/primitive PCM mismatch");
                    if (pcm_sample_ce) begin
                        if (!beh_pcm_update)
                            $fatal(1, "PCM update missing at frame deadline");
                        if (beh_pcm_addr !== expected_pcm_addr[7:0] ||
                            beh_pcm_data !== pcm_golden[expected_pcm_addr])
                            $fatal(1,
                                "PCM mismatch addr=%0d actual_addr=%0d actual=%0d expected=%0d",
                                expected_pcm_addr, beh_pcm_addr,
                                beh_pcm_data, pcm_golden[expected_pcm_addr]);
                        if (family_value) begin
                            expected_pcm_addr =
                                (expected_pcm_addr == 162) ?
                                147 : expected_pcm_addr + 1;
                        end
                        else begin
                            expected_pcm_addr =
                                (expected_pcm_addr == 146) ?
                                0 : expected_pcm_addr + 1;
                        end
                        local_sample_count = local_sample_count + 1;
                    end
                end
            end
            @(negedge clk);
            history_read_enable = 1'b0;
            pcm_sample_ce = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        family_48k = 1'b0;
        history_read_enable = 1'b0;
        history_read_addr = 6'd0;
        history_write_enable = 1'b0;
        history_write_addr = 6'd0;
        history_write_data = 24'sd0;
        pcm_sample_ce = 1'b0;
        $readmemh("nf_sine_15k_dual_rate_24bit_256.mem", pcm_golden);

        // UNISIM glbl keeps GSR asserted at the start of simulation; do not
        // issue primitive writes until that device-level reset is released.
        #120;
        apply_reset(1'b0);
        for (index = 0; index < 64; index = index + 1) begin
            history_golden[index] =
                $signed((index * 24'h13579) ^ 24'h5A39C7);
            @(negedge clk);
            history_write_enable = 1'b1;
            history_write_addr = index[5:0];
            history_write_data = history_golden[index];
        end
        @(negedge clk);
        history_write_enable = 1'b0;

        for (index = 0; index < 64; index = index + 1) begin
            @(negedge clk);
            history_read_enable = 1'b1;
            history_read_addr = index[5:0];
            @(posedge clk);
            #1;
            if (beh_history_data !== history_golden[history_read_addr] ||
                prim_history_data !== history_golden[history_read_addr])
                $fatal(1,
                    "Shared RAM history mismatch addr=%0d beh=%0d prim=%0d expected=%0d",
                    history_read_addr, beh_history_data, prim_history_data,
                    history_golden[history_read_addr]);
        end
        @(negedge clk);
        history_read_enable = 1'b0;

        verify_pcm_family(1'b0, 150);
        verify_pcm_family(1'b1, 20);

        if (beh_deadline_miss || prim_deadline_miss)
            $fatal(1, "Shared RAM deadline miss flag asserted");

        $display("PCM/STAGE1 SHARED RAMB18 PASS: history=64, 44k1=150, 48k=20, 12-cycle idle window");
        $finish;
    end

endmodule

