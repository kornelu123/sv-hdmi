// Simulation-only behavioural model of the Lattice ECP5 ODDRX1F primitive
// (yosys ships only a blackbox for it).
//
// D0/D1 are captured on the rising SCLK edge; Q drives the captured D0 while
// SCLK is high and the captured D1 while SCLK is low, i.e. one SCLK cycle of
// latency with D0 transmitted first. RST synchronously clears both registers.
`timescale 1ns / 1ps
module ODDRX1F #(
    parameter GSR = "ENABLED"
) (
    input  wire SCLK,
    input  wire RST,
    input  wire D0,
    input  wire D1,
    output wire Q
);
    reg q0 = 1'b0;
    reg q1 = 1'b0;

    always @(posedge SCLK) begin
        if (RST) begin
            q0 <= 1'b0;
            q1 <= 1'b0;
        end else begin
            q0 <= D0;
            q1 <= D1;
        end
    end

    assign Q = SCLK ? q0 : q1;
endmodule
