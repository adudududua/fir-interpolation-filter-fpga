`timescale 1ns / 1ps

module tb_nf_x3_20m_fir_front_bittrue;
    localparam integer INPUT_COUNT = 256;
    localparam integer Y4_COUNT = 1245;
    localparam integer Y8_COUNT = 2499;
    localparam integer SHIFT_4X = 3;
    localparam integer SHIFT_8X = 7;

    reg sys_clk;
    reg audio_clk;
    reg sys_rst_n;
    reg audio_rst_n;
    reg [6:0] ce_cnt;
    reg input_phase;
    reg signed [23:0] x_in;
    reg signed [23:0] input_mem [0:INPUT_COUNT-1];
    reg signed [23:0] y4_expected [0:Y4_COUNT-1];
    reg signed [23:0] y8_expected [0:Y8_COUNT-1];
    integer input_index;
    integer y4_stream_index;
    integer y8_stream_index;
    integer y4_index;
    integer y8_index;
    integer mismatch_count;
    integer timeout_cycles;

    wire ce2 = (ce_cnt[5:0] == 6'd0);
    wire ce4 = (ce_cnt[4:0] == 5'd0);
    wire ce8 = (ce_cnt[3:0] == 4'd0);
    wire signed [23:0] y2;
    wire y2_valid;
    wire signed [21:0] y4;
    wire y4_valid;
    wire signed [19:0] y8;
    wire y8_valid;
    wire input_overflow;
    wire output_overrun;

    nf_x3_20m_fir_front u_dut (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .audio_clk(audio_clk), .audio_rst_n(audio_rst_n),
        .audio_ce2(ce2), .audio_ce4(ce4), .audio_ce8(ce8),
        .x_in(x_in), .x_in_valid(1'b1),
        .y2_out(y2), .y2_out_valid(y2_valid),
        .y4_out(y4), .y4_out_valid(y4_valid),
        .y8_out(y8), .y8_out_valid(y8_valid),
        .input_overflow_dbg(input_overflow),
        .output_overrun_dbg(output_overrun),
        .sys_frame_cycle_dbg(), .sys_frame_active_dbg()
    );

    initial begin
        sys_clk = 1'b0;
        forever #25 sys_clk = ~sys_clk;
    end

    // Worst-case competition rate: 48 kHz input / 6.144 MHz audio clock.
    initial begin
        audio_clk = 1'b0;
        forever #81.380208 audio_clk = ~audio_clk;
    end

    always @(posedge audio_clk or negedge audio_rst_n) begin
        if (!audio_rst_n) begin
            ce_cnt <= 7'd0;
            input_phase <= 1'b1;
            input_index <= 0;
            x_in <= input_mem[0];
        end
        else begin
            ce_cnt <= ce_cnt + 7'd1;
            if (ce2) begin
                if (!input_phase) begin
                    input_index <= input_index + 1;
                    if (input_index + 1 < INPUT_COUNT)
                        x_in <= input_mem[input_index + 1];
                    else
                        x_in <= 24'sd0;
                end
                input_phase <= ~input_phase;
            end
        end
    end

    always @(posedge audio_clk or negedge audio_rst_n) begin
        if (!audio_rst_n) begin
            y4_stream_index <= 0;
            y8_stream_index <= 0;
            y4_index <= 0;
            y8_index <= 0;
            mismatch_count <= 0;
        end
        else begin
            if (y4_valid) begin
                if (^y4 === 1'bx) begin
                    mismatch_count = mismatch_count + 1;
                    $display("X3 y4 contains X at stream index %0d",
                             y4_stream_index);
                end
                else if (y4_stream_index >= SHIFT_4X &&
                         y4_index < Y4_COUNT) begin
                    if ({y4, 2'b00} !== y4_expected[y4_index]) begin
                        mismatch_count = mismatch_count + 1;
                        if (mismatch_count <= 20)
                            $display("X3 y4 mismatch index=%0d actual=%0d expected=%0d",
                                y4_index, $signed({y4,2'b00}),
                                $signed(y4_expected[y4_index]));
                    end
                    y4_index <= y4_index + 1;
                end
                y4_stream_index <= y4_stream_index + 1;
            end

            if (y8_valid) begin
                if (^y8 === 1'bx) begin
                    mismatch_count = mismatch_count + 1;
                    $display("X3 y8 contains X at stream index %0d",
                             y8_stream_index);
                end
                else if (y8_stream_index >= SHIFT_8X &&
                         y8_index < Y8_COUNT) begin
                    if ({y8, 4'b0000} !== y8_expected[y8_index]) begin
                        mismatch_count = mismatch_count + 1;
                        if (mismatch_count <= 20)
                            $display("X3 y8 mismatch index=%0d actual=%0d expected=%0d",
                                y8_index, $signed({y8,4'b0000}),
                                $signed(y8_expected[y8_index]));
                    end
                    y8_index <= y8_index + 1;
                end
                y8_stream_index <= y8_stream_index + 1;
            end
        end
    end

    initial begin
        $readmemh("../../../vectors/daily/impulse_input_24bit.mem",
                  input_mem);
        $readmemh("../../../vectors/daily/impulse_y4_golden_24bit.mem",
                  y4_expected);
        $readmemh("../../../vectors/daily/impulse_y8_golden_24bit.mem",
                  y8_expected);
        sys_rst_n = 1'b0;
        audio_rst_n = 1'b0;
        repeat (20) @(posedge sys_clk);
        @(negedge audio_clk);
        sys_rst_n = 1'b1;
        audio_rst_n = 1'b1;

        timeout_cycles = 0;
        while ((y4_index < Y4_COUNT || y8_index < Y8_COUNT) &&
               timeout_cycles < 50000) begin
            @(posedge audio_clk);
            timeout_cycles = timeout_cycles + 1;
        end

        if (input_overflow || output_overrun)
            $fatal(1, "X3 CDC status failure overflow=%0d overrun=%0d",
                   input_overflow, output_overrun);
        if (y4_index != Y4_COUNT || y8_index != Y8_COUNT)
            $fatal(1, "X3 output count insufficient y4=%0d y8=%0d",
                   y4_index, y8_index);
        if (mismatch_count != 0)
            $fatal(1, "X3 front bittrue mismatch count=%0d", mismatch_count);
        $display("NF X3 20M FIR FRONT BITTRUE PASS: y4=%0d y8=%0d, 0 LSB.",
                 y4_index, y8_index);
        $finish;
    end
endmodule
