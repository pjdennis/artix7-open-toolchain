`include "tb_util.vh"

module tb_debounce;
  localparam CYCLES = 8;
  reg clk, in = 0;
  wire out, rise, fall;
  integer rises = 0, falls = 0;

  debounce #(.CYCLES(CYCLES)) dut (.clk(clk), .in(in), .out(out), .rise(rise), .fall(fall));
  `TB_CLOCK(clk, 5, 100000)

  always @(posedge clk) begin
    rises <= rises + rise;
    falls <= falls + fall;
    `CHECK(!(rise && fall), "rise and fall together")
    `CHECK(!rise || out, "rise pulse while out low")
    `CHECK(!fall || !out, "fall pulse while out high")
  end

  task hold(input v, input integer n);
    begin in = v; repeat (n) @(posedge clk); #1; end
  endtask

  task bounce(input integer n);
    integer i;
    for (i = 0; i < n; i = i + 1) hold(i[0], 1 + (i % 3));
  endtask

  initial begin
    hold(0, 20);
    `CHECK_EQ(out, 1'b0, "starts low")

    hold(1, CYCLES - 2);  // glitch shorter than the debounce window
    hold(0, 3 * CYCLES);
    `CHECK_EQ(out, 1'b0, "short glitch rejected")
    `CHECK_EQ(rises, 0, "no rise on glitch")

    bounce(12);
    hold(1, CYCLES + 4);  // synchronizer latency + debounce window
    `CHECK_EQ(out, 1'b1, "stable high accepted")
    `CHECK_EQ(rises, 1, "exactly one rise despite bounce")

    bounce(12);
    hold(0, CYCLES + 4);
    `CHECK_EQ(out, 1'b0, "release accepted")
    `CHECK_EQ(falls, 1, "exactly one fall despite bounce")
    `CHECK_EQ(rises, 1, "no extra rise during release bounce")
    `TB_PASS
  end
endmodule
