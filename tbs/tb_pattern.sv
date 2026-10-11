`timescale 1ns / 1ps
`default_nettype none
`include "tb_check.svh"

// Sweeps every visible x and y of one pattern configuration:
//   r = x * 255 / H_RES, g = 0, b = y * 255 / V_RES
module pattern_checker #(
    parameter int H_RES = 640,
    parameter int V_RES = 480
) (
    output bit done
);
    logic [12:0] x = '0, y = '0;
    wire  [7:0]  r, g, b;

    pattern #(.H_RES(H_RES), .V_RES(V_RES)) dut (.x(x), .y(y), .r(r), .g(g), .b(b));

    int checks = 0;

    task automatic check_pixel(input int px, input int py);
        x = 13'(px);
        y = 13'(py);
        #1;
        `CHECK(r == 8'(px * 255 / H_RES), ("%0dx%0d (%0d,%0d): r=%0d expected %0d", H_RES, V_RES, px, py, r, px * 255 / H_RES))
        `CHECK(g == 8'h00,                ("%0dx%0d (%0d,%0d): g=%0d expected 0", H_RES, V_RES, px, py, g))
        `CHECK(b == 8'(py * 255 / V_RES), ("%0dx%0d (%0d,%0d): b=%0d expected %0d", H_RES, V_RES, px, py, b, py * 255 / V_RES))
    endtask

    initial begin
        // Each channel depends on one coordinate: sweep x with random y and
        // y with random x, plus the four corners.
        for (int px = 0; px < H_RES; px++) check_pixel(px, $urandom_range(0, V_RES - 1));
        for (int py = 0; py < V_RES; py++) check_pixel($urandom_range(0, H_RES - 1), py);
        check_pixel(0, 0);
        check_pixel(H_RES - 1, 0);
        check_pixel(0, V_RES - 1);
        check_pixel(H_RES - 1, V_RES - 1);
        // The ramps reach the top of the 8-bit range at the last pixel.
        x = 13'(H_RES - 1);
        y = 13'(V_RES - 1);
        #1;
        `CHECK(r >= 8'd254 && b >= 8'd254, ("%0dx%0d: ramp ends at r=%0d b=%0d", H_RES, V_RES, r, b))
        done = 1'b1;
    end
endmodule

module tb_pattern;
    wire done_vga, done_xga;

    pattern_checker #(.H_RES(640),  .V_RES(480)) vga (.done(done_vga));
    pattern_checker #(.H_RES(1024), .V_RES(768)) xga (.done(done_xga));

    initial begin
        wait (done_vga && done_xga);
        $display("PASS tb_pattern: %0d checks", vga.checks + xga.checks);
        $finish;
    end

    `DUMP_WAVES(tb_pattern)
endmodule

`default_nettype wire
