
`timescale 1ns / 1ps
`default_nettype none

module serial10b (
    input  wire       i_pix_clk,
    input  wire       i_ser_clk,  // 5x pixel clock
    input  wire       i_rst,
    input  wire [9:0] i_data,
    output wire       o_data
);

    reg [9:0] shift_reg = 10'b0;

    // The PLL phase-aligns the two clocks, so the pixel-clock edge coincides
    // with a serializer rising edge. Sample it on the serializer falling edge
    // (half a serial period of margin on both sides), then detect the rising
    // edge in the serializer rising-edge domain.
    reg pix_s  = 1'b0;
    reg pix_d1 = 1'b0;
    reg pix_d2 = 1'b0;

    wire load = pix_d1 & ~pix_d2;

    always @(negedge i_ser_clk) begin
        pix_s <= i_rst ? 1'b0 : i_pix_clk;
    end

    always @(posedge i_ser_clk) begin
        if (i_rst) begin
            pix_d1 <= 1'b0;
            pix_d2 <= 1'b0;
        end else begin
            pix_d1 <= pix_s;
            pix_d2 <= pix_d1;
        end
    end

    // Two bits are transmitted per serializer-clock cycle.
    // D0 is sent on the rising edge, D1 on the falling edge.
    always @(posedge i_ser_clk) begin
        if (i_rst) begin
            shift_reg <= 10'b0;
        end else if (load) begin
            shift_reg <= i_data;
        end else begin
            shift_reg <= {2'b00, shift_reg[9:2]};
        end
    end

    ODDRX1F ddr_out (
        .D0  (shift_reg[0]),
        .D1  (shift_reg[1]),
        .SCLK(i_ser_clk),
        .RST (i_rst),
        .Q   (o_data)
    );

endmodule

`default_nettype wire

