`timescale 1ns / 1ps
`default_nettype none
`include "tb_check.svh"

// 10x3 frame (non-power-of-two depth) with an init image. Pixel and write
// clocks are unrelated. Checks the 2-clock read latency of rgb and hve, the
// RGB222 expansion, row-major addressing over raster and random visit orders,
// and that writes from the write-clock domain show up in later reads.
module tb_framebuffer;
    localparam int    W = 10, H = 3, AW = 5;
    localparam int    LATENCY = 2;
    localparam string INIT = "tbs/data/fb_init_10x3.hex";

    logic pclk = 1'b0, wclk = 1'b0;
    always #5   pclk = ~pclk;   // 100 MHz
    always #3.5 wclk = ~wclk;   // ~143 MHz, unrelated

    logic signed [12:0] x = '0, y = '0;
    logic [2:0]         hve_in = '0;
    logic [2:0]         hve_out;
    logic [23:0]        rgb;
    logic               we = 1'b0;
    logic [AW-1:0]      waddr = '0;
    logic [5:0]         wdata = '0;

    framebuffer #(.W(W), .H(H), .AW(AW), .INIT_FILE(INIT)) dut (
        .pix_clk(pclk), .x(x), .y(y), .i_hve(hve_in), .o_hve(hve_out), .rgb(rgb),
        .wclk(wclk), .we(we), .waddr(waddr), .wdata(wdata));

    typedef struct {
        logic [2:0] hve;
        int         x, y;
    } item_t;

    int         checks = 0;
    logic [5:0] model [W * H];
    item_t      pending [$];
    int         shown = 0;       // visible pixels checked

    function automatic logic [23:0] expand(input logic [5:0] p);
        return {{4{p[5:4]}}, {4{p[3:2]}}, {4{p[1:0]}}};
    endfunction

    // Present one raster position on the falling edge; after the next rising
    // edge the outputs belong to the position presented LATENCY edges earlier.
    task automatic pix(input bit de, input int xx, input int yy);
        item_t it;
        @(negedge pclk);
        hve_in = {de, 2'($urandom)};
        x = 13'(xx);
        y = 13'(yy);
        pending.push_back('{hve: hve_in, x: xx, y: yy});
        @(posedge pclk);
        #1;
        if (pending.size() < LATENCY) return;
        it = pending.pop_front();
        `CHECK(hve_out === it.hve, ("hve out %b, expected %b", hve_out, it.hve))
        if (it.hve[2]) begin
            `CHECK(rgb === expand(model[it.y * W + it.x]),
                   ("pixel (%0d,%0d): rgb %06h expected %06h", it.x, it.y, rgb, expand(model[it.y * W + it.x])))
            shown++;
        end
    endtask

    // One frame: a blanking line, then H lines of 3 blanking + W visible pixels.
    task automatic frame();
        for (int i = 0; i < W + 3; i++) pix(1'b0, i - 3, -1);
        for (int r = 0; r < H; r++)
            for (int i = 0; i < W + 3; i++) pix(i >= 3, i - 3, r);
    endtask

    task automatic write(input int a, input logic [5:0] d);
        @(negedge wclk);
        we = 1'b1; waddr = AW'(a); wdata = d;
        model[a] = d;
        @(negedge wclk);
        we = 1'b0;
    endtask

    initial begin : main
        $readmemh(INIT, model);

        // 1. Init image over a raster scan; every colour channel value appears.
        frame();
        frame();
        repeat (LATENCY - 1) pix(1'b0, -1, -1);
        `CHECK(shown == 2 * W * H, ("%0d visible pixels checked, expected %0d", shown, 2 * W * H))

        // 2. All 64 colours written from the write clock domain, read back.
        for (int a = 0; a < W * H; a++) write(a, 6'(a + 17));
        frame();
        for (int c = 0; c < 64; c++) begin
            write(c % (W * H), 6'(c));
            pix(1'b1, c % W, (c % (W * H)) / W);
            pix(1'b1, c % W, (c % (W * H)) / W);
        end

        // 3. Random positions and DE, random writes in between (not to a pixel
        //    whose read is in flight).
        for (int i = 0; i < 5000; i++) begin
            if ($urandom_range(0, 3) == 0) begin
                automatic int a = $urandom_range(0, W * H - 1);
                foreach (pending[k]) if (pending[k].y * W + pending[k].x == a) a = (a + 1) % (W * H);
                write(a, 6'($urandom));
            end
            if ($urandom_range(0, 4) == 0)
                pix(1'b0, -int'($urandom_range(1, 300)), -int'($urandom_range(0, 50)));
            else
                pix(1'b1, $urandom_range(0, W - 1), $urandom_range(0, H - 1));
        end
        repeat (LATENCY) pix(1'b0, -1, -1);

        $display("PASS tb_framebuffer: %0d checks (%0d visible pixels)", checks, shown);
        $finish;
    end

    initial begin
        #10ms;
        $fatal(1, "timeout");
    end

    `DUMP_WAVES(tb_framebuffer)
endmodule

`default_nettype wire
