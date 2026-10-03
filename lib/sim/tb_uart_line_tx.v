`include "tb_util.vh"

module tb_uart_line_tx;
  localparam CPB = 6, LEN = 4;
  reg clk, start = 0;
  reg [8*LEN-1:0] line = "ABCD";
  wire busy, tx, rx_valid;
  wire [7:0] rx_data;
  reg [7:0] got [0:15];
  integer n = 0;

  uart_line_tx #(.CLKS_PER_BIT(CPB), .LEN(LEN)) dut (.clk(clk), .start(start), .line(line), .busy(busy), .tx(tx));
  uart_rx #(.CLKS_PER_BIT(CPB)) mon (.clk(clk), .rx(tx), .valid(rx_valid), .data(rx_data));
  `TB_CLOCK(clk, 5, 200000)

  always @(posedge clk) if (rx_valid) begin got[n] <= rx_data; n <= n + 1; end

  task pulse_start; begin start = 1; @(posedge clk); #1 start = 0; end endtask
  // Sampled on clock edges, as synchronous logic would (busy may glitch between delta cycles).
  task wait_idle; begin @(posedge clk); while (busy) @(posedge clk); end endtask

  initial begin
    repeat (3) @(posedge clk); #1;
    `CHECK_EQ(busy, 1'b0, "idle")
    `CHECK_EQ(tx, 1'b1, "line idle high")
    pulse_start;
    line = "WXYZ";  // the line is latched at start; later changes must not leak into it
    `CHECK_EQ(busy, 1'b1, "busy after start")
    pulse_start;    // ignored while busy
    wait_idle; repeat (2 * CPB) @(posedge clk);
    `CHECK_EQ(n, LEN, "one line, extra start ignored")
    `CHECK_EQ({got[0], got[1], got[2], got[3]}, "ABCD", "bytes sent MSB-first, latched at start")
    pulse_start;
    wait_idle; repeat (2 * CPB) @(posedge clk);
    `CHECK_EQ({got[4], got[5], got[6], got[7]}, "WXYZ", "second line")
    `TB_PASS
  end
endmodule
