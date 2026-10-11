`timescale 1ns / 1ps
`default_nettype none
`include "tb_check.svh"

// End-to-end: 25 MHz in, PLL model, raster, pattern, TMDS, serializers.
// Decodes the three data lanes back into {DE, VSYNC, HSYNC, R, G, B} and checks
// one full frame (plus the start of the next) against VESA 640x480@60 with
// negative syncs and the gradient pattern.
module tb_steer;
    import tmds_ref::*;

    localparam int HRES = 640, HFP = 16, HSYNC = 96, HBP = 48;
    localparam int VRES = 480, VFP = 10, VSYNC = 2,  VBP = 33;
    localparam int HT = HFP + HSYNC + HBP + HRES;   // 800
    localparam int VT = VFP + VSYNC + VBP + VRES;   // 525
    localparam int CHECK_PIX = HT * VT + 2 * HT;     // one frame + 2 lines

    logic clk = 1'b0;
    always #20 clk = ~clk;   // 25 MHz

    wire       led_locked;
    wire [3:0] gpdi_dp;

    steer dut (.i_clk(clk), .led_locked(led_locked), .gpdi_dp(gpdi_dp));

    wire ser_clk = dut.hdmi_clk_5x;

    tmds_rx rx0 (.ser_clk(ser_clk), .pix_clk(clk), .lane(gpdi_dp[0]));
    tmds_rx rx1 (.ser_clk(ser_clk), .pix_clk(clk), .lane(gpdi_dp[1]));
    tmds_rx rx2 (.ser_clk(ser_clk), .pix_clk(clk), .lane(gpdi_dp[2]));

    int checks = 0;

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

        #1;
        `CHECK(led_locked === 1'b0, ("led_locked=%b before the PLL locks", led_locked))

        // Run until one full frame after the first vsync has been received.
        repeat (CHECK_PIX + 12 * HT) @(posedge clk);
        `CHECK(led_locked === 1'b1, ("PLL never locked"))

        decode_lanes();

        // Frame origin: first pixel of the vsync pulse (active low).
        for (int k = 1; k < pix.size() && origin < 0; k++)
            if (!pix[k].de && !pix[k].vs && !pix[k - 1].de && pix[k - 1].vs)
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
                automatic int x = h - (HFP + HSYNC + HBP);
                automatic int y = v - (VSYNC + VBP);
                `CHECK(p.de, ("frame pixel (%0d,%0d) line %0d: blanking, expected video", h, v, v))
                `CHECK(p.r == 8'(x * 255 / HRES) && p.g == 8'h00 && p.b == 8'(y * 255 / VRES),
                       ("pixel (%0d,%0d): rgb %02h%02h%02h expected %02h00%02h", x, y, p.r, p.g, p.b,
                        8'(x * 255 / HRES), 8'(y * 255 / VRES)))
            end else begin
                `CHECK(!p.de, ("frame position h=%0d v=%0d: video, expected blanking", h, v))
                `CHECK(p.hs == !hs_act && p.vs == !vs_act,
                       ("frame position h=%0d v=%0d: hsync=%b vsync=%b expected %b/%b (active low)",
                        h, v, p.hs, p.vs, !hs_act, !vs_act))
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
