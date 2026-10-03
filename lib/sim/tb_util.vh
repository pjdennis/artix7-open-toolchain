// Shared testbench helpers. Testbenches must end with `TB_PASS; mk/sim.mk requires the final
// log line to be exactly "PASS" so a testbench that stops early never counts as passing.
`ifndef TB_UTIL_VH
`define TB_UTIL_VH

`define CHECK(cond_, msg_) \
  if (!(cond_)) begin \
    $display("FAIL %s:%0d @%0t: %s", `__FILE__, `__LINE__, $time, msg_); \
    $fatal(1); \
  end

// (iverilog expands macro arguments inside string literals, hence the unusual parameter names)
`define CHECK_EQ(actual_, expected_, msg_) \
  if ((actual_) !== (expected_)) begin \
    $display("FAIL %s:%0d @%0t: %s: got %0h, expected %0h", `__FILE__, `__LINE__, $time, msg_, actual_, expected_); \
    $fatal(1); \
  end

`define TB_PASS begin $display("PASS"); $finish(0); end

// Free-running clock and a watchdog so a hung testbench fails instead of running forever.
`define TB_CLOCK(clk, half_period, timeout) \
  initial clk = 1'b0; \
  always #(half_period) clk = ~clk; \
  initial begin #(timeout); $display("FAIL: timeout"); $fatal(1); end

`endif
