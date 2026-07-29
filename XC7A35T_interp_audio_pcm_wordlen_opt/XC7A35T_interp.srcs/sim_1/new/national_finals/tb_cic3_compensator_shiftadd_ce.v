`timescale 1ns / 1ps

module tb_cic3_compensator_shiftadd_ce;

    localparam integer DATA_W = 20;
    localparam integer OUT_MAX = (1 << (DATA_W-1))-1;
    localparam integer OUT_MIN = -(1 << (DATA_W-1));

    reg clk;
    reg rst_n;
    reg signed [DATA_W-1:0] x_in;
    reg x_in_valid;
    wire signed [DATA_W-1:0] y_out;
    wire y_out_valid;

    integer model_z1;
    integer model_z2;
    integer expected;
    integer curvature;
    integer sample_count;
    integer seed;

    cic3_compensator_shiftadd_ce #(
        .DATA_W(DATA_W)
    ) u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .x_in(x_in),
        .x_in_valid(x_in_valid),
        .y_out(y_out),
        .y_out_valid(y_out_valid)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task send_sample;
        input integer value;
        input integer gap_cycles;
        integer one_gap;
        integer signed_value;
        begin
            signed_value = value & ((1 << DATA_W)-1);
            if (signed_value > OUT_MAX)
                signed_value = signed_value-(1 << DATA_W);
            @(negedge clk);
            x_in <= signed_value;
            x_in_valid <= 1'b1;
            curvature = 2*model_z1-signed_value-model_z2;
            expected = model_z1+(curvature >>> 3);
            if (expected > OUT_MAX)
                expected = OUT_MAX;
            else if (expected < OUT_MIN)
                expected = OUT_MIN;

            @(posedge clk);
            #1;
            if (!y_out_valid)
                $fatal(1, "Missing valid at sample %0d", sample_count);
            if ($signed(y_out) !== expected)
                $fatal(1, "Mismatch sample=%0d x=%0d actual=%0d expected=%0d",
                    sample_count, signed_value, $signed(y_out), expected);

            model_z2 = model_z1;
            model_z1 = signed_value;
            sample_count = sample_count+1;
            @(negedge clk);
            x_in_valid <= 1'b0;
            for (one_gap = 0; one_gap < gap_cycles; one_gap = one_gap+1) begin
                @(posedge clk);
                #1;
                if (y_out_valid)
                    $fatal(1, "Unexpected valid in input gap");
                @(negedge clk);
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        x_in = {DATA_W{1'b0}};
        x_in_valid = 1'b0;
        model_z1 = 0;
        model_z2 = 0;
        sample_count = 0;
        seed = 32'h5A17C3E1;

        repeat (4) @(negedge clk);
        rst_n = 1'b1;

        send_sample(0, 0);
        send_sample(1, 1);
        send_sample(-1, 0);
        send_sample(OUT_MAX, 2);
        send_sample(OUT_MIN, 0);
        send_sample(OUT_MAX, 0);
        send_sample(OUT_MIN, 3);

        repeat (2000) begin
            send_sample($random(seed) & ((1 << DATA_W)-1),
                        sample_count % 3);
        end

        // 中途复位后必须与冷启动历史一致。
        rst_n = 1'b0;
        x_in_valid = 1'b0;
        repeat (3) @(negedge clk);
        model_z1 = 0;
        model_z2 = 0;
        rst_n = 1'b1;
        send_sample(12345, 0);
        send_sample(-23456, 0);

        $display("NF CIC3 SHIFTADD COMPENSATOR PASS samples=%0d",
            sample_count);
        $finish;
    end

endmodule
