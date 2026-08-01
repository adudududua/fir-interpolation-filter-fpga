`timescale 1ns / 1ps

// X3 experiment: run the complete 2x/4x/8x FIR front end in the 20 MHz
// system-clock domain with one shared DSP48E1.  One input frame is executed
// in 128 system clocks.  Fully completed frames cross back to the audio clock
// through ping-pong banks, so no multi-bit sample is observed while changing.
module nf_x3_20m_fir_front (
    input  wire                         sys_clk,
    input  wire                         sys_rst_n,
    input  wire                         audio_clk,
    input  wire                         audio_rst_n,
    input  wire                         audio_ce2,
    input  wire                         audio_ce4,
    input  wire                         audio_ce8,
    input  wire signed [23:0]           x_in,
    input  wire                         x_in_valid,
    output reg  signed [23:0]           y2_out,
    output reg                          y2_out_valid,
    output reg  signed [21:0]           y4_out,
    output reg                          y4_out_valid,
    output reg  signed [19:0]           y8_out,
    output reg                          y8_out_valid,
    output wire                         input_overflow_dbg,
    output reg                          output_overrun_dbg,
    output wire [7:0]                   sys_frame_cycle_dbg,
    output wire                         sys_frame_active_dbg
);
    // ---------------------------------------------------------------
    // Audio-to-system input FIFO: one 24-bit word per input frame.
    // ---------------------------------------------------------------
    reg audio_input_phase;
    wire input_fifo_wr = audio_ce2 && !audio_input_phase && x_in_valid;
    wire [23:0] input_fifo_rd_data;
    wire input_fifo_full;
    wire input_fifo_empty;
    reg input_fifo_rd;
    wire input_fifo_underflow;

    always @(posedge audio_clk or negedge audio_rst_n) begin
        if (!audio_rst_n)
            audio_input_phase <= 1'b1;
        else if (audio_ce2)
            audio_input_phase <= ~audio_input_phase;
    end

    nf_async_fifo_gray #(.WIDTH(24), .ADDR_W(2)) u_input_fifo (
        .wr_clk(audio_clk),
        .wr_rst_n(audio_rst_n),
        .wr_en(input_fifo_wr),
        .wr_data(x_in),
        .wr_full(input_fifo_full),
        .wr_overflow(input_overflow_dbg),
        .rd_clk(sys_clk),
        .rd_rst_n(sys_rst_n),
        .rd_en(input_fifo_rd),
        .rd_data(input_fifo_rd_data),
        .rd_empty(input_fifo_empty),
        .rd_underflow(input_fifo_underflow)
    );

    // ---------------------------------------------------------------
    // A 160-clock virtual audio frame in the 20 MHz domain.  The actual CE
    // activity occupies cycles 0..112; cycles 113..159 are explicit control,
    // BRAM-prefetch and preemption headroom.  160 clocks is still below the
    // guide's 180/416-clock target at the worst-case 48 kHz input rate.
    // Stage1 phase events are deliberately at cycles 0 and 32.  This leaves
    // 96 clocks after its phase-0 launch, enough for the preemptible 26-MAC
    // job while Stage2/3 consume their fixed higher-priority slots.
    // ---------------------------------------------------------------
    reg sys_frame_active;
    reg [7:0] sys_frame_cycle;
    reg signed [23:0] sys_frame_sample;
    wire engine_ce2 = sys_frame_active &&
                      (sys_frame_cycle == 8'd0 ||
                       sys_frame_cycle == 8'd32);
    wire engine_ce4 = sys_frame_active && sys_frame_cycle < 8'd128 &&
                      (sys_frame_cycle[4:0] == 5'd0);
    // Stage3 is intentionally offset eight clocks from Stage2.  With a
    // single non-preemptible short-job accumulator, a simultaneous Stage3
    // launch would delay the Stage2 result past the next 16-clock consume
    // point.  Events at 8,24,...,120 preserve sample order and give every
    // Stage2 result a deterministic bridge window.
    wire engine_ce8 = sys_frame_active && sys_frame_cycle < 8'd128 &&
                      (sys_frame_cycle[3:0] == 4'd8);

    wire signed [23:0] engine_y2;
    wire engine_y2_valid;
    wire signed [21:0] engine_y4;
    wire engine_y4_valid;
    wire signed [19:0] engine_y8;
    wire engine_y8_valid;
    wire [1:0] engine_owner;
    wire [5:0] engine_index;
    wire engine_s1_pending;
    wire engine_s2_pending;
    wire engine_s3_pending;

    nf_interp_fir3_shared_mac_ce u_shared_fir (
        .clk(sys_clk),
        .rst_n(sys_rst_n),
        .ce2_out(engine_ce2),
        .ce4_out(engine_ce4),
        .ce8_out(engine_ce8),
        .x_in(sys_frame_sample),
        .x_in_valid(1'b1),
        .y2_out(engine_y2),
        .y2_out_valid(engine_y2_valid),
        .y4_out(engine_y4),
        .y4_out_valid(engine_y4_valid),
        .y8_out(engine_y8),
        .y8_out_valid(engine_y8_valid),
        .scheduler_owner_dbg(engine_owner),
        .scheduler_index_dbg(engine_index),
        .stage1_pending_dbg(engine_s1_pending),
        .stage2_pending_dbg(engine_s2_pending),
        .stage3_pending_dbg(engine_s3_pending)
    );

    // ---------------------------------------------------------------
    // System-domain ping-pong frame banks.
    // ---------------------------------------------------------------
    // Each rate is one single-clock-write/asynchronous-read distributed RAM.
    // The MSB of the address selects the ping-pong bank.
    (* ram_style = "distributed" *) reg signed [23:0] y2_bank [0:3];
    (* ram_style = "distributed" *) reg signed [21:0] y4_bank [0:7];
    (* ram_style = "distributed" *) reg signed [19:0] y8_bank [0:15];
    reg bank_write_select;
    reg bank_commit_select;
    reg bank_commit_toggle;
    reg [1:0] y2_write_count;
    reg [2:0] y4_write_count;
    reg [3:0] y8_write_count;

    // The payload arrays have no reset requirement.  Keeping their writes in
    // this reset-free process is required for Vivado LUTRAM inference.
    always @(posedge sys_clk) begin
        if (engine_y2_valid)
            y2_bank[{bank_write_select, y2_write_count[0]}] <= engine_y2;
        if (engine_y4_valid)
            y4_bank[{bank_write_select, y4_write_count[1:0]}] <= engine_y4;
        if (engine_y8_valid)
            y8_bank[{bank_write_select, y8_write_count[2:0]}] <= engine_y8;
    end

    // Synchronous system reset keeps all BRAM address/enable controls timed.
    always @(posedge sys_clk) begin
        if (!sys_rst_n) begin
            input_fifo_rd <= 1'b0;
            sys_frame_active <= 1'b0;
            sys_frame_cycle <= 8'd0;
            sys_frame_sample <= 24'sd0;
            bank_write_select <= 1'b0;
            bank_commit_select <= 1'b0;
            bank_commit_toggle <= 1'b0;
            y2_write_count <= 2'd0;
            y4_write_count <= 3'd0;
            y8_write_count <= 4'd0;
        end
        else begin
            input_fifo_rd <= 1'b0;

            if (!sys_frame_active) begin
                if (!input_fifo_empty) begin
                    input_fifo_rd <= 1'b1;
                    sys_frame_sample <= input_fifo_rd_data;
                    sys_frame_active <= 1'b1;
                    sys_frame_cycle <= 8'd0;
                    y2_write_count <= 2'd0;
                    y4_write_count <= 3'd0;
                    y8_write_count <= 4'd0;
                end
            end
            else if (sys_frame_cycle == 8'd159) begin
                sys_frame_active <= 1'b0;
                bank_commit_select <= bank_write_select;
                bank_commit_toggle <= ~bank_commit_toggle;
                bank_write_select <= ~bank_write_select;
            end
            else begin
                sys_frame_cycle <= sys_frame_cycle + 8'd1;
            end

            if (engine_y2_valid) begin
                y2_write_count <= y2_write_count + 2'd1;
            end
            if (engine_y4_valid) begin
                y4_write_count <= y4_write_count + 3'd1;
            end
            if (engine_y8_valid) begin
                y8_write_count <= y8_write_count + 4'd1;
            end
        end
    end

    // ---------------------------------------------------------------
    // Commit-toggle synchronizer and audio-domain bank reader.
    // bank_select is stable for an entire frame before the synchronized
    // toggle is acted on, so the multi-bit bank payload has ample settling.
    // ---------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg commit_toggle_meta;
    (* ASYNC_REG = "TRUE" *) reg commit_toggle_sync;
    (* ASYNC_REG = "TRUE" *) reg commit_select_meta;
    (* ASYNC_REG = "TRUE" *) reg commit_select_sync;
    reg commit_toggle_seen;
    reg audio_bank_select;
    reg audio_frame_available;
    reg [1:0] y2_read_count;
    reg [2:0] y4_read_count;
    reg [3:0] y8_read_count;
    wire signed [23:0] y2_bank_read =
        y2_bank[{audio_bank_select, y2_read_count[0]}];
    wire signed [21:0] y4_bank_read =
        y4_bank[{audio_bank_select, y4_read_count[1:0]}];
    wire signed [19:0] y8_bank_read =
        y8_bank[{audio_bank_select, y8_read_count[2:0]}];

    always @(posedge audio_clk or negedge audio_rst_n) begin
        if (!audio_rst_n) begin
            commit_toggle_meta <= 1'b0;
            commit_toggle_sync <= 1'b0;
            commit_select_meta <= 1'b0;
            commit_select_sync <= 1'b0;
            commit_toggle_seen <= 1'b0;
            audio_bank_select <= 1'b0;
            audio_frame_available <= 1'b0;
            y2_read_count <= 2'd0;
            y4_read_count <= 3'd0;
            y8_read_count <= 4'd0;
            y2_out <= 24'sd0;
            y4_out <= 22'sd0;
            y8_out <= 20'sd0;
            y2_out_valid <= 1'b0;
            y4_out_valid <= 1'b0;
            y8_out_valid <= 1'b0;
            output_overrun_dbg <= 1'b0;
        end
        else begin
            commit_toggle_meta <= bank_commit_toggle;
            commit_toggle_sync <= commit_toggle_meta;
            commit_select_meta <= bank_commit_select;
            commit_select_sync <= commit_select_meta;
            y2_out_valid <= 1'b0;
            y4_out_valid <= 1'b0;
            y8_out_valid <= 1'b0;

            if (commit_toggle_sync != commit_toggle_seen) begin
                if (audio_frame_available &&
                    (y2_read_count != 2 || y4_read_count != 4 ||
                     y8_read_count != 8))
                    output_overrun_dbg <= 1'b1;
                commit_toggle_seen <= commit_toggle_sync;
                audio_bank_select <= commit_select_sync;
                audio_frame_available <= 1'b1;
                y2_read_count <= 2'd0;
                y4_read_count <= 3'd0;
                y8_read_count <= 4'd0;
            end
            else if (audio_frame_available) begin
                if (audio_ce2 && y2_read_count < 2) begin
                    y2_out <= y2_bank_read;
                    y2_out_valid <= 1'b1;
                    y2_read_count <= y2_read_count + 2'd1;
                end
                if (audio_ce4 && y4_read_count < 4) begin
                    y4_out <= y4_bank_read;
                    y4_out_valid <= 1'b1;
                    y4_read_count <= y4_read_count + 3'd1;
                end
                if (audio_ce8 && y8_read_count < 8) begin
                    y8_out <= y8_bank_read;
                    y8_out_valid <= 1'b1;
                    y8_read_count <= y8_read_count + 4'd1;
                end
            end
        end
    end

    assign sys_frame_cycle_dbg = sys_frame_cycle;
    assign sys_frame_active_dbg = sys_frame_active;

`ifndef SYNTHESIS
    always @(posedge sys_clk) begin
        if (sys_rst_n && sys_frame_active && sys_frame_cycle == 8'd159) begin
            if (y2_write_count != 2 || y4_write_count != 4 ||
                y8_write_count != 8)
                $fatal(1,
                    "X3 frame count mismatch y2=%0d y4=%0d y8=%0d",
                    y2_write_count, y4_write_count, y8_write_count);
            if (engine_s1_pending || engine_s2_pending || engine_s3_pending)
                $fatal(1, "X3 shared FIR still pending at frame commit");
        end
        if (sys_rst_n && input_fifo_underflow)
            $fatal(1, "X3 input FIFO underflow");
    end

    always @(posedge audio_clk) begin
        if (audio_rst_n && input_overflow_dbg)
            $fatal(1, "X3 input FIFO overflow");
        if (audio_rst_n && output_overrun_dbg)
            $fatal(1, "X3 output ping-pong bank overrun");
    end
`endif
endmodule
