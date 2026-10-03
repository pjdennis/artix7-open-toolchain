// Sends a fixed-length line (LEN bytes, first character in the top byte) over an 8N1 UART.
// `line` is latched on `start` while idle; `start` is ignored while busy (until the last stop bit).
module uart_line_tx #(
  parameter CLKS_PER_BIT = 104,
  parameter LEN          = 16
) (
  input                clk,
  input                start,
  input  [8*LEN-1:0]   line,
  output               busy,
  output               tx
);
  reg [8*LEN-1:0] latched = 0;
  reg [$clog2(LEN+1)-1:0] idx = 0;
  reg  sending = 1'b0;
  wire tx_ready;

  assign busy = sending || !tx_ready;

  uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
    .clk(clk), .valid(sending), .data(latched[8*(LEN-1-idx) +: 8]), .ready(tx_ready), .tx(tx));

  always @(posedge clk)
    if (!busy) begin
      if (start) begin
        latched <= line;
        idx     <= 0;
        sending <= 1'b1;
      end
    end else if (tx_ready) begin
      idx <= idx + 1'b1;
      if (idx == LEN - 1) sending <= 1'b0;
    end
endmodule
