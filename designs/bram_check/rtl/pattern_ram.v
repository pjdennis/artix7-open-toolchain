// 1024 x 32 RAM (one RAMB36) preloaded by the bitstream with pattern(BANK, addr).
module pattern_ram #(
  parameter BANK = 0
) (
  input             clk,
  input             we,
  input      [9:0]  waddr,
  input      [31:0] wdata,
  input      [9:0]  raddr,
  output reg [31:0] rdata
);
  `include "pattern.vh"

  reg [31:0] mem [0:1023];
  integer i;
  initial for (i = 0; i < 1024; i = i + 1) mem[i] = pattern(BANK, i);

  always @(posedge clk) begin
    if (we) mem[waddr] <= wdata;
    rdata <= mem[raddr];
  end
endmodule
