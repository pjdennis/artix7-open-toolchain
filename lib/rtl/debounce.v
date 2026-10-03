// Synchronizes an asynchronous input (e.g. a push button) and accepts a new level only after it
// has been stable for CYCLES clocks. `rise`/`fall` pulse for one clock when `out` changes.
module debounce #(
  parameter CYCLES = 120000  // 10 ms at 12 MHz
) (
  input      clk,
  input      in,
  output reg out = 1'b0,
  output     rise,
  output     fall
);
  reg [1:0] sync = 2'b00;
  reg [$clog2(CYCLES)-1:0] count = 0;
  reg out_q = 1'b0;

  always @(posedge clk) begin
    sync  <= {sync[0], in};
    out_q <= out;
    if (sync[1] == out)
      count <= 0;
    else if (count == CYCLES - 1) begin
      out   <= sync[1];
      count <= 0;
    end else
      count <= count + 1'b1;
  end

  assign rise = out & ~out_q;
  assign fall = ~out & out_q;
endmodule
