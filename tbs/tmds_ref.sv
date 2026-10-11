// Test-only TMDS reference: encoder (DVI 1.0 spec, section 3.2.2), decoder and
// control-token table shared by tb_tmds, tb_hdmi and tb_steer.
package tmds_ref;

    localparam logic [9:0] CTRL_TOKEN [4] = '{
        10'b1101010100,   // {C1,C0} = 00
        10'b0010101011,   // 01
        10'b0101010100,   // 10
        10'b1010101011    // 11
    };

    // One word recovered by tmds_rx, tagged with the pixel-clock edge count.
    typedef struct {
        longint     tag;
        logic [9:0] word;
    } rx_item_t;

    // Encoder state: running disparity, cleared during blanking.
    typedef struct {
        int cnt;
        int branch_hits [3];   // which disparity branch produced each data word
    } enc_state_t;

    function automatic logic [9:0] encode(
        inout enc_state_t st,
        input logic [7:0] d,
        input logic       de,
        input logic [1:0] c
    );
        logic [8:0] qm;
        logic [9:0] q;
        int n1d, n1q, n0q;
        bit use_xnor;

        if (!de) begin
            st.cnt = 0;
            return CTRL_TOKEN[c];
        end

        n1d = $countones(d);
        use_xnor = (n1d > 4) || (n1d == 4 && d[0] == 1'b0);
        qm[0] = d[0];
        for (int i = 1; i < 8; i++)
            qm[i] = use_xnor ? ~(qm[i-1] ^ d[i]) : (qm[i-1] ^ d[i]);
        qm[8] = ~use_xnor;

        n1q = $countones(qm[7:0]);
        n0q = 8 - n1q;

        if (st.cnt == 0 || n1q == n0q) begin
            q[9]   = ~qm[8];
            q[8]   = qm[8];
            q[7:0] = qm[8] ? qm[7:0] : ~qm[7:0];
            st.cnt = qm[8] ? st.cnt + (n1q - n0q) : st.cnt + (n0q - n1q);
            st.branch_hits[0]++;
        end else if ((st.cnt > 0 && n1q > n0q) || (st.cnt < 0 && n0q > n1q)) begin
            q = {1'b1, qm[8], ~qm[7:0]};
            st.cnt = st.cnt + 2 * int'(qm[8]) + (n0q - n1q);
            st.branch_hits[1]++;
        end else begin
            q = {1'b0, qm[8], qm[7:0]};
            st.cnt = st.cnt - 2 * int'(!qm[8]) + (n1q - n0q);
            st.branch_hits[2]++;
        end
        return q;
    endfunction

    function automatic bit is_ctrl(input logic [9:0] w, output logic [1:0] c);
        for (int i = 0; i < 4; i++)
            if (w == CTRL_TOKEN[i]) begin
                c = 2'(i);
                return 1'b1;
            end
        c = 2'b00;
        return 1'b0;
    endfunction

    function automatic logic [7:0] decode_data(input logic [9:0] w);
        logic [7:0] q, d;
        q = w[9] ? ~w[7:0] : w[7:0];
        d[0] = q[0];
        for (int i = 1; i < 8; i++)
            d[i] = w[8] ? (q[i] ^ q[i-1]) : ~(q[i] ^ q[i-1]);
        return d;
    endfunction

endpackage
