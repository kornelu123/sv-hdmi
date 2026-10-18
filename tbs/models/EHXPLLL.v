// Simulation-only behavioural model of the Lattice ECP5 EHXPLLL primitive
// (yosys ships only a blackbox for it).
//
// Supported subset: CLKOP and CLKOS outputs with FEEDBK_PATH = "CLKOP".
//   f_CLKOP = f_CLKI * CLKFB_DIV / CLKI_DIV,  f_VCO = f_CLKOP * CLKOP_DIV
//   f_CLKOS = f_VCO / CLKOS_DIV  (only when CLKOS_ENABLE = "ENABLED")
// The model measures the CLKI period, enforces the ECP5 datasheet ranges
// (PFD 3.125-400 MHz, VCO 400-800 MHz, output 3.125-400 MHz on CLKOP and
// CLKOS) with $fatal, and emits CLKOP with its rising edges aligned to every
// CLKI_DIV-th CLKI rising edge. CLKOS is emitted as a 50% duty clock whose
// edge pattern restarts every CLKOS_HYPER PFD periods (the shortest whole
// number of PFD periods holding a whole number of CLKOS cycles), so its rising
// edges sit on whole multiples of CLKOS_DIV VCO cycles from a CLKOP rising
// edge; with CLKOS_DIV a multiple of CLKOP_DIV every CLKOS rising edge
// coincides with a CLKOP rising edge. CPHASE/FPHASE are ignored (0 degrees,
// as ecppll generates them). CLKOP and CLKOS both start toggling with the
// second CLKI rising edge (before LOCK); LOCK rises after LOCK_CYCLES
// reference cycles. All other outputs stay low (CLKOS too when disabled).
`timescale 1ps / 1ps
module EHXPLLL #(
    parameter CLKI_DIV = 1,
    parameter CLKFB_DIV = 1,
    parameter CLKOP_DIV = 8,
    parameter CLKOS_DIV = 8,
    parameter CLKOS2_DIV = 8,
    parameter CLKOS3_DIV = 8,
    parameter CLKOP_ENABLE = "ENABLED",
    parameter CLKOS_ENABLE = "DISABLED",
    parameter CLKOS2_ENABLE = "DISABLED",
    parameter CLKOS3_ENABLE = "DISABLED",
    parameter CLKOP_CPHASE = 0,
    parameter CLKOS_CPHASE = 0,
    parameter CLKOS2_CPHASE = 0,
    parameter CLKOS3_CPHASE = 0,
    parameter CLKOP_FPHASE = 0,
    parameter CLKOS_FPHASE = 0,
    parameter CLKOS2_FPHASE = 0,
    parameter CLKOS3_FPHASE = 0,
    parameter FEEDBK_PATH = "CLKOP",
    parameter CLKOP_TRIM_POL = "RISING",
    parameter CLKOP_TRIM_DELAY = 0,
    parameter CLKOS_TRIM_POL = "RISING",
    parameter CLKOS_TRIM_DELAY = 0,
    parameter OUTDIVIDER_MUXA = "DIVA",
    parameter OUTDIVIDER_MUXB = "DIVB",
    parameter OUTDIVIDER_MUXC = "DIVC",
    parameter OUTDIVIDER_MUXD = "DIVD",
    parameter PLL_LOCK_MODE = 0,
    parameter PLL_LOCK_DELAY = 200,
    parameter STDBY_ENABLE = "DISABLED",
    parameter REFIN_RESET = "DISABLED",
    parameter SYNC_ENABLE = "DISABLED",
    parameter INT_LOCK_STICKY = "ENABLED",
    parameter DPHASE_SOURCE = "DISABLED",
    parameter PLLRST_ENA = "DISABLED",
    parameter INTFB_WAKE = "DISABLED",
    parameter LOCK_CYCLES = 16
) (
    input  wire CLKI,
    input  wire CLKFB,
    input  wire PHASESEL1,
    input  wire PHASESEL0,
    input  wire PHASEDIR,
    input  wire PHASESTEP,
    input  wire PHASELOADREG,
    input  wire STDBY,
    input  wire PLLWAKESYNC,
    input  wire RST,
    input  wire ENCLKOP,
    input  wire ENCLKOS,
    input  wire ENCLKOS2,
    input  wire ENCLKOS3,
    output wire CLKOP,
    output wire CLKOS,
    output wire CLKOS2,
    output wire CLKOS3,
    output wire LOCK,
    output wire INTLOCK,
    output wire REFCLK,
    output wire CLKINTFB
);
    function automatic int gcd(input int a, input int b);
        int t;
        while (b != 0) begin
            t = a % b;
            a = b;
            b = t;
        end
        return a;
    endfunction

    localparam bit CLKOS_EN    = CLKOS_ENABLE == "ENABLED";
    // VCO cycles per PFD period.
    localparam int VCO_PER_PFD = CLKFB_DIV * CLKOP_DIV;
    // PFD periods per CLKOS burst, and CLKOS cycles in one burst.
    localparam int CLKOS_HYPER = CLKOS_EN ? CLKOS_DIV / gcd(VCO_PER_PFD, CLKOS_DIV) : 1;
    localparam int CLKOS_BURST = CLKOS_EN ? VCO_PER_PFD * CLKOS_HYPER / CLKOS_DIV : 0;

    reg clkop_r = 1'b0;
    reg clkos_r = 1'b0;
    reg lock_r  = 1'b0;

    assign CLKOP    = clkop_r;
    assign LOCK     = lock_r;
    assign CLKOS    = clkos_r;
    assign CLKOS2   = 1'b0;
    assign CLKOS3   = 1'b0;
    assign INTLOCK  = lock_r;
    assign REFCLK   = CLKI;
    assign CLKINTFB = 1'b0;

    initial begin
        if (FEEDBK_PATH != "CLKOP")
            $fatal(1, "EHXPLLL model: only FEEDBK_PATH=\"CLKOP\" is supported");
        if (CLKOP_ENABLE != "ENABLED")
            $fatal(1, "EHXPLLL model: CLKOP must be enabled");
        if (CLKI_DIV < 1 || CLKFB_DIV < 1 || CLKOP_DIV < 1)
            $fatal(1, "EHXPLLL model: dividers must be >= 1");
        if (CLKOS_EN && CLKOS_DIV < 1)
            $fatal(1, "EHXPLLL model: CLKOS_DIV must be >= 1");
    end

    longint unsigned t_prev    = 0;
    longint unsigned in_period = 0;   // ps
    longint unsigned out_period;      // ps
    longint unsigned os_period;       // ps
    int unsigned     n_pfd     = 0;
    int unsigned     n_in      = 0;

    task automatic check_ranges(input longint unsigned in_ps, input longint unsigned out_ps);
        longint unsigned pfd_ps, vco_ps, os_ps;
        pfd_ps = in_ps * CLKI_DIV;
        vco_ps = out_ps / CLKOP_DIV;
        // 3.125 MHz = 320000 ps, 400 MHz = 2500 ps, 800 MHz = 1250 ps
        if (pfd_ps > 320000 || pfd_ps < 2500)
            $fatal(1, "EHXPLLL model: PFD frequency out of range (period %0d ps)", pfd_ps);
        if (vco_ps > 2500 || vco_ps < 1250)
            $fatal(1, "EHXPLLL model: VCO frequency out of range (period %0d ps)", vco_ps);
        if (out_ps > 320000 || out_ps < 2500)
            $fatal(1, "EHXPLLL model: CLKOP frequency out of range (period %0d ps)", out_ps);
        if ((in_ps * CLKI_DIV) % (2 * CLKFB_DIV) != 0)
            $fatal(1, "EHXPLLL model: CLKOP period not representable in 1 ps steps");
        if (CLKOS_EN) begin
            if ((pfd_ps * CLKOS_DIV) % (2 * VCO_PER_PFD) != 0)
                $fatal(1, "EHXPLLL model: CLKOS period not representable in 1 ps steps");
            os_ps = pfd_ps * CLKOS_DIV / VCO_PER_PFD;
            if (os_ps > 320000 || os_ps < 2500)
                $fatal(1, "EHXPLLL model: CLKOS frequency out of range (period %0d ps)", os_ps);
        end
    endtask

    task automatic emit_burst(input longint unsigned period_ps);
        for (int k = 0; k < CLKFB_DIV; k++) begin
            clkop_r = 1'b1;
            #(period_ps / 2);
            clkop_r = 1'b0;
            #(period_ps / 2);
        end
    endtask

    task automatic emit_clkos_burst(input longint unsigned period_ps);
        for (int k = 0; k < CLKOS_BURST; k++) begin
            clkos_r = 1'b1;
            #(period_ps / 2);
            clkos_r = 1'b0;
            #(period_ps / 2);
        end
    endtask

    always @(posedge CLKI) begin
        if (n_in > 0)
            in_period = $time - t_prev;
        t_prev = $time;
        n_in++;
        // Start a CLKOP burst on every CLKI_DIV-th reference edge once the
        // reference period is known, and a CLKOS burst on every CLKOS_HYPER-th
        // CLKOP burst.
        if (n_in >= 2 && (n_in - 2) % CLKI_DIV == 0) begin
            out_period = in_period * CLKI_DIV / CLKFB_DIV;
            check_ranges(in_period, out_period);
            fork
                emit_burst(out_period);
            join_none
            if (CLKOS_EN && n_pfd % CLKOS_HYPER == 0) begin
                os_period = in_period * CLKI_DIV * CLKOS_DIV / VCO_PER_PFD;
                fork
                    emit_clkos_burst(os_period);
                join_none
            end
            n_pfd++;
        end
        if (n_in == LOCK_CYCLES)
            lock_r = 1'b1;
    end
endmodule
