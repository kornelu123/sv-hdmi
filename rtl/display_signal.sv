// display_signal module converts a pixel clock into a hsync+vsync+disp_enable+x+y structure.
module display_signal #(
  H_RESOLUTION    = 1280,
  V_RESOLUTION    = 1024,
  H_FRONT_PORCH   = 48,
  H_SYNC          = 112,
  H_BACK_PORCH    = 248,
  V_FRONT_PORCH   = 1,
  V_SYNC          = 3,
  V_BACK_PORCH    = 38,
  H_SYNC_POLARITY = 1,   // 0: neg, 1: pos
  V_SYNC_POLARITY = 1    // 0: neg, 1: pos
)
(
  input  i_pixel_clk,
  output reg [2:0] o_hve,   // { display_enable, vsync, hsync} . hsync is active at desired H_SYNC_POLARITY and vsync is active at desired V_SYNC_POLARITY, display_enable is active high, low in blanking
  output reg signed [12:0] x, // screen x coordinate (negative in blanking, nonneg in visible picture area)
  output reg signed [12:0] y  // screen y coordinate (negative in blanking, nonneg in visible picture area)
);
  // A horizontal scanline consists of sequence of regions: front porch -> sync -> back porch -> display visible
  localparam signed H_START       = -H_BACK_PORCH - H_SYNC - H_FRONT_PORCH;
  localparam signed HSYNC_START   = -H_BACK_PORCH - H_SYNC;
  localparam signed HSYNC_END     = -H_BACK_PORCH;
  localparam signed HACTIVE_START = 0;
  localparam signed HACTIVE_END   = H_RESOLUTION - 1;
  // Vertical image frame has the same structure, but counts scanlines instead of pixel clocks.
  localparam signed V_START       = -V_BACK_PORCH - V_SYNC - V_FRONT_PORCH;
  localparam signed VSYNC_START   = -V_BACK_PORCH - V_SYNC;
  localparam signed VSYNC_END     = -V_BACK_PORCH;
  localparam signed VACTIVE_START = 0;
  localparam signed VACTIVE_END   = V_RESOLUTION - 1;

  // Free-running counters. x, y and o_hve are registered from the same counter
  // values, so all three outputs describe the same pixel in every cycle.
  reg signed [12:0] cx = 13'(H_START);
  reg signed [12:0] cy = 13'(V_START);

  always @(posedge i_pixel_clk) begin
    cx <= (cx == HACTIVE_END) ? 13'(H_START) : cx + 1'b1;
    if   (cx == HACTIVE_END) cy <= (cy == VACTIVE_END) ? 13'(V_START) : cy + 1'b1;
    x <= cx;
    y <= cy;
    o_hve <= { cx >= 0 && cy >= 0, // display enable is high when in visible picture area
               1'(V_SYNC_POLARITY) ~^ (cy >= VSYNC_START && cy < VSYNC_END), // vsync bit, equals V_SYNC_POLARITY during the pulse
               1'(H_SYNC_POLARITY) ~^ (cx >= HSYNC_START && cx < HSYNC_END) }; // hsync bit, equals H_SYNC_POLARITY during the pulse
  end
endmodule
