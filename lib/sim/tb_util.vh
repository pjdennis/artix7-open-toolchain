// Shared testbench helpers. Testbenches must end with `TB_PASS; mk/sim.mk requires the final
// log line to be exactly "PASS" so a testbench that stops early never counts as passing.
`ifndef TB_UTIL_VH
`define TB_UTIL_VH

`define CHECK(cond, msg) \
  if (!(cond)) begin \
    $display("FAIL %s:%0d @%0t: %s", `__FILE__, `__LINE__, $time, msg); \
    $fatal(1); \
  end

`define CHECK_EQ(got, exp, msg) \
  if ((got) !== (exp)) begin \
    $display("FAIL %s:%0d @%0t: %s: got %0h, expected %0h", `__FILE__, `__LINE__, $time, msg, got, exp); \
    $fatal(1); \
  end

`define TB_PASS begin $display("PASS"); $finish(0); end

// Free-running clock and a watchdog so a hung testbench fails instead of running forever.
`define TB_CLOCK(clk, half_period, timeout) \
  initial clk = 1'b0; \
  always #(half_period) clk = ~clk; \
  initial begin #(timeout); $display("FAIL: timeout"); $fatal(1); end

`endif
