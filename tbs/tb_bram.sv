`timescale 1ns / 1ps
`default_nettype none
`include "tb_check.svh"

module tb_bram;
    localparam string INIT = "tbs/data/bram_init.hex";

    logic clk = 1'b0;
    always #5 clk = ~clk;

    int checks = 0;

    // Small instance: AW=4 forces frequent read/write address collisions.
    logic       we_s = 1'b0;
    logic [3:0] wa_s = '0, ra_s = '0;
    logic [7:0] wd_s = '0;
    logic [7:0] rd_s;
    bram #(.AW(4), .DW(8), .INIT_FILE(INIT)) dut_small (
        .clk(clk), .we(we_s), .waddr(wa_s), .raddr(ra_s), .wdata(wd_s), .rdata(rd_s));

    // Default-parameter instance (64K x 16, no init file).
    logic        we_d = 1'b0;
    logic [15:0] wa_d = '0, ra_d = '0;
    logic [15:0] wd_d = '0;
    logic [15:0] rd_d;
    bram dut_big (
        .clk(clk), .we(we_d), .waddr(wa_d), .raddr(ra_d), .wdata(wd_d), .rdata(rd_d));

    logic [7:0]  img     [16];
    logic [7:0]  model_s [16];
    logic [15:0] model_d [int];

    // Inputs change on the falling edge; the registered read is checked
    // just after the following rising edge.
    task automatic cycle_small(input logic we, input logic [3:0] wa, input logic [7:0] wd,
                               input logic [3:0] ra, output logic [7:0] expected);
        @(negedge clk);
        we_s = we; wa_s = wa; wd_s = wd; ra_s = ra;
        expected = model_s[ra];             // read returns the pre-write value
        if (we) model_s[wa] = wd;
        @(posedge clk);
        #1;
    endtask

    initial begin : main
        logic [7:0] exp_s;
        automatic int collisions = 0;
        int written [$];

        $readmemh(INIT, img);
        model_s = img;

        // 1. Contents loaded from INIT_FILE, one-cycle read latency.
        for (int a = 0; a < 16; a++) begin
            cycle_small(1'b0, 4'(a), 8'h00, 4'(a), exp_s);
            `CHECK(rd_s === exp_s, ("init read addr %0d: got %02h expected %02h", a, rd_s, exp_s))
        end

        // 2. Read data is registered: it only changes on a clock edge.
        @(negedge clk);
        ra_s = 4'd3;
        #2;
        `CHECK(rd_s === img[15], ("rdata changed without a clock edge: %02h", rd_s))

        // 3. Random reads/writes against a reference memory, including
        //    read-during-write to the same address (old data expected) and
        //    we=0 cycles that must not modify memory.
        for (int i = 0; i < 20000; i++) begin
            automatic logic       we = 1'($urandom_range(0, 1));
            automatic logic [3:0] wa = 4'($urandom);
            automatic logic [3:0] ra = $urandom_range(0, 3) == 0 ? wa : 4'($urandom);
            automatic logic [7:0] wd = 8'($urandom);
            if (we && wa == ra && model_s[wa] != wd) collisions++;
            cycle_small(we, wa, wd, ra, exp_s);
            `CHECK(rd_s === exp_s, ("cycle %0d we=%b wa=%0d ra=%0d: got %02h expected %02h",
                                    i, we, wa, ra, rd_s, exp_s))
        end
        `CHECK(collisions > 100, ("only %0d read-during-write collisions exercised", collisions))

        // 4. Default 64K x 16 instance: writes across the full address range
        //    (both extremes included), each cycle reading back a random
        //    previously written address.
        written.push_back(0);
        written.push_back(32'hFFFF);
        model_d[0]       = 16'h1234;
        model_d[32'hFFFF] = 16'hABCD;
        foreach (written[k]) begin
            @(negedge clk);
            we_d = 1'b1; wa_d = 16'(written[k]); wd_d = model_d[written[k]];
        end
        for (int i = 0; i < 20000; i++) begin
            automatic logic [15:0] wa = 16'($urandom);
            automatic logic [15:0] wd = 16'($urandom);
            automatic int          ra = written[$urandom_range(0, written.size() - 1)];
            logic [15:0] exp_d;
            @(negedge clk);
            we_d = 1'b1; wa_d = wa; wd_d = wd; ra_d = 16'(ra);
            exp_d = model_d[ra];
            if (!model_d.exists(int'(wa))) written.push_back(int'(wa));
            model_d[int'(wa)] = wd;
            @(posedge clk);
            #1;
            `CHECK(rd_d === exp_d, ("64K read addr %04h: got %04h expected %04h", ra, rd_d, exp_d))
        end
        // Read back every address written in the 64K instance.
        @(negedge clk);
        we_d = 1'b0;
        foreach (written[k]) begin
            @(negedge clk);
            ra_d = 16'(written[k]);
            @(posedge clk);
            #1;
            `CHECK(rd_d === model_d[written[k]], ("64K readback addr %04h: got %04h expected %04h",
                                                  written[k], rd_d, model_d[written[k]]))
        end

        $display("PASS tb_bram: %0d checks", checks);
        $finish;
    end

    initial begin
        #10ms;
        $fatal(1, "timeout");
    end

    `DUMP_WAVES(tb_bram)
endmodule

`default_nettype wire
