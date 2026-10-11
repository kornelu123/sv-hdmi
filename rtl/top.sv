module top(
  input clk_25mhz,
  output [7:0]led,
  output [3:0]gpdi_dp);

  steer st(
    .i_clk(clk_25mhz),
    .led_locked(led[0]),   // lit once the HDMI PLL has locked
    .gpdi_dp(gpdi_dp)
  );

  assign led[7:1] = 7'b1010101;   // LEDs 7, 5, 3, 1 on; 6, 4, 2 off
endmodule
