module steer #(
    parameter FB_INIT_FILE = "build/fb_init.hex"   // power-up image, see scripts/fb_image.py
  ) (
    input  i_clk,
    output led_locked,
    output [3:0]gpdi_dp,

    // Frame buffer write port, own clock domain. Pixel (x, y) is at
    // address y*800 + x; data is RGB222 {r1 r0 g1 g0 b1 b0}.
    input        i_fb_wclk,
    input        i_fb_we,
    input [18:0] i_fb_waddr,
    input [5:0]  i_fb_wdata
  );

  wire hdmi_clk_5x;
  wire pix_clk;
  wire pll_locked;

  // 800x600 @ 60 Hz (1056x628 total): 40 MHz pixel clock and the 200 MHz
  // DDR serial clock (5x), phase-aligned, both from the 25 MHz oscillator.
  pll hdmi_pll(
    .clkin(i_clk),
    .clkout0(hdmi_clk_5x),
    .clkout1(pix_clk),
    .locked(pll_locked));

  assign led_locked = pll_locked;

  localparam H_RES = 800;
  localparam V_RES = 600;

  wire signed [12:0] x, y;
  wire [2:0] hve;

  display_signal #(
    .H_RESOLUTION(H_RES),
    .V_RESOLUTION(V_RES),
    .H_FRONT_PORCH(40),
    .H_SYNC(128),
    .H_BACK_PORCH(88),
    .V_FRONT_PORCH(1),
    .V_SYNC(4),
    .V_BACK_PORCH(23),
    .H_SYNC_POLARITY(1),
    .V_SYNC_POLARITY(1)
    ) ds (
      .i_pixel_clk(pix_clk),
      .x(x),
      .y(y),
      .o_hve(hve)
    );

  // The frame buffer delays hve by its read latency, so the colour and the
  // sync/DE bits reach hdmi together.
  wire [2:0]  hve_fb;
  wire [23:0] rgb;

  framebuffer #(
    .W(H_RES),
    .H(V_RES),
    .INIT_FILE(FB_INIT_FILE)
    ) fb (
    .pix_clk(pix_clk),
    .x(x),
    .y(y),
    .i_hve(hve),
    .o_hve(hve_fb),
    .rgb(rgb),
    .wclk(i_fb_wclk),
    .we(i_fb_we),
    .waddr(i_fb_waddr),
    .wdata(i_fb_wdata));

  hdmi h_out(
    .reset(~pll_locked),
    .hdmi_clk(pix_clk),
    .hdmi_clk_5x(hdmi_clk_5x),
    .hve(hve_fb),
    .rgb(rgb),
    .hdmi_tx_p(gpdi_dp));
endmodule
