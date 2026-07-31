`timescale 1ns / 1ps

// Route-2 dual canonical halfband engine.
//
// Both stages use [-1 0 9 16 9 0 -1]/16.  Their filtered phases are
// mutually exclusive on the nested ce16/ce32 schedule, so the pair sums,
// shift/add expression, and round/saturation block are shared.
(* use_dsp = "no" *)
module interp2_dual_halfband7_shared_shiftadd_ce #(
    parameter integer DATA_W = 20
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ce16_out,
    input  wire                         ce32_out,
    input  wire signed [DATA_W-1:0]     x8_in,
    input  wire                         x8_in_valid,
    output reg  signed [DATA_W-1:0]     y16_out,
    output reg                          y16_out_valid,
    output reg  signed [DATA_W-1:0]     y32_out,
    output reg                          y32_out_valid,
    output wire                         phase16_dbg,
    output wire                         phase32_dbg
);

    localparam integer PAIR_W = DATA_W + 1;
    localparam integer ACC_W = DATA_W + 5;

    reg phase16;
    reg phase32;
    reg signed [DATA_W-1:0] h16_d1;
    reg signed [DATA_W-1:0] h16_d2;
    reg signed [DATA_W-1:0] h16_d3;
    reg signed [DATA_W-1:0] h32_d1;
    reg signed [DATA_W-1:0] h32_d2;
    reg signed [DATA_W-1:0] h32_d3;

    wire request_h16;
    wire request_h32;
    wire signed [DATA_W-1:0] shared_current;
    wire signed [DATA_W-1:0] shared_d1;
    wire signed [DATA_W-1:0] shared_d2;
    wire signed [DATA_W-1:0] shared_d3;
    wire signed [PAIR_W-1:0] pair_edge;
    wire signed [PAIR_W-1:0] pair_inner;
    wire signed [ACC_W-1:0] pair_edge_ext;
    wire signed [ACC_W-1:0] pair_inner_ext;
    wire signed [ACC_W-1:0] shared_acc;
    wire signed [DATA_W-1:0] shared_rounded;

    assign request_h16 = ce16_out && !phase16;
    assign request_h32 = ce32_out && !phase32;

    assign shared_current = request_h16 ? x8_in : y16_out;
    assign shared_d1 = request_h16 ? h16_d1 : h32_d1;
    assign shared_d2 = request_h16 ? h16_d2 : h32_d2;
    assign shared_d3 = request_h16 ? h16_d3 : h32_d3;

    assign pair_edge = $signed({shared_current[DATA_W-1], shared_current})
                     + $signed({shared_d3[DATA_W-1], shared_d3});
    assign pair_inner = $signed({shared_d1[DATA_W-1], shared_d1})
                      + $signed({shared_d2[DATA_W-1], shared_d2});
    assign pair_edge_ext =
        {{(ACC_W-PAIR_W){pair_edge[PAIR_W-1]}}, pair_edge};
    assign pair_inner_ext =
        {{(ACC_W-PAIR_W){pair_inner[PAIR_W-1]}}, pair_inner};
    assign shared_acc = -pair_edge_ext
                      + pair_inner_ext
                      + (pair_inner_ext <<< 3);

    round_sat_shift_compact #(
        .IN_W(ACC_W),
        .OUT_W(DATA_W),
        .SHIFT_N(4)
    ) u_shared_round_sat_q4_compact (
        .din(shared_acc),
        .dout(shared_rounded)
    );

    assign phase16_dbg = phase16;
    assign phase32_dbg = phase32;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase16 <= 1'b1;
            h16_d1 <= {DATA_W{1'b0}};
            h16_d2 <= {DATA_W{1'b0}};
            h16_d3 <= {DATA_W{1'b0}};
            y16_out <= {DATA_W{1'b0}};
            y16_out_valid <= 1'b0;
        end
        else begin
            y16_out_valid <= 1'b0;
            if (ce16_out) begin
                y16_out_valid <= 1'b1;
                if (!phase16) begin
                    y16_out <= shared_rounded;
                    h16_d3 <= h16_d2;
                    h16_d2 <= h16_d1;
                    h16_d1 <= x8_in;
                end
                else begin
                    y16_out <= h16_d2;
                end
                phase16 <= ~phase16;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase32 <= 1'b1;
            h32_d1 <= {DATA_W{1'b0}};
            h32_d2 <= {DATA_W{1'b0}};
            h32_d3 <= {DATA_W{1'b0}};
            y32_out <= {DATA_W{1'b0}};
            y32_out_valid <= 1'b0;
        end
        else begin
            y32_out_valid <= 1'b0;
            if (ce32_out) begin
                y32_out_valid <= 1'b1;
                if (!phase32) begin
                    y32_out <= shared_rounded;
                    h32_d3 <= h32_d2;
                    h32_d2 <= h32_d1;
                    h32_d1 <= y16_out;
                end
                else begin
                    y32_out <= h32_d2;
                end
                phase32 <= ~phase32;
            end
        end
    end

`ifndef SYNTHESIS
    reg input_seen;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            input_seen <= 1'b0;
        end
        else begin
            if (request_h16 && x8_in_valid)
                input_seen <= 1'b1;
            if (request_h16 && input_seen && !x8_in_valid)
                $display("WARNING: Route2 shared HB16 input missing at %0t",
                    $time);
            if (request_h16 && request_h32)
                $fatal(1, "Route2 shared halfband arithmetic collision");
        end
    end
`endif

endmodule
