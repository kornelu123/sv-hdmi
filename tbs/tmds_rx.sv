// Test-only TMDS lane receiver.
//
// Samples a DDR lane SAMPLE_DELAY after every edge of the 5x serial clock,
// LSB first. Word alignment is found from LOCK_RUN consecutive control tokens
// at the same bit phase (control tokens never occur in aligned data words).
// After lock, every aligned 10-bit word is appended to `words`, tagged with the
// number of pixel-clock rising edges seen so far; the tag-to-pixel offset is a
// constant pipeline latency.
`timescale 1ns / 1ps
module tmds_rx #(
    parameter int  LOCK_RUN     = 16,
    parameter time SAMPLE_DELAY = 1ns
) (
    input wire ser_clk,
    input wire pix_clk,
    input wire lane
);
    tmds_ref::rx_item_t words [$];
    int         phase  = -1;      // bit phase of word boundaries, -1 until locked
    longint     pix_count = 0;

    logic [9:0] window = '0;
    longint     nbits  = 0;
    int         run [10];

    always @(posedge pix_clk) pix_count++;

    task automatic take_bit();
        int p;
        logic [1:0] c;
        window = {lane, window[9:1]};
        nbits++;
        p = int'(nbits % 10);
        if (phase < 0) begin
            if (nbits >= 10) begin
                if (tmds_ref::is_ctrl(window, c)) run[p]++;
                else                             run[p] = 0;
                if (run[p] >= LOCK_RUN) phase = p;
            end
        end else if (p == phase) begin
            words.push_back('{tag: pix_count, word: window});
        end
    endtask

    always @(posedge ser_clk) begin
        #(SAMPLE_DELAY);
        take_bit();
    end

    always @(negedge ser_clk) begin
        #(SAMPLE_DELAY);
        take_bit();
    end
endmodule
