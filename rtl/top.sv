module top(
  input clk_25mhz,
  output [7:0]led,
  output [3:0]gpdi_dp);

  // The frame buffer shows its power-up image; the write port is unused
  // until a writer (CPU, loader, ...) is added here.
  steer st(
    .i_clk(clk_25mhz),
    .led_locked(led[0]),   // lit once the HDMI PLL has locked
    .gpdi_dp(gpdi_dp),
    .i_fb_wclk(clk_25mhz),
    .i_fb_we(1'b0),
    .i_fb_waddr(19'd0),
    .i_fb_wdata(6'd0)
  );

  assign led[7:1] = 7'b1010101;   // LEDs 7, 5, 3, 1 on; 6, 4, 2 off
endmodule
