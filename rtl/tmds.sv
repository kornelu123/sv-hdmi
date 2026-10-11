`timescale 1ns / 1ps
`default_nettype none

module tmds (
  input  logic       i_hdmi_clk,
  input  logic       i_rst,
  input  logic [7:0] i_color,
  input  logic [1:0] i_ctrl,
  input  logic       i_display_en,
  output logic [9:0] o_tmds_encoded
);

  logic [3:0] n1_d;
  logic       use_xnor;
  logic [8:0] q_m;

  always_comb begin
    n1_d     = 4'($countones(i_color));
    use_xnor = (n1_d > 4'd4) || (n1_d == 4'd4 && i_color[0] == 1'b0);
    q_m[0]   = i_color[0];
    for (int i = 1; i < 8; i++)
      q_m[i] = use_xnor ? ~(q_m[i-1] ^ i_color[i]) : (q_m[i-1] ^ i_color[i]);
    q_m[8]   = ~use_xnor;
  end

  logic [3:0]        n1_q, n0_q;
  logic signed [5:0] bal;
  logic signed [5:0] cnt;

  assign n1_q = 4'($countones(q_m[7:0]));
  assign n0_q = 4'd8 - n1_q;
  assign bal  = $signed({2'b00, n1_q}) - $signed({2'b00, n0_q});

  always_ff @(posedge i_hdmi_clk) begin
    if (i_rst) begin
      o_tmds_encoded <= 10'b1101010100;
      cnt            <= '0;
    end else if (!i_display_en) begin
      case (i_ctrl)
        2'b00: o_tmds_encoded <= 10'b1101010100;
        2'b01: o_tmds_encoded <= 10'b0010101011;
        2'b10: o_tmds_encoded <= 10'b0101010100;
        2'b11: o_tmds_encoded <= 10'b1010101011;
      endcase
      cnt <= '0;
    end else if (cnt == 0 || n1_q == n0_q) begin
      o_tmds_encoded <= {~q_m[8], q_m[8], q_m[8] ? q_m[7:0] : ~q_m[7:0]};
      cnt            <= q_m[8] ? cnt + bal : cnt - bal;
    end else if ((cnt > 0 && n1_q > n0_q) || (cnt < 0 && n0_q > n1_q)) begin
      o_tmds_encoded <= {1'b1, q_m[8], ~q_m[7:0]};
      cnt            <= cnt + (q_m[8] ? 6'sd2 : 6'sd0) - bal;
    end else begin
      o_tmds_encoded <= {1'b0, q_m[8], q_m[7:0]};
      cnt            <= cnt - (q_m[8] ? 6'sd0 : 6'sd2) + bal;
    end
  end

endmodule

`default_nettype wire
