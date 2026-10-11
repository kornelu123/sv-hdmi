`timescale 1ns / 1ps
`default_nettype none
`include "tb_check.svh"

// Checks one display_signal configuration cycle by cycle against an
// independent raster model. Pixel index 0 is the first front-porch pixel of
// the first front-porch line; lines and frames are laid out as
//   front porch | sync | back porch | visible
module ds_checker #(
    parameter int HRES = 8, HFP = 2, HSYNC = 3, HBP = 4,
    parameter int VRES = 4, VFP = 1, VSYNC = 2, VBP = 3,
    parameter int HPOL = 1, VPOL = 1,
    parameter int FRAMES = 3
) (
    input  wire clk,
    output bit  done
);
    localparam int HBLANK = HFP + HSYNC + HBP;
    localparam int VBLANK = VFP + VSYNC + VBP;
    localparam int HT     = HBLANK + HRES;
    localparam int VT     = VBLANK + VRES;

    wire        [2:0]  hve;
    wire signed [12:0] x, y;

    display_signal #(
        .H_RESOLUTION(HRES), .V_RESOLUTION(VRES),
        .H_FRONT_PORCH(HFP), .H_SYNC(HSYNC), .H_BACK_PORCH(HBP),
        .V_FRONT_PORCH(VFP), .V_SYNC(VSYNC), .V_BACK_PORCH(VBP),
        .H_SYNC_POLARITY(HPOL), .V_SYNC_POLARITY(VPOL)
    ) dut (
        .i_pixel_clk(clk),
        .o_hve(hve),
        .x(x),
        .y(y)
    );

    int checks = 0;

    initial begin : run
        automatic longint idx = 0;
        automatic int     h = 0, v = 0, hsync_len = 0, vsync_lines = 0;
        bit     hs_act, vs_act, de;

        // Outputs are registered: the first rising edge presents pixel 0.
        @(posedge clk);
        @(negedge clk);
        `CHECK(x == -HBLANK && y == -VBLANK,
               ("%0dx%0d: first pixel is (%0d,%0d), expected (%0d,%0d)", HRES, VRES, x, y, -HBLANK, -VBLANK))

        for (idx = 0; idx < longint'(FRAMES) * HT * VT + 2 * HT; idx++) begin
            h = int'(idx % HT);
            v = int'((idx / HT) % VT);
            hs_act = h >= HFP && h < HFP + HSYNC;
            vs_act = v >= VFP && v < VFP + VSYNC;
            de     = h >= HBLANK && v >= VBLANK;

            `CHECK(x == h - HBLANK && y == v - VBLANK,
                   ("%0dx%0d pixel %0d: (x,y)=(%0d,%0d) expected (%0d,%0d)", HRES, VRES, idx, x, y,
                    h - HBLANK, v - VBLANK))
            `CHECK(hve[2] == de,
                   ("%0dx%0d (%0d,%0d): display enable %b expected %b", HRES, VRES, x, y, hve[2], de))
            `CHECK(hve[1] == (VPOL != 0 ? vs_act : !vs_act),
                   ("%0dx%0d (%0d,%0d): vsync %b, sync active=%b polarity=%0d", HRES, VRES, x, y, hve[1], vs_act, VPOL))
            `CHECK(hve[0] == (HPOL != 0 ? hs_act : !hs_act),
                   ("%0dx%0d (%0d,%0d): hsync %b, sync active=%b polarity=%0d", HRES, VRES, x, y, hve[0], hs_act, HPOL))

            // Pulse widths measured from the outputs alone.
            if (hve[0] == 1'(HPOL)) hsync_len++;
            if (h == HT - 1) begin
                `CHECK(hsync_len == HSYNC, ("%0dx%0d line %0d: hsync pulse %0d pixels, expected %0d",
                                            HRES, VRES, v, hsync_len, HSYNC))
                hsync_len = 0;
                if (hve[1] == 1'(VPOL)) vsync_lines++;
            end
            if (h == HT - 1 && v == VT - 1) begin
                `CHECK(vsync_lines == VSYNC, ("%0dx%0d: vsync pulse %0d lines, expected %0d",
                                              HRES, VRES, vsync_lines, VSYNC))
                vsync_lines = 0;
            end
            @(negedge clk);
        end
        done = 1'b1;
    end
endmodule

module tb_display_signal;
    logic clk = 1'b0;
    always #1 clk = ~clk;

    wire done_vga, done_small, done_default;

    // 640x480@60 timing exactly as instantiated in steer (negative syncs).
    ds_checker #(
        .HRES(640), .HFP(16), .HSYNC(96), .HBP(48),
        .VRES(480), .VFP(10), .VSYNC(2), .VBP(33),
        .HPOL(0), .VPOL(0), .FRAMES(2)
    ) vga (.clk(clk), .done(done_vga));

    // Tiny raster, positive syncs, many frames.
    ds_checker #(
        .HRES(8), .HFP(2), .HSYNC(3), .HBP(4),
        .VRES(4), .VFP(1), .VSYNC(2), .VBP(3),
        .HPOL(1), .VPOL(1), .FRAMES(50)
    ) tiny (.clk(clk), .done(done_small));

    // Module default parameters (1280x1024, positive syncs).
    ds_checker #(
        .HRES(1280), .HFP(48), .HSYNC(112), .HBP(248),
        .VRES(1024), .VFP(1), .VSYNC(3), .VBP(38),
        .HPOL(1), .VPOL(1), .FRAMES(1)
    ) dflt (.clk(clk), .done(done_default));

    initial begin
        wait (done_vga && done_small && done_default);
        $display("PASS tb_display_signal: %0d checks", vga.checks + tiny.checks + dflt.checks);
        $finish;
    end

    initial begin
        #20ms;
        $fatal(1, "timeout");
    end

    `DUMP_WAVES(tb_display_signal)
endmodule

`default_nettype wire
