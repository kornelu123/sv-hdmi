module bram #(
    parameter AW = 16,
    parameter DW = 16,
    parameter INIT_FILE = ""   // optional $readmemh image; empty = no initialisation
  ) (
    input clk,
    input we,
    input logic [AW-1:0] waddr, raddr,
    input logic [DW-1:0] wdata,
    output logic [DW-1:0] rdata
  );

  logic [DW-1:0] mem [0:(1<<AW)-1];

  initial if (INIT_FILE != "") $readmemh(INIT_FILE, mem);

  always_ff @(posedge clk) begin
    if (we) mem[waddr] <= wdata;
    rdata <= mem[raddr];
  end
endmodule
