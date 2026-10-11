`timescale 1ns / 1ps
`default_nettype none
`include "tb_check.svh"

module tb_tmds;
    import tmds_ref::*;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic       rst   = 1'b1;
    logic [7:0] color = '0;
    logic [1:0] ctrl  = '0;
    logic       de    = 1'b0;
    logic [9:0] tmds;

    tmds dut (
        .i_hdmi_clk     (clk),
        .i_rst          (rst),
        .i_color        (color),
        .i_ctrl         (ctrl),
        .i_display_en   (de),
        .o_tmds_encoded (tmds)
    );

    int         checks = 0;
    enc_state_t ref_st;

    // Drive one input set on the falling edge and compare the registered
    // output after the next rising edge against the DVI reference encoder.
    task automatic step(input logic r, input logic d_en, input logic [1:0] c, input logic [7:0] col);
        logic [9:0] expected;
        logic [1:0] tok;
        @(negedge clk);
        rst = r; de = d_en; ctrl = c; color = col;
        @(posedge clk);
        #1;
        if (r) begin
            ref_st.cnt = 0;
            expected   = CTRL_TOKEN[0];
        end else begin
            expected = encode(ref_st, col, d_en, c);
        end
        `CHECK(tmds === expected, ("rst=%b de=%b ctrl=%b color=%02h: got %b expected %b (ref cnt %0d)",
                                   r, d_en, c, col, tmds, expected, ref_st.cnt))
        if (!r && d_en) begin
            `CHECK(!is_ctrl(tmds, tok), ("data %02h encoded as control token %b", col, tmds))
            `CHECK(decode_data(tmds) == col, ("data %02h decodes to %02h (%b)", col, decode_data(tmds), tmds))
        end
    endtask

    initial begin : main
        // 1. Reset output is the CTRL 00 token regardless of inputs.
        step(1'b1, 1'b1, 2'b11, 8'hFF);
        step(1'b1, 1'b0, 2'b10, 8'h00);
        step(1'b1, 1'b1, 2'b01, 8'h5A);

        // 2. Control tokens during blanking; colour must be ignored.
        for (int c = 0; c < 4; c++)
            for (int k = 0; k < 4; k++)
                step(1'b0, 1'b0, 2'(c), 8'($urandom));

        // 3. Every byte value, twice in a row (second pass starts with a
        //    non-zero running disparity).
        for (int pass = 0; pass < 2; pass++)
            for (int v = 0; v < 256; v++)
                step(1'b0, 1'b1, 2'b00, 8'(v));

        // 4. Long same-value runs push the running disparity to its extremes.
        begin
            automatic logic [7:0] vals [6] = '{8'h00, 8'hFF, 8'h01, 8'hFE, 8'h0F, 8'h10};
            foreach (vals[i])
                repeat (40) step(1'b0, 1'b1, 2'b00, vals[i]);
        end

        // 5. Blanking clears the running disparity: the first data word after
        //    a control period is encoded with cnt = 0.
        repeat (7) step(1'b0, 1'b1, 2'b00, 8'h01);
        step(1'b0, 1'b0, 2'b01, 8'h00);
        step(1'b0, 1'b1, 2'b00, 8'h01);

        // 6. Reset in the middle of active video clears the running disparity.
        repeat (5) step(1'b0, 1'b1, 2'b00, 8'hF0);
        step(1'b1, 1'b1, 2'b00, 8'hF0);
        repeat (5) step(1'b0, 1'b1, 2'b00, 8'hF0);

        // 7. Random video: active runs of random length separated by blanking.
        for (int i = 0; i < 2000; i++) begin
            automatic int  len = $urandom_range(1, 100);
            automatic bit  act = $urandom_range(0, 3) != 0;
            automatic logic [1:0] c = 2'($urandom);
            repeat (len) step(1'b0, act, c, 8'($urandom));
        end

        `CHECK(ref_st.branch_hits[0] > 0 && ref_st.branch_hits[1] > 0 && ref_st.branch_hits[2] > 0,
               ("disparity branches not all exercised: %0d/%0d/%0d",
                ref_st.branch_hits[0], ref_st.branch_hits[1], ref_st.branch_hits[2]))

        $display("PASS tb_tmds: %0d checks (disparity branches %0d/%0d/%0d)", checks,
                 ref_st.branch_hits[0], ref_st.branch_hits[1], ref_st.branch_hits[2]);
        $finish;
    end

    initial begin
        #100ms;
        $fatal(1, "timeout");
    end

    `DUMP_WAVES(tb_tmds)
endmodule

`default_nettype wire
