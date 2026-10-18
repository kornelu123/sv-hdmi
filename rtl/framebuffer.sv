`timescale 1ns / 1ps
`default_nettype none

// W x H frame buffer of RGB222 pixels, stored row-major (address y*W + x) as
// {r[1:0], g[1:0], b[1:0]} in block RAM.
//
// Read side follows the raster: the pixel position (x, y) and its
// {DE, VSYNC, HSYNC} go in, the colour expanded to 24 bits ({R, G, B}, each
// 2-bit channel replicated: 00, 55, AA, FF) and the same hve come out
// LATENCY = 2 pixel clocks later (address register + block RAM read).
// rgb is only meaningful while o_hve[2] (DE) is high.
//
// Write side is an independent port in its own clock domain (the block RAM
// ports are independent, so no clock-crossing logic is needed). Writes to the
// pixel being displayed at the same time can tear; nothing is synchronised to
// the raster.
module framebuffer #(
    parameter int W = 800,
    parameter int H = 600,
    parameter int AW = $clog2(W * H),
    parameter     INIT_FILE = ""   // $readmemh image, W*H 6-bit words; empty = uninitialised
) (
    input  logic               pix_clk,
    input  logic signed [12:0] x,          // visible area 0..W-1 while i_hve[2]
    input  logic signed [12:0] y,          // visible area 0..H-1 while i_hve[2]
    input  logic [2:0]         i_hve,      // {DE, VSYNC, HSYNC}
    output logic [2:0]         o_hve,
    output logic [23:0]        rgb,

    input  logic               wclk,
    input  logic               we,
    input  logic [AW-1:0]      waddr,      // y*W + x
    input  logic [5:0]         wdata       // {r[1:0], g[1:0], b[1:0]}
);

    // Stage 1: pixel address. Outside the visible area x/y are negative or
    // past the frame, so the address is parked at 0.
    logic [AW-1:0] raddr;
    logic [2:0]    hve_1;

    always_ff @(posedge pix_clk) begin
        raddr <= i_hve[2] ? AW'(y) * AW'(W) + AW'(x) : '0;
        hve_1 <= i_hve;
    end

    // Stage 2: registered block RAM read.
    logic [5:0] pixel;

    bram #(.AW(AW), .DW(6), .DEPTH(W * H), .INIT_FILE(INIT_FILE)) ram (
        .wclk  (wclk),
        .we    (we),
        .waddr (waddr),
        .wdata (wdata),
        .rclk  (pix_clk),
        .raddr (raddr),
        .rdata (pixel)
    );

    always_ff @(posedge pix_clk)
        o_hve <= hve_1;

    assign rgb = {{4{pixel[5:4]}}, {4{pixel[3:2]}}, {4{pixel[1:0]}}};

endmodule

`default_nettype wire
