`timescale 1ns / 1ps

// Atomic control-to-audio mode transfer.
//
// The source keeps mode_shadow stable from req_toggle until ack_toggle.
// The audio domain waits for the request synchronizer and the data bus to
// settle and captures both mode bits on one edge while the DAC is muted.
// Reset recovery also performs a capture, so a family
// clock switch cannot lose a request whose toggle equals the reset value.
module nf_mode_cdc_handshake #(
    parameter integer SETTLE_CYCLES = 3
)(
    input  wire       ctrl_clk,
    input  wire       ctrl_rst_n,
    input  wire [1:0] ctrl_mode,
    output wire       ctrl_busy,

    input  wire       audio_clk,
    input  wire       audio_rst_n,
    output reg  [1:0] audio_mode,
    output reg        audio_mute
);

    reg [1:0] mode_shadow = 2'b11;
    reg       req_toggle = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg ack_meta = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg ack_sync = 1'b0;

    reg       ack_toggle = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg req_meta = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg req_sync = 1'b0;
    reg       req_seen = 1'b0;
    // A one-hot token replaces the pending flag plus binary down-counter.
    // With SETTLE_CYCLES=3 the request follows
    // 0001 -> 0010 -> 0100 -> 1000 -> capture, which is cycle-identical to
    // count 3 -> 2 -> 1 -> 0 -> capture and removes the decrementer.
    reg [SETTLE_CYCLES:0] transfer_pipe =
        {{SETTLE_CYCLES{1'b0}}, 1'b1};
    assign ctrl_busy = (req_toggle != ack_sync);

    // Changes received while busy are folded into one latest-value transfer
    // after the current request completes.
    always @(posedge ctrl_clk) begin
        if (!ctrl_rst_n) begin
            mode_shadow <= 2'b11;
            req_toggle  <= 1'b0;
            ack_meta    <= 1'b0;
            ack_sync    <= 1'b0;
        end
        else begin
            ack_meta <= ack_toggle;
            ack_sync <= ack_meta;

            if ((req_toggle == ack_sync) && (ctrl_mode != mode_shadow)) begin
                mode_shadow <= ctrl_mode;
                req_toggle  <= ~req_toggle;
            end
        end
    end

    // mode_shadow is a bundled-data bus. The request handshake guarantees it
    // stays unchanged throughout SETTLE and WARMUP.
    always @(posedge audio_clk) begin
        if (!audio_rst_n) begin
            req_meta     <= 1'b0;
            req_sync     <= 1'b0;
            req_seen     <= 1'b0;
            ack_toggle   <= 1'b0;
            audio_mode   <= 2'b11;
            audio_mute   <= 1'b1;
            transfer_pipe <= {{SETTLE_CYCLES{1'b0}}, 1'b1};
        end
        else begin
            req_meta <= req_toggle;
            req_sync <= req_meta;

            if (transfer_pipe != {(SETTLE_CYCLES + 1){1'b0}}) begin
                audio_mute <= 1'b1;
                if (transfer_pipe[SETTLE_CYCLES]) begin
                    audio_mode <= mode_shadow;
                    req_seen <= req_sync;
                    ack_toggle <= req_sync;
                    transfer_pipe <= {(SETTLE_CYCLES + 1){1'b0}};
                end
                else
                    transfer_pipe <= transfer_pipe << 1;
            end
            else if (req_sync != req_seen) begin
                audio_mute <= 1'b1;
                transfer_pipe <= {{SETTLE_CYCLES{1'b0}}, 1'b1};
            end
            else begin
                audio_mute <= 1'b0;
            end
        end
    end

endmodule
