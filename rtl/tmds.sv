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

  // 1st stage
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

  logic [8:0] s1_q_m;
  logic [1:0] s1_ctrl;
  logic       s1_de;

  always_ff @(posedge i_hdmi_clk) begin
    if (i_rst) begin
      s1_de   <= 1'b0;
      s1_ctrl <= 2'b00;
    end else begin
      s1_de   <= i_display_en;
      s1_ctrl <= i_ctrl;
    end
    s1_q_m <= q_m;
  end

  // 2nd stage
  logic [3:0]        n1_q;
  logic signed [5:0] bal;

  assign n1_q = 4'($countones(s1_q_m[7:0]));
  assign bal  = $signed({1'b0, n1_q, 1'b0}) - 6'sd8;

  logic [8:0]        s2_q_m;
  logic [1:0]        s2_ctrl;
  logic              s2_de;
  logic              s2_bal_zero;
  logic              s2_bal_neg;
  logic signed [5:0] s2_d_inv;
  logic signed [5:0] s2_d_noinv;

  always_ff @(posedge i_hdmi_clk) begin
    if (i_rst) begin
      s2_de   <= 1'b0;
      s2_ctrl <= 2'b00;
    end else begin
      s2_de   <= s1_de;
      s2_ctrl <= s1_ctrl;
    end
    s2_q_m      <= s1_q_m;
    s2_bal_zero <= bal == 6'sd0;
    s2_bal_neg  <= bal < 6'sd0;
    s2_d_inv    <= (s1_q_m[8] ? 6'sd2 : 6'sd0) - bal;
    s2_d_noinv  <= bal - (s1_q_m[8] ? 6'sd0 : 6'sd2);
  end

  // 3rd stage
  logic signed [5:0] cnt;
  logic              invert;

  assign invert = (cnt == 6'sd0 || s2_bal_zero) ? ~s2_q_m[8] : (cnt[5] == s2_bal_neg);

  always_ff @(posedge i_hdmi_clk) begin
    if (i_rst) begin
      o_tmds_encoded <= 10'b1101010100;
      cnt            <= '0;
    end else if (!s2_de) begin
      case (s2_ctrl)
        2'b00: o_tmds_encoded <= 10'b1101010100;
        2'b01: o_tmds_encoded <= 10'b0010101011;
        2'b10: o_tmds_encoded <= 10'b0101010100;
        2'b11: o_tmds_encoded <= 10'b1010101011;
      endcase
      cnt <= '0;
    end else begin
      o_tmds_encoded <= {invert, s2_q_m[8], s2_q_m[7:0] ^ {8{invert}}};
      cnt            <= cnt + (invert ? s2_d_inv : s2_d_noinv);
    end
  end

endmodule

`default_nettype wire
