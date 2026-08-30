`timescale 1ps / 1ps

// Isolated feasibility candidate.  This file is not part of the formal project.
// It asks whether the two existing MMCMs can generate an exact 256x compute
// clock, select the active family on global clock routing, and derive the 128x
// audio clock synchronously with a BUFR divide-by-two.
module dual_family_clock_256x_candidate (
    input  wire clk_20m,
    input  wire reset,
    input  wire family_48k,
    output wire locked_selected,
    output wire activity_256x,
    output wire activity_128x
);

    wire clk_44k1_256x_raw;
    wire clk_48k_256x_raw;
    wire clk_compute_256x;
    wire clk_audio_128x;
    wire clkfb_44k1;
    wire clkfb_48k;
    wire locked_44k1;
    wire locked_48k;

    reg [3:0] count_256x = 4'd0;
    reg [3:0] count_128x = 4'd0;

    // 20 MHz / 2 * 62.375 / 55.25 = 11.289592760 MHz
    // Ideal 44.1-kHz-family 256x clock is 11.289600000 MHz (-0.64 ppm).
    MMCME2_ADV #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKOUT4_CASCADE("FALSE"),
        .COMPENSATION("ZHOLD"),
        .STARTUP_WAIT("FALSE"),
        .DIVCLK_DIVIDE(2),
        .CLKFBOUT_MULT_F(62.375),
        .CLKFBOUT_PHASE(0.0),
        .CLKFBOUT_USE_FINE_PS("FALSE"),
        .CLKOUT0_DIVIDE_F(55.250),
        .CLKOUT0_PHASE(0.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_USE_FINE_PS("FALSE"),
        .CLKIN1_PERIOD(50.0)
    ) u_mmcm_44k1 (
        .CLKFBOUT(clkfb_44k1),
        .CLKOUT0(clk_44k1_256x_raw),
        .CLKFBIN(clkfb_44k1),
        .CLKIN1(clk_20m),
        .CLKIN2(1'b0),
        .CLKINSEL(1'b1),
        .DADDR(7'd0),
        .DCLK(1'b0),
        .DEN(1'b0),
        .DI(16'd0),
        .DWE(1'b0),
        .PSCLK(1'b0),
        .PSEN(1'b0),
        .PSINCDEC(1'b0),
        .LOCKED(locked_44k1),
        .PWRDWN(1'b0),
        .RST(reset)
    );

    // 20 MHz * 36.25 / 59 = 12.288135593 MHz
    // Ideal 48-kHz-family 256x clock is 12.288000000 MHz (+11.03 ppm).
    MMCME2_ADV #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKOUT4_CASCADE("FALSE"),
        .COMPENSATION("ZHOLD"),
        .STARTUP_WAIT("FALSE"),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(36.250),
        .CLKFBOUT_PHASE(0.0),
        .CLKFBOUT_USE_FINE_PS("FALSE"),
        .CLKOUT0_DIVIDE_F(59.000),
        .CLKOUT0_PHASE(0.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_USE_FINE_PS("FALSE"),
        .CLKIN1_PERIOD(50.0)
    ) u_mmcm_48k (
        .CLKFBOUT(clkfb_48k),
        .CLKOUT0(clk_48k_256x_raw),
        .CLKFBIN(clkfb_48k),
        .CLKIN1(clk_20m),
        .CLKIN2(1'b0),
        .CLKINSEL(1'b1),
        .DADDR(7'd0),
        .DCLK(1'b0),
        .DEN(1'b0),
        .DI(16'd0),
        .DWE(1'b0),
        .PSCLK(1'b0),
        .PSEN(1'b0),
        .PSINCDEC(1'b0),
        .LOCKED(locked_48k),
        .PWRDWN(1'b0),
        .RST(reset)
    );

    BUFGMUX_CTRL u_bufgmux_compute_family (
        .I0(clk_44k1_256x_raw),
        .I1(clk_48k_256x_raw),
        .S(family_48k),
        .O(clk_compute_256x)
    );

    // The feasibility question is specifically whether this global-to-regional
    // clock transition is legal and routable on XC7A35T.  The experiment runs
    // place/route and DRC; synthesis success alone is not accepted.
    BUFR #(
        .BUFR_DIVIDE("2")
    ) u_bufr_audio_div2 (
        .I(clk_compute_256x),
        .CE(1'b1),
        .CLR(reset),
        .O(clk_audio_128x)
    );

    always @(posedge clk_compute_256x or posedge reset) begin
        if (reset)
            count_256x <= 4'd0;
        else
            count_256x <= count_256x + 1'b1;
    end

    always @(posedge clk_audio_128x or posedge reset) begin
        if (reset)
            count_128x <= 4'd0;
        else
            count_128x <= count_128x + 1'b1;
    end

    assign activity_256x = count_256x[3];
    assign activity_128x = count_128x[3];
    assign locked_selected = family_48k ? locked_48k : locked_44k1;

endmodule
