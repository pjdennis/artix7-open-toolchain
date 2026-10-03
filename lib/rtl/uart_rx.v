// 8N1 UART receiver. `valid` pulses for one clock with the received byte on `data`.
// Start bits shorter than half a bit are ignored, as are frames with a low stop bit.
module uart_rx #(
  parameter CLKS_PER_BIT = 104  // 12 MHz / 115200 baud
) (
  input            clk,
  input            rx,
  output reg       valid = 1'b0,
  output reg [7:0] data = 8'h00
);
  reg [2:0] sync = 3'b111;  // 2-FF synchronizer + previous value for edge detection
  wire      s    = sync[1];
  reg       busy = 1'b0;
  reg [3:0] bit_idx = 0;    // 0 = start, 1..8 = data, 9 = stop
  reg [7:0] shift = 0;
  reg [$clog2(CLKS_PER_BIT)-1:0] count = 0;

  always @(posedge clk) begin
    sync  <= {sync[1:0], rx};
    valid <= 1'b0;
    if (!busy) begin
      if (sync[2] && !s) begin  // falling edge: candidate start bit, sample its middle
        busy    <= 1'b1;
        bit_idx <= 0;
        count   <= CLKS_PER_BIT / 2 - 1;
      end
    end else if (count != 0)
      count <= count - 1'b1;
    else begin
      count   <= CLKS_PER_BIT - 1;
      bit_idx <= bit_idx + 1'b1;
      case (bit_idx)
        0:       busy  <= !s;               // abort if the start bit was a glitch
        9: begin busy  <= 1'b0;
                 valid <= s;                // drop frames with a bad stop bit
                 if (s) data <= shift; end
        default: shift <= {s, shift[7:1]};
      endcase
    end
  end
endmodule
