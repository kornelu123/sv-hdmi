`timescale 1ns / 1ps
`default_nettype none
`include "tb_check.svh"

module tb_differential;
    logic data = 1'b0;
    wire  p;
    int   checks = 0;

    differential dut (.data(data), .p(p));

    initial begin
        repeat (4) begin
            for (int v = 0; v < 2; v++) begin
                data = 1'(v);
                #1;
                `CHECK(p === data, ("p=%b for data=%b", p, data))
            end
        end
        $display("PASS tb_differential: %0d checks", checks);
        $finish;
    end

    `DUMP_WAVES(tb_differential)
endmodule

`default_nettype wire
