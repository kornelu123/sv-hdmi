`timescale 1ns / 1ps
`default_nettype none
`include "tb_check.svh"

// Board-level wrapper: LED pattern, PLL-lock LED, HDMI pins connected to steer.
// The video content itself is covered by tb_steer.
module tb_top;
    logic clk_25mhz = 1'b0;
    always #20 clk_25mhz = ~clk_25mhz;

    wire [7:0] led;
    wire [3:0] gpdi_dp;

    top dut (.clk_25mhz(clk_25mhz), .led(led), .gpdi_dp(gpdi_dp));

    int checks = 0;

    initial begin : main
        automatic int toggles [3] = '{0, 0, 0};
        logic [2:0] prev;

        #1;
        `CHECK(led === 8'b1010_1010, ("led=%b before PLL lock, expected 10101010", led))

        fork
            wait (led[0] === 1'b1);
            begin
                #2us;
                $fatal(1, "led[0] (PLL locked) never lit");
            end
        join_any
        disable fork;
        `CHECK(led === 8'b1010_1011, ("led=%b after PLL lock, expected 10101011", led))

        // Clock lane is the pixel clock; data lanes are active after lock.
        @(posedge dut.st.hdmi_clk_5x);
        prev = gpdi_dp[2:0];
        repeat (500) begin
            @(posedge dut.st.hdmi_clk_5x or negedge dut.st.hdmi_clk_5x);
            #1;
            `CHECK(gpdi_dp[3] === clk_25mhz, ("gpdi_dp[3]=%b, clk_25mhz=%b", gpdi_dp[3], clk_25mhz))
            for (int i = 0; i < 3; i++)
                if (gpdi_dp[i] !== prev[i]) toggles[i]++;
            prev = gpdi_dp[2:0];
            `CHECK(led === 8'b1010_1011, ("led changed to %b", led))
        end
        for (int i = 0; i < 3; i++)
            `CHECK(toggles[i] > 100, ("gpdi_dp[%0d] toggled only %0d times in 50 pixel clocks", i, toggles[i]))

        $display("PASS tb_top: %0d checks", checks);
        $finish;
    end

    initial begin
        #1ms;
        $fatal(1, "timeout");
    end

    `DUMP_WAVES(tb_top)
endmodule

`default_nettype wire
