`timescale 1ns / 1ps
`default_nettype none
`include "tb_check.svh"

// Drives random video (active runs with random colours, blanking runs with
// random sync bits and junk colours) into hdmi, recovers each serial lane with
// tmds_rx and checks every received word against the input pixel it encodes.
module tb_hdmi;
    import tmds_ref::*;

    localparam int NPIX      = 6000;
    localparam int RESET_PIX = 10;

    // Phase-aligned clocks as produced by the PLL: rising edges coincide.
    logic hdmi_clk    = 1'b0;
    logic hdmi_clk_5x = 1'b0;
    always #20 hdmi_clk    = ~hdmi_clk;      // 25 MHz pixel clock
    always #4  hdmi_clk_5x = ~hdmi_clk_5x;   // 125 MHz DDR serial clock

    logic [2:0]  hve   = 3'b000;
    logic [23:0] rgb   = '0;
    logic        reset = 1'b1;
    wire  [3:0]  hdmi_tx_p;

    hdmi dut (
        .hdmi_clk    (hdmi_clk),
        .hdmi_clk_5x (hdmi_clk_5x),
        .hve         (hve),
        .rgb         (rgb),
        .reset       (reset),
        .hdmi_tx_p   (hdmi_tx_p)
    );

    tmds_rx rx0 (.ser_clk(hdmi_clk_5x), .pix_clk(hdmi_clk), .lane(hdmi_tx_p[0]));
    tmds_rx rx1 (.ser_clk(hdmi_clk_5x), .pix_clk(hdmi_clk), .lane(hdmi_tx_p[1]));
    tmds_rx rx2 (.ser_clk(hdmi_clk_5x), .pix_clk(hdmi_clk), .lane(hdmi_tx_p[2]));

    int     checks = 0;
    longint pix_n  = 0;                 // pixel-clock rising edges so far
    logic [2:0]  exp_hve [NPIX + 32];   // what the rising edge #n sampled
    logic [23:0] exp_rgb [NPIX + 32];

    always @(posedge hdmi_clk) pix_n++;

    // Data lanes are low during reset; the clock lane always is the pixel clock.
    always @(posedge hdmi_clk_5x or negedge hdmi_clk_5x) begin
        #1;
        `CHECK(hdmi_tx_p[3] === hdmi_clk, ("clock lane %b, pixel clock %b", hdmi_tx_p[3], hdmi_clk))
        if (reset)
            `CHECK(hdmi_tx_p[2:0] === 3'b000, ("data lanes %b during reset", hdmi_tx_p[2:0]))
    end

    // Inputs change on the falling edge; record what the next rising edge sees.
    // A pixel sampled under reset is expected as blanking with sync bits 00.
    task automatic drive(input logic r, input logic [2:0] h, input logic [23:0] c);
        @(negedge hdmi_clk);
        reset = r;
        hve   = h;
        rgb   = c;
        exp_hve[pix_n + 1] = r ? 3'b000 : h;
        exp_rgb[pix_n + 1] = c;
    endtask

    function automatic bit word_ok(input int lane, input logic [9:0] w, input longint j);
        logic [1:0] c;
        logic [2:0] h  = exp_hve[j];
        logic [7:0] px = exp_rgb[j][8 * lane +: 8];
        if (!h[2])
            return w == (lane == 0 ? CTRL_TOKEN[h[1:0]] : CTRL_TOKEN[0]);
        return !is_ctrl(w, c) && decode_data(w) == px;
    endfunction

    // Every word must match the input pixel `latency` pixel clocks earlier;
    // the latency is found from the first words and must then hold throughout.
    task automatic check_lane(input int lane, ref rx_item_t q [$], output int latency);
        int checked = 0;
        latency = -1;
        `CHECK(q.size() > NPIX - 100, ("lane %0d: only %0d words received (locked=%0d)", lane, q.size(), q.size() != 0))
        for (int l = 0; l <= 8 && latency < 0; l++) begin
            bit ok = 1'b1;
            for (int k = 0; k < 64 && ok; k++)
                if (!word_ok(lane, q[k].word, q[k].tag - l)) ok = 1'b0;
            if (ok) latency = l;
        end
        `CHECK(latency >= 0, ("lane %0d: received words match no fixed pipeline latency", lane))
        for (int k = 0; k < q.size(); k++) begin
            longint j = q[k].tag - latency;
            if (j > NPIX) break;
            `CHECK(k == 0 || q[k].tag == q[k-1].tag + 1, ("lane %0d: word %0d not one pixel after the previous", lane, k))
            `CHECK(word_ok(lane, q[k].word, j),
                   ("lane %0d pixel %0d: word %b for hve=%b rgb=%06h", lane, j, q[k].word, exp_hve[j], exp_rgb[j]))
            checked++;
        end
        $display("lane %0d: %0d words checked, latency %0d pixel clocks", lane, checked, latency);
    endtask

    initial begin : main
        int lat0, lat1, lat2;
        automatic int active = 0;

        for (int i = 0; i < RESET_PIX; i++) drive(1'b1, 3'($urandom), 24'($urandom));

        // Blanking long enough for the lane receivers to find word alignment.
        for (int i = 0; i < 40; i++) drive(1'b0, {1'b0, 2'($urandom)}, 24'($urandom));

        // Fixed colours, then random runs.
        begin
            automatic logic [23:0] fixed [5] = '{24'h000000, 24'hFFFFFF, 24'hFF0000, 24'h00FF00, 24'h0000FF};
            foreach (fixed[i]) repeat (8) drive(1'b0, 3'b100, fixed[i]);
        end
        while (pix_n < NPIX - 1) begin
            automatic bit de  = $urandom_range(0, 2) != 0;
            automatic int len = de ? $urandom_range(1, 64) : $urandom_range(1, 32);
            for (int i = 0; i < len && pix_n < NPIX - 1; i++) begin
                drive(1'b0, {de, 2'($urandom)}, 24'($urandom));
                if (de) active++;
            end
        end
        // Flush the pipeline.
        repeat (20) drive(1'b0, 3'b000, 24'h0);

        check_lane(0, rx0.words, lat0);
        check_lane(1, rx1.words, lat1);
        check_lane(2, rx2.words, lat2);
        `CHECK(lat0 == lat1 && lat1 == lat2, ("lane skew: latencies %0d/%0d/%0d", lat0, lat1, lat2))
        `CHECK(rx0.phase == rx1.phase && rx1.phase == rx2.phase,
               ("lane word boundaries differ: bit phases %0d/%0d/%0d", rx0.phase, rx1.phase, rx2.phase))

        $display("PASS tb_hdmi: %0d checks (%0d active pixels)", checks, active);
        $finish;
    end

    initial begin
        #2ms;
        $fatal(1, "timeout");
    end

    `DUMP_WAVES(tb_hdmi)
endmodule

`default_nettype wire
