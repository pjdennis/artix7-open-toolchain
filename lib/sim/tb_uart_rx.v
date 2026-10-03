`include "tb_util.vh"

module tb_uart_rx;
  localparam CPB = 8;  // clocks per bit
  reg clk, rx = 1;
  wire valid;
  wire [7:0] data;
  integer count = 0;
  reg [7:0] last = 0;

  uart_rx #(.CLKS_PER_BIT(CPB)) dut (.clk(clk), .rx(rx), .valid(valid), .data(data));
  `TB_CLOCK(clk, 5, 100000)

  always @(posedge clk) if (valid) begin count <= count + 1; last <= data; end

  task bit_out(input b); begin rx = b; repeat (CPB) @(posedge clk); end endtask

  task frame(input [7:0] b, input stop);
    integer i;
    begin
      bit_out(0);
      for (i = 0; i < 8; i = i + 1) bit_out(b[i]);
      bit_out(stop);
      rx = 1;
    end
  endtask

  initial begin
    repeat (10) @(posedge clk);
    frame(8'h5A, 1); frame(8'hC3, 1);
    repeat (2 * CPB) @(posedge clk);
    `CHECK_EQ(count, 2, "two bytes received")
    `CHECK_EQ(last, 8'hC3, "second byte data")

    rx = 0; repeat (CPB / 4) @(posedge clk); rx = 1;  // glitch: not a real start bit
    repeat (12 * CPB) @(posedge clk);
    `CHECK_EQ(count, 2, "glitch ignored")

    frame(8'hFF, 0);  // framing error: stop bit low
    repeat (2 * CPB) @(posedge clk);
    `CHECK_EQ(count, 2, "framing error dropped")

    frame(8'h01, 1);
    repeat (2 * CPB) @(posedge clk);
    `CHECK_EQ(count, 3, "recovers after framing error")
    `CHECK_EQ(last, 8'h01, "byte after framing error")
    `TB_PASS
  end
endmodule
