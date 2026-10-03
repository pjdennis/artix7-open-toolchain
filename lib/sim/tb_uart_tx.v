`include "tb_util.vh"

module tb_uart_tx;
  localparam CPB = 6;  // clocks per bit
  reg clk, valid = 0;
  reg [7:0] data = 0;
  wire ready, tx;

  uart_tx #(.CLKS_PER_BIT(CPB)) dut (.clk(clk), .valid(valid), .data(data), .ready(ready), .tx(tx));
  `TB_CLOCK(clk, 5, 100000)

  // Decode one frame from tx, sampling mid-bit, and compare to `exp`.
  task expect_frame(input [7:0] exp);
    integer i;
    reg [7:0] got;
    begin
      wait (tx === 1'b0);                              // start bit edge
      repeat (CPB / 2) @(posedge clk); #1;
      `CHECK_EQ(tx, 1'b0, "start bit")
      for (i = 0; i < 8; i = i + 1) begin
        repeat (CPB) @(posedge clk); #1;
        got[i] = tx;
      end
      repeat (CPB) @(posedge clk); #1;
      `CHECK_EQ(tx, 1'b1, "stop bit")
      `CHECK_EQ(got, exp, "data bits, LSB first")
    end
  endtask

  // Present a byte and wait for the handshake.
  task send(input [7:0] b);
    begin
      data = b; valid = 1;
      @(posedge clk); while (!ready) @(posedge clk);
      #1 valid = 0;
    end
  endtask

  initial begin
    repeat (5) @(posedge clk); #1;
    `CHECK_EQ(tx, 1'b1, "idle high")
    `CHECK_EQ(ready, 1'b1, "idle ready")
    fork
      begin send(8'hA5); send(8'h3C); end
      begin expect_frame(8'hA5); expect_frame(8'h3C); end
    join
    repeat (2 * CPB) @(posedge clk); #1;
    `CHECK_EQ(tx, 1'b1, "idle high after frames")
    `CHECK_EQ(ready, 1'b1, "ready after frames")
    `TB_PASS
  end

  always @(posedge clk) if (!ready) `CHECK(tx !== 1'bx, "tx unknown while busy")
endmodule
