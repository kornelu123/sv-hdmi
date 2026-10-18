`timescale 1ns / 1ps
`default_nettype none
`include "tb_check.svh"

// End-to-end: 25 MHz in, PLL model, raster, frame buffer, TMDS, serializers.
// Decodes the three data lanes back into {DE, VSYNC, HSYNC, R, G, B} and checks
// one full frame (plus the start of the next) against VESA 800x600@60 with
// positive syncs and the frame buffer contents: the power-up image, with some
// pixels overwritten through the write port right after PLL lock.
module tb_steer;
    import tmds_ref::*;

    localparam int HRES = 800, HFP = 40, HSYNC = 128, HBP = 88;
    localparam int VRES = 600, VFP = 1,  VSYNC = 4,   VBP = 23;
    localparam int HT = HFP + HSYNC + HBP + HRES;   // 1056
    localparam int VT = VFP + VSYNC + VBP + VRES;   // 628
    localparam int CHECK_PIX = HT * VT + 2 * HT;     // one frame + 2 lines
    localparam string FB_INIT = "build/fb_init.hex";

    logic clk = 1'b0;
    always #20 clk = ~clk;   // 25 MHz

    wire       led_locked;
    wire [3:0] gpdi_dp;

    logic        fb_we    = 1'b0;
    logic [18:0] fb_waddr = '0;
    logic [5:0]  fb_wdata = '0;

    steer #(.FB_INIT_FILE(FB_INIT)) dut (
        .i_clk(clk), .led_locked(led_locked), .gpdi_dp(gpdi_dp),
        .i_fb_wclk(clk), .i_fb_we(fb_we), .i_fb_waddr(fb_waddr), .i_fb_wdata(fb_wdata));

    wire ser_clk = dut.hdmi_clk_5x;
    wire pix_clk = dut.pix_clk;

    tmds_rx rx0 (.ser_clk(ser_clk), .pix_clk(pix_clk), .lane(gpdi_dp[0]));
    tmds_rx rx1 (.ser_clk(ser_clk), .pix_clk(pix_clk), .lane(gpdi_dp[1]));
    tmds_rx rx2 (.ser_clk(ser_clk), .pix_clk(pix_clk), .lane(gpdi_dp[2]));

    int         checks = 0;
    logic [5:0] img [HRES * VRES];   // expected frame buffer contents

    function automatic logic [7:0] level(input logic [1:0] c);
        return {4{c}};
    endfunction

    typedef struct {
        bit         de, vs, hs;
        logic [7:0] r, g, b;
    } pixel_t;

    pixel_t pix [$];

    // Join the lanes by pixel tag and decode them into pixels.
    task automatic decode_lanes();
        int o1, o2;
        `CHECK(rx0.phase >= 0 && rx1.phase >= 0 && rx2.phase >= 0,
               ("lanes not locked: phases %0d/%0d/%0d", rx0.phase, rx1.phase, rx2.phase))
        `CHECK(rx0.phase == rx1.phase && rx1.phase == rx2.phase,
               ("lane word boundaries differ: bit phases %0d/%0d/%0d", rx0.phase, rx1.phase, rx2.phase))
        o1 = int'(rx0.words[0].tag - rx1.words[0].tag);
        o2 = int'(rx0.words[0].tag - rx2.words[0].tag);
        `CHECK(o1 >= 0 && o2 >= 0, ("lane 0 locked after lanes 1/2 (offsets %0d/%0d)", o1, o2))
        for (int k = 0; k < rx0.words.size() && k + o1 < rx1.words.size() && k + o2 < rx2.words.size(); k++) begin
            pixel_t     p;
            logic [1:0] c;
            logic [9:0] w0 = rx0.words[k].word;
            logic [9:0] w1 = rx1.words[k + o1].word;
            logic [9:0] w2 = rx2.words[k + o2].word;
            `CHECK(rx1.words[k + o1].tag == rx0.words[k].tag && rx2.words[k + o2].tag == rx0.words[k].tag,
                   ("lane tags diverge at word %0d", k))
            `CHECK(k == 0 || rx0.words[k].tag == rx0.words[k - 1].tag + 1, ("lane 0 skipped a pixel at word %0d", k))
            if (is_ctrl(w0, c)) begin
                `CHECK(w1 == CTRL_TOKEN[0] && w2 == CTRL_TOKEN[0],
                       ("pixel %0d: blanking on lane 0 but lanes 1/2 carry %b/%b", k, w1, w2))
                p = '{de: 1'b0, vs: c[1], hs: c[0], r: 8'h0, g: 8'h0, b: 8'h0};
            end else begin
                `CHECK(!is_ctrl(w1, c) && !is_ctrl(w2, c),
                       ("pixel %0d: video on lane 0 but lanes 1/2 carry %b/%b", k, w1, w2))
                p = '{de: 1'b1, vs: 1'b0, hs: 1'b0,
                      r: decode_data(w2), g: decode_data(w1), b: decode_data(w0)};
            end
            pix.push_back(p);
        end
    endtask

    initial begin : main
        automatic int origin = -1;

        $readmemh(FB_INIT, img);
        #1;
        `CHECK(led_locked === 1'b0, ("led_locked=%b before the PLL locks", led_locked))

        // Overwrite the corners and random pixels from the 25 MHz domain,
        // long before the checked frame's visible area starts.
        wait (led_locked === 1'b1);
        for (int i = 0; i < 200; i++) begin
            automatic int a = i == 0 ? 0 : i == 1 ? HRES - 1 : i == 2 ? HRES * (VRES - 1) :
                              i == 3 ? HRES * VRES - 1 : $urandom_range(0, HRES * VRES - 1);
            @(negedge clk);
            fb_we = 1'b1; fb_waddr = 19'(a); fb_wdata = 6'($urandom);
            img[a] = fb_wdata;
        end
        @(negedge clk);
        fb_we = 1'b0;

        // Run until one full frame after the first vsync has been received.
        repeat (CHECK_PIX + 12 * HT) @(posedge pix_clk);

        decode_lanes();

        // Frame origin: first pixel of the vsync pulse (active high).
        for (int k = 1; k < pix.size() && origin < 0; k++)
            if (!pix[k].de && pix[k].vs && !pix[k - 1].de && !pix[k - 1].vs)
                origin = k;
        `CHECK(origin >= 0, ("no vsync pulse found in %0d pixels", pix.size()))
        `CHECK(pix.size() >= origin + CHECK_PIX, ("only %0d pixels after vsync, need %0d", pix.size() - origin, CHECK_PIX))

        // Frame layout from the vsync line: sync | back porch | visible | front porch.
        // Line layout: front porch | sync | back porch | visible.
        for (int i = 0; i < CHECK_PIX; i++) begin
            automatic int     h      = i % HT;
            automatic int     v      = (i / HT) % VT;
            automatic bit     hs_act = h >= HFP && h < HFP + HSYNC;
            automatic bit     vs_act = v < VSYNC;
            automatic bit     de     = h >= HFP + HSYNC + HBP && v >= VSYNC + VBP && v < VSYNC + VBP + VRES;
            automatic pixel_t p      = pix[origin + i];
            if (de) begin
                automatic int         x = h - (HFP + HSYNC + HBP);
                automatic int         y = v - (VSYNC + VBP);
                automatic logic [5:0] c = img[y * HRES + x];
                `CHECK(p.de, ("frame pixel (%0d,%0d) line %0d: blanking, expected video", h, v, v))
                `CHECK(p.r == level(c[5:4]) && p.g == level(c[3:2]) && p.b == level(c[1:0]),
                       ("pixel (%0d,%0d): rgb %02h%02h%02h expected %02h%02h%02h", x, y, p.r, p.g, p.b,
                        level(c[5:4]), level(c[3:2]), level(c[1:0])))
            end else begin
                `CHECK(!p.de, ("frame position h=%0d v=%0d: video, expected blanking", h, v))
                `CHECK(p.hs == hs_act && p.vs == vs_act,
                       ("frame position h=%0d v=%0d: hsync=%b vsync=%b expected %b/%b (active high)",
                        h, v, p.hs, p.vs, hs_act, vs_act))
            end
        end

        $display("PASS tb_steer: %0d checks (%0d pixels decoded, frame starts at pixel %0d)",
                 checks, pix.size(), origin);
        $finish;
    end

    initial begin
        #50ms;
        $fatal(1, "timeout");
    end

    `DUMP_WAVES(tb_steer)
endmodule

`default_nettype wire
