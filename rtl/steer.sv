module steer(
    input  i_clk,
    output led_locked,
    output [3:0]gpdi_dp
  );

  wire hdmi_clk_5x;
  wire pll_locked;

  pll hdmi_pll(
    .clkin(i_clk),
    .clkout0(hdmi_clk_5x),
    .locked(pll_locked));

  assign led_locked = pll_locked;

  // 640x480 @ 60 Hz (800x525 total). The PLL fixes the pixel clock at 25 MHz
  // (125 MHz DDR serial clock / 5), which is the standard 640x480 rate.
  localparam H_RES = 640;
  localparam V_RES = 480;

  wire signed [12:0] x, y;
  wire [2:0] hve;

  display_signal #(
    .H_RESOLUTION(H_RES),
    .V_RESOLUTION(V_RES),
    .H_FRONT_PORCH(16),
    .H_SYNC(96),
    .H_BACK_PORCH(48),
    .V_FRONT_PORCH(10),
    .V_SYNC(2),
    .V_BACK_PORCH(33),
    .H_SYNC_POLARITY(0),
    .V_SYNC_POLARITY(0)
    ) ds (
      .i_pixel_clk(i_clk),
      .x(x),
      .y(y),
      .o_hve(hve)
    );

  wire [7:0] r, g, b;

  pattern #(
    .H_RES(H_RES),
    .V_RES(V_RES)
    ) dp (
    .x(x),
    .y(y),
    .r(r),
    .g(g),
    .b(b));

  hdmi h_out(
    .reset(~pll_locked),
    .hdmi_clk(i_clk),
    .hdmi_clk_5x(hdmi_clk_5x),
    .hve(hve),
    .rgb({r, g, b}),
    .hdmi_tx_p(gpdi_dp));
endmodule
