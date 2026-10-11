`timescale 1ns / 1ps
`default_nettype none

module hdmi (
    input  logic       hdmi_clk,      // pixel clock
    input  logic       hdmi_clk_5x,   // 5x pixel clock, DDR serializer clock
    input  logic [2:0] hve,           // {DE, VSYNC, HSYNC}
    input  logic [23:0] rgb,
    input  logic       reset,
    output logic [3:0] hdmi_tx_p
);

    // ------------------------------------------------------------------
    // Pipeline control & colour to the pixel-clock domain
    // ------------------------------------------------------------------
    logic [2:0]  hve_p;
    logic [23:0] rgb_p;

    always_ff @(posedge hdmi_clk) begin
        if (reset) begin
            hve_p <= 3'b0;
            rgb_p <= 24'b0;
        end else begin
            hve_p <= hve;
            rgb_p <= rgb;
        end
    end

    // ------------------------------------------------------------------
    // TMDS encoders – MUST be clocked by the pixel clock
    // ------------------------------------------------------------------
    logic [9:0] tmds_ch0, tmds_ch1, tmds_ch2;

    tmds encode_b (
        .i_hdmi_clk     (hdmi_clk),       // <-- pixel clock
        .i_rst          (reset),
        .i_color        (rgb_p[7:0]),     // <-- pipelined
        .i_ctrl         (hve_p[1:0]),
        .i_display_en   (hve_p[2]),
        .o_tmds_encoded (tmds_ch0)
    );

    tmds encode_g (
        .i_hdmi_clk     (hdmi_clk),
        .i_rst          (reset),
        .i_color        (rgb_p[15:8]),
        .i_ctrl         (2'b00),
        .i_display_en   (hve_p[2]),
        .o_tmds_encoded (tmds_ch1)
    );

    tmds encode_r (
        .i_hdmi_clk     (hdmi_clk),
        .i_rst          (reset),
        .i_color        (rgb_p[23:16]),
        .i_ctrl         (2'b00),
        .i_display_en   (hve_p[2]),
        .o_tmds_encoded (tmds_ch2)
    );

    // ------------------------------------------------------------------
    // 10-bit serializers
    // ------------------------------------------------------------------
    logic serial_tmds0, serial_tmds1, serial_tmds2;

    serial10b ser_c0 (
        .i_ser_clk  (hdmi_clk_5x),
        .i_pix_clk  (hdmi_clk),
        .i_rst  (reset),
        .i_data (tmds_ch0),
        .o_data (serial_tmds0)
    );

    serial10b ser_c1 (
        .i_ser_clk  (hdmi_clk_5x),
        .i_pix_clk  (hdmi_clk),
        .i_rst  (reset),
        .i_data (tmds_ch1),
        .o_data (serial_tmds1)
    );

    serial10b ser_c2 (
        .i_ser_clk  (hdmi_clk_5x),
        .i_pix_clk  (hdmi_clk),
        .i_rst  (reset),
        .i_data (tmds_ch2),
        .o_data (serial_tmds2)
    );

    // ------------------------------------------------------------------
    // Differential drivers
    // ------------------------------------------------------------------
    differential c0_df (.data(serial_tmds0),   .p(hdmi_tx_p[0]));
    differential c1_df (.data(serial_tmds1),   .p(hdmi_tx_p[1]));
    differential c2_df (.data(serial_tmds2),   .p(hdmi_tx_p[2]));
    differential c3_df (.data(hdmi_clk),  .p(hdmi_tx_p[3]));

endmodule

`default_nettype wire
