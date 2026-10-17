// Simple dual-port RAM: one write port and one registered read port, each in
// its own clock domain (ECP5 DP16KD ports are independent). DEPTH need not be
// a power of two; only DEPTH words are allocated, so e.g. an 800x600 frame
// does not round up to 2^19 words. Read-during-write on the same clock returns
// the old data.
module bram #(
    parameter AW = 16,
    parameter DW = 16,
    parameter DEPTH = 1 << AW,
    parameter INIT_FILE = ""   // optional $readmemh image; empty = no initialisation
  ) (
    input wclk,
    input we,
    input logic [AW-1:0] waddr,
    input logic [DW-1:0] wdata,
    input rclk,
    input logic [AW-1:0] raddr,
    output logic [DW-1:0] rdata
  );

  logic [DW-1:0] mem [0:DEPTH-1];

  initial if (INIT_FILE != "") $readmemh(INIT_FILE, mem);

  always_ff @(posedge wclk)
    if (we) mem[waddr] <= wdata;

  always_ff @(posedge rclk)
    rdata <= mem[raddr];
endmodule
