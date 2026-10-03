// 8N1 UART transmitter. A byte is accepted on a clock where `valid && ready`.
module uart_tx #(
  parameter CLKS_PER_BIT = 104  // 12 MHz / 115200 baud
) (
  input        clk,
  input        valid,
  input  [7:0] data,
  output       ready,
  output       tx
);
  reg [9:0] shift = 10'h3FF;  // {stop, data[7:0], start}, shifted out LSB first
  reg [3:0] bits_left = 0;
  reg [$clog2(CLKS_PER_BIT)-1:0] count = 0;

  assign ready = (bits_left == 0);
  assign tx    = shift[0];

  always @(posedge clk) begin
    if (ready) begin
      if (valid) begin
        shift     <= {1'b1, data, 1'b0};
        bits_left <= 10;
        count     <= 0;
      end
    end else if (count == CLKS_PER_BIT - 1) begin
      shift     <= {1'b1, shift[9:1]};
      bits_left <= bits_left - 1'b1;
      count     <= 0;
    end else
      count <= count + 1'b1;
  end
endmodule
