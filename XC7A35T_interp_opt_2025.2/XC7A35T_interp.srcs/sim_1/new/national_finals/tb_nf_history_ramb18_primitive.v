`timescale 1ns / 1ps

// Directly compares the two explicit RAMB18E1 history wrappers against their
// behavioral models.  The test does not define SYNTHESIS globally: only the
// candidate instances select the primitive branch.
module tb_nf_history_ramb18_primitive;
    reg clk = 1'b0;

    reg [5:0] s1_read_addr = 6'd0;
    reg s1_write_enable = 1'b0;
    reg [5:0] s1_write_addr = 6'd0;
    reg signed [23:0] s1_write_data = 24'sd0;
    wire signed [23:0] s1_read_behavioral;
    wire signed [23:0] s1_read_primitive;

    reg [4:0] s23_read_addr = 5'd0;
    reg s23_write_enable = 1'b0;
    reg [4:0] s23_write_addr = 5'd0;
    reg signed [21:0] s23_write_data = 22'sd0;
    wire signed [21:0] s23_read_behavioral;
    wire signed [21:0] s23_read_primitive;

    reg signed [23:0] s1_golden [0:63];
    reg signed [21:0] s23_golden [0:31];
    reg signed [23:0] s1_expected;
    reg signed [21:0] s23_expected;
    integer i;
    integer cycle;
    integer seed_data = 32'h13579bdf;
    integer seed_ctrl = 32'h2468ace1;

    always #5 clk = ~clk;

    nf_stage1_history_ramb18_sdp #(
        .SIM_USE_PRIMITIVE(0)
    ) u_s1_behavioral (
        .clk(clk),
        .read_addr(s1_read_addr),
        .read_data(s1_read_behavioral),
        .write_enable(s1_write_enable),
        .write_addr(s1_write_addr),
        .write_data(s1_write_data)
    );

    nf_stage1_history_ramb18_sdp #(
        .SIM_USE_PRIMITIVE(1)
    ) u_s1_primitive (
        .clk(clk),
        .read_addr(s1_read_addr),
        .read_data(s1_read_primitive),
        .write_enable(s1_write_enable),
        .write_addr(s1_write_addr),
        .write_data(s1_write_data)
    );

    nf_stage23_history_ramb18_sdp #(
        .SIM_USE_PRIMITIVE(0)
    ) u_s23_behavioral (
        .clk(clk),
        .read_addr(s23_read_addr),
        .read_data(s23_read_behavioral),
        .write_enable(s23_write_enable),
        .write_addr(s23_write_addr),
        .write_data(s23_write_data)
    );

    nf_stage23_history_ramb18_sdp #(
        .SIM_USE_PRIMITIVE(1)
    ) u_s23_primitive (
        .clk(clk),
        .read_addr(s23_read_addr),
        .read_data(s23_read_primitive),
        .write_enable(s23_write_enable),
        .write_addr(s23_write_addr),
        .write_data(s23_write_data)
    );

    task check_outputs;
        begin
            if (s1_read_behavioral !== s1_expected ||
                s1_read_primitive !== s1_expected) begin
                $display("Stage1 history mismatch cycle=%0d addr=%0d expected=%0d behavioral=%0d primitive=%0d",
                         cycle, s1_read_addr, s1_expected,
                         s1_read_behavioral, s1_read_primitive);
                $fatal(1, "Stage1 history RAMB18 primitive mismatch");
            end
            if (s23_read_behavioral !== s23_expected ||
                s23_read_primitive !== s23_expected) begin
                $display("Stage23 history mismatch cycle=%0d addr=%0d expected=%0d behavioral=%0d primitive=%0d",
                         cycle, s23_read_addr, s23_expected,
                         s23_read_behavioral, s23_read_primitive);
                $fatal(1, "Stage23 history RAMB18 primitive mismatch");
            end
        end
    endtask

    initial begin
        // Wait for the UNISIM global reset to release before accessing RAM.
        #120;

        // Initialize every logical word through the normal write ports.
        for (i = 0; i < 64; i = i + 1) begin
            @(negedge clk);
            s1_write_enable = 1'b1;
            s1_write_addr = i[5:0];
            s1_write_data = $signed((i * 24'sd7919) ^ 24'h8a31c5);
            s1_golden[i] = s1_write_data;
            if (i < 32) begin
                s23_write_enable = 1'b1;
                s23_write_addr = i[4:0];
                s23_write_data = $signed((i * 22'sd4051) ^ 22'h25a39d);
                s23_golden[i] = s23_write_data;
            end else begin
                s23_write_enable = 1'b0;
            end
        end

        @(negedge clk);
        s1_write_enable = 1'b0;
        s23_write_enable = 1'b0;

        // Address sweep proves the full logical address map and sign packing.
        for (cycle = 0; cycle < 128; cycle = cycle + 1) begin
            @(negedge clk);
            s1_read_addr = cycle[5:0];
            s23_read_addr = cycle[4:0];
            s1_expected = s1_golden[cycle[5:0]];
            s23_expected = s23_golden[cycle[4:0]];
            @(posedge clk);
            #1 check_outputs;
        end

        // Random concurrent reads/writes, including signed full-scale values.
        // Same-address collisions are intentionally avoided because the
        // signed-off filters bypass the just-arriving sample instead of
        // depending on device collision semantics.
        for (cycle = 0; cycle < 5000; cycle = cycle + 1) begin
            @(negedge clk);
            s1_read_addr = $random(seed_ctrl);
            s23_read_addr = $random(seed_ctrl);
            s1_write_enable = (($random(seed_ctrl) & 3) == 0);
            s23_write_enable = (($random(seed_ctrl) & 3) == 0);
            s1_write_addr = $random(seed_ctrl);
            s23_write_addr = $random(seed_ctrl);
            if (s1_write_enable && s1_write_addr == s1_read_addr)
                s1_write_addr = s1_write_addr + 6'd1;
            if (s23_write_enable && s23_write_addr == s23_read_addr)
                s23_write_addr = s23_write_addr + 5'd1;

            if (cycle == 0)
                s1_write_data = 24'sh7fffff;
            else if (cycle == 1)
                s1_write_data = -24'sh800000;
            else
                s1_write_data = $random(seed_data);
            if (cycle == 0)
                s23_write_data = 22'sh1fffff;
            else if (cycle == 1)
                s23_write_data = -22'sh200000;
            else
                s23_write_data = $random(seed_data);

            s1_expected = s1_golden[s1_read_addr];
            s23_expected = s23_golden[s23_read_addr];
            @(posedge clk);
            #1 check_outputs;
            if (s1_write_enable)
                s1_golden[s1_write_addr] = s1_write_data;
            if (s23_write_enable)
                s23_golden[s23_write_addr] = s23_write_data;
        end

        $display("HISTORY RAMB18 PRIMITIVE PASS: Stage1 64x24 and Stage2/3 32x22, sweep=128 random=5000");
        $finish;
    end
endmodule
