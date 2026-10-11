`ifndef TB_CHECK_SVH
`define TB_CHECK_SVH
// Counts a check (the enclosing scope declares `int checks`) and stops the
// simulation with a non-zero exit status on the first failure.
// Usage: `CHECK(a == b, ("a=%0d b=%0d", a, b))
`define CHECK(cond, msg) \
    begin checks++; if (!(cond)) $fatal(1, $sformatf msg); end

// Optional waveform dump, enabled with the +waves plusarg (make WAVES=1).
`define DUMP_WAVES(top) \
    initial if ($test$plusargs("waves")) begin \
        $dumpfile({"build/", `"top`", ".vcd"}); \
        $dumpvars(0, top); \
    end
`endif
