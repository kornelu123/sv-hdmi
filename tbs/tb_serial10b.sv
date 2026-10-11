`timescale 1ns / 1ps
`default_nettype none
`include "tb_check.svh"

// serial10b is checked at several phase offsets between the 25 MHz pixel clock
// and the 125 MHz DDR serial clock. Offset 4 ns (pixel edge on a serial falling
// edge, where the pixel clock is sampled) is excluded: it is a true race.
module tb_serial10b;
    localparam int NPHASE      = 7;
    localparam int OFFS_NS [NPHASE] = '{0, 1, 2, 3, 5, 6, 7};
    localparam int NWORDS      = 2000;
    localparam int RESET_PIX   = 10;

    int checks = 0;

    // Pixel clock: rising edges at 0, 40, 80, ... ns.
    logic pix = 1'b0;
    initial forever begin
        pix = 1'b1; #20;
        pix = 1'b0; #20;
    end

    logic       rst  = 1'b1;
    logic [9:0] data = '0;
    logic [9:0] words [NWORDS + 8];
    longint     pix_n = 0;           // pixel rising edges seen so far
    bit         capture = 1'b0;      // collect serial bits once reset is released

    // i_data behaves like a register in the pixel domain (as tmds does):
    // it changes 1 ns after each pixel rising edge.
    always @(posedge pix) begin
        pix_n++;
        #1;
        data = words[pix_n];
    end

    for (genvar g = 0; g < NPHASE; g++) begin : ph
        logic ser = 1'b0;
        wire  o;
        bit   bits [$];

        initial begin
            #(OFFS_NS[g] * 1ns);
            forever begin
                ser = 1'b1; #4;
                ser = 1'b0; #4;
            end
        end

        serial10b dut (
            .i_pix_clk(pix),
            .i_ser_clk(ser),
            .i_rst    (rst),
            .i_data   (data),
            .o_data   (o)
        );

        // Sample the DDR output 1 ns after every serial-clock edge.
        task automatic sample();
            if (rst)
                `CHECK(o === 1'b0, ("phase %0d ns: o_data=%b during reset", OFFS_NS[g], o))
            else if (capture)
                bits.push_back(o);
        endtask

        always @(posedge ser) begin #1; sample(); end
        always @(negedge ser) begin #1; sample(); end
    end

    // Find the bit offset b and first word index s such that the serial stream
    // from b carries words[s], words[s+1], ... back to back, LSB first.
    task automatic check_stream(input int offs_ns, ref bit bits [$]);
        int b_found = -1, s_found = -1;
        int nfull;
        for (int b = 0; b < 30 && b_found < 0; b++) begin
            for (int s = RESET_PIX; s < RESET_PIX + 6 && b_found < 0; s++) begin
                bit ok = 1'b1;
                for (int k = 0; k < 50 && ok; k++)
                    for (int i = 0; i < 10 && ok; i++)
                        if (bits[b + 10 * k + i] !== words[s + k][i]) ok = 1'b0;
                if (ok) begin
                    b_found = b;
                    s_found = s;
                end
            end
        end
        `CHECK(b_found >= 0, ("phase %0d ns: serial stream does not carry the input words", offs_ns))

        // Nothing but zeros before the first word (shift register cleared).
        for (int i = 0; i < b_found; i++)
            `CHECK(bits[i] === 1'b0, ("phase %0d ns: bit %0d before first word is %b", offs_ns, i, bits[i]))

        // Every following word, contiguous, until the end of the capture.
        nfull = (bits.size() - b_found) / 10;
        if (s_found + nfull > NWORDS) nfull = NWORDS - s_found;
        `CHECK(nfull > NWORDS - 30, ("phase %0d ns: only %0d words captured", offs_ns, nfull))
        for (int k = 0; k < nfull; k++)
            for (int i = 0; i < 10; i++)
                `CHECK(bits[b_found + 10 * k + i] === words[s_found + k][i],
                       ("phase %0d ns: word %0d (%b) bit %0d mismatch", offs_ns, s_found + k,
                        words[s_found + k], i))
        $display("phase %0d ns: %0d words, first word %0d at bit %0d", offs_ns, nfull, s_found, b_found);
    endtask

    initial begin : main
        foreach (words[i]) words[i] = 10'($urandom);
        // Fixed patterns first so bit ordering errors cannot hide in noise.
        words[RESET_PIX + 1] = 10'h000;
        words[RESET_PIX + 2] = 10'h3FF;
        words[RESET_PIX + 3] = 10'h155;
        words[RESET_PIX + 4] = 10'h2AA;
        words[RESET_PIX + 5] = 10'h201;
        words[RESET_PIX + 6] = 10'h001;
        words[RESET_PIX + 7] = 10'h200;

        // Hold reset for RESET_PIX pixel cycles; release between clock edges.
        wait (pix_n == RESET_PIX);
        @(negedge pix);
        #0.5;
        rst     = 1'b0;
        capture = 1'b1;

        wait (pix_n == NWORDS);
        capture = 1'b0;

        check_stream(OFFS_NS[0], ph[0].bits);
        check_stream(OFFS_NS[1], ph[1].bits);
        check_stream(OFFS_NS[2], ph[2].bits);
        check_stream(OFFS_NS[3], ph[3].bits);
        check_stream(OFFS_NS[4], ph[4].bits);
        check_stream(OFFS_NS[5], ph[5].bits);
        check_stream(OFFS_NS[6], ph[6].bits);

        $display("PASS tb_serial10b: %0d checks", checks);
        $finish;
    end

    initial begin
        #1ms;
        $fatal(1, "timeout");
    end

    `DUMP_WAVES(tb_serial10b)
endmodule

`default_nettype wire
