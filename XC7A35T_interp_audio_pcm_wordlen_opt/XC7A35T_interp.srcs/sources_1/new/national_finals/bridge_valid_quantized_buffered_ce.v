`timescale 1ns / 1ps

// Quantizing rate bridge with an explicit data register.  Unlike the compact
// valid-only bridge, this remains correct when the upstream FIR's valid pulse
// moves relative to the downstream CE because of a variable-length shared-MAC
// schedule.
module bridge_valid_quantized_buffered_ce #(
    parameter integer IN_W = 20,
    parameter integer OUT_W = 18,
    parameter integer SHIFT_N = IN_W - OUT_W
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire signed [IN_W-1:0]   in_data,
    input  wire                     in_valid,
    input  wire                     ce_out_next,
    output wire signed [OUT_W-1:0]  out_data,
    output wire                     out_valid
);

    reg pending;
    reg phase_mirror;
    reg signed [OUT_W-1:0] pending_data;
    wire signed [OUT_W-1:0] rounded_data;
    wire consume_now;

    round_sat_shift_compact #(
        .IN_W(IN_W), .OUT_W(OUT_W), .SHIFT_N(SHIFT_N)
    ) u_round (
        .din(in_data),
        .dout(rounded_data)
    );

    assign out_data = pending_data;
    assign out_valid = pending;
    assign consume_now = ce_out_next && !phase_mirror && pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending <= 1'b0;
            phase_mirror <= 1'b1;
            pending_data <= {OUT_W{1'b0}};
        end
        else begin
            if (consume_now)
                pending <= in_valid;
            else if (in_valid)
                pending <= 1'b1;

            if (in_valid)
                pending_data <= rounded_data;

            if (ce_out_next)
                phase_mirror <= ~phase_mirror;
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && pending && !consume_now && in_valid)
            $fatal(1, "buffered quantized bridge input overwrite");
    end
`endif

endmodule
