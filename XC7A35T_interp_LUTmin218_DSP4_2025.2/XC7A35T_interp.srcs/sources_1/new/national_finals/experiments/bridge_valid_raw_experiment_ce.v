`timescale 1ns / 1ps

// Experiment-only valid bridge.  It preserves the sample bits so the
// downstream DSP can evaluate whether absorbing the inter-stage quantizer is
// cheaper than the signed round/saturate bridge used by the signed-off core.
module bridge_valid_raw_experiment_ce #(
    parameter integer DATA_W = 24
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire signed [DATA_W-1:0]     in_data,
    input  wire                         in_valid,
    input  wire                         ce_out_next,
    input  wire                         phase_current,
    output wire signed [DATA_W-1:0]     out_data,
    output wire                         out_valid
);

    reg                     pending;
    wire                    consume_now = pending && ce_out_next && !phase_current;

    // The upstream registered output remains stable until this bridge is
    // consumed; keeping the data combinational avoids duplicating DATA_W FFs.
    assign out_data = in_data;
    assign out_valid = pending;

    always @(posedge clk) begin
        if (!rst_n) begin
            pending <= 1'b0;
        end
        else begin
            if (consume_now)
                pending <= in_valid;
            else if (in_valid)
                pending <= 1'b1;
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && pending && !consume_now && in_valid)
            $fatal(1, "raw experiment bridge input overwrite");
    end
`endif

endmodule
