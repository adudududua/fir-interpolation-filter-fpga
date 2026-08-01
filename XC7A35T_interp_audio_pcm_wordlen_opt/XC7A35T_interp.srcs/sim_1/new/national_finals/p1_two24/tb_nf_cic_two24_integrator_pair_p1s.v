`timescale 1ns / 1ps

module tb_nf_cic_two24_integrator_pair_p1s;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg event_ce = 1'b0;
    reg signed [25:0] u_in = 26'sd0;

    wire signed [25:0] a_out;
    wire signed [28:0] q_out;
    wire signed [28:0] b_out;
    wire out_valid;
    wire [47:0] p_low_limb_dbg;
    wire [3:0] carryout_dbg;
    wire pending_dbg;

    reg signed [25:0] ref_a = 26'sd0;
    reg signed [28:0] ref_b = 29'sd0;
    reg signed [25:0] expected_a = 26'sd0;
    reg signed [28:0] expected_q = 29'sd0;
    reg signed [28:0] expected_b = 29'sd0;
    reg expected_pending = 1'b0;
    reg [23:0] old_a_low;
    reg [23:0] old_q_low;
    reg [24:0] raw_a_low;
    reg [24:0] raw_q_low;
    reg signed [25:0] next_a;
    reg signed [28:0] next_b;
    reg signed [28:0] next_q;
    integer checks = 0;
    integer events = 0;
    integer resets = 0;
    integer seed;
    integer index;
    integer random_word;

    always #5 clk = ~clk;

    nf_cic_two24_integrator_pair_p1s dut (
        .clk(clk), .rst_n(rst_n), .event_ce(event_ce), .u_in(u_in),
        .a_out(a_out), .q_out(q_out), .b_out(b_out),
        .out_valid(out_valid), .p_low_limb_dbg(p_low_limb_dbg),
        .carryout_dbg(carryout_dbg), .pending_dbg(pending_dbg)
    );

    task tick;
        input do_reset;
        input do_event;
        input signed [25:0] sample;
        begin
            @(negedge clk);
            rst_n = !do_reset;
            event_ce = do_event;
            u_in = sample;

            old_a_low = ref_a[23:0];
            old_q_low = (ref_b-ref_a);
            raw_a_low = {1'b0, old_a_low}+{1'b0, sample[23:0]};
            raw_q_low = {1'b0, old_q_low}+{1'b0, old_a_low};
            next_a = ref_a+sample;
            next_b = ref_b+next_a;
            next_q = next_b-next_a;

            @(posedge clk); #1;
            if (do_reset) begin
                resets = resets+1;
                if (out_valid !== 1'b0 || pending_dbg !== 1'b0 ||
                    p_low_limb_dbg !== 48'd0)
                    $fatal(1, "Reset did not clear TWO24 state");
                ref_a = 26'sd0;
                ref_b = 29'sd0;
                expected_pending = 1'b0;
            end
            else begin
                if (out_valid !== expected_pending)
                    $fatal(1, "valid mismatch event=%0d", events);
                if (expected_pending) begin
                    checks = checks+1;
                    if (a_out !== expected_a || q_out !== expected_q ||
                        b_out !== expected_b)
                        $fatal(1, "state mismatch check=%0d A=%0d/%0d Q=%0d/%0d B=%0d/%0d",
                            checks, a_out, expected_a, q_out, expected_q,
                            b_out, expected_b);
                end
                if (do_event) begin
                    events = events+1;
                    if (p_low_limb_dbg[23:0] !== next_a[23:0] ||
                        p_low_limb_dbg[47:24] !== next_q[23:0])
                        $fatal(1, "low-limb mismatch event=%0d", events);
                    if (carryout_dbg[1] !== raw_a_low[24] ||
                        carryout_dbg[3] !== raw_q_low[24])
                        $fatal(1, "carry lane mismatch event=%0d carry=%b expected=%b%b",
                            events, carryout_dbg, raw_q_low[24], raw_a_low[24]);
                    ref_a = next_a;
                    ref_b = next_b;
                    expected_a = next_a;
                    expected_b = next_b;
                    expected_q = next_q;
                    expected_pending = 1'b1;
                end
                else begin
                    expected_pending = 1'b0;
                end
            end
        end
    endtask

    initial begin
        repeat (3) tick(1'b1, 1'b0, 26'sd0);
        // glbl keeps GSR asserted for the first 100 ns in UNISIM runs.
        #120;
        tick(1'b0, 1'b1, 26'sh0FFFFFE);
        tick(1'b0, 1'b1, 26'sh0FFFFFF);
        tick(1'b0, 1'b1, 26'sh1000000);
        tick(1'b0, 1'b1, 26'sh1000001);
        tick(1'b0, 1'b1, -26'sd1);
        tick(1'b0, 1'b1, 26'sh3FFFFFF);
        tick(1'b0, 1'b1, -26'sd33554432);
        tick(1'b0, 1'b0, 26'sd0);

        for (seed = 1; seed <= 20; seed = seed+1) begin
            random_word = 32'h13579BDF ^ (seed*32'h10203);
            for (index = 0; index < 600; index = index+1) begin
                random_word = random_word*1664525+1013904223;
                if ((index % 137) == 73) begin
                    tick(1'b1, 1'b0, 26'sd0);
                end
                else if ((random_word & 32'h7) < 5) begin
                    tick(1'b0, 1'b1, random_word[25:0]);
                end
                else begin
                    tick(1'b0, 1'b0, 26'sd0);
                end
            end
            tick(1'b0, 1'b0, 26'sd0);
        end

        tick(1'b0, 1'b1, 26'sh3FFFFFE);
        tick(1'b1, 1'b0, 26'sd0);
        tick(1'b0, 1'b1, 26'sd12345);
        tick(1'b0, 1'b0, 26'sd0);

        if (checks < 7000 || events < 7000 || resets < 20)
            $fatal(1, "Insufficient coverage checks=%0d events=%0d resets=%0d",
                checks, events, resets);
        $display("P1B TWO24 UNISIM PASS: events=%0d commits=%0d resets=%0d, carry lanes [1]/[3], II=1/stall/reset exact",
            events, checks, resets);
        $finish;
    end
endmodule
