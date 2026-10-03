// Cmod A7-35T demo:
//   LD1      heartbeat, toggles every BLINK_HALF clocks (1 Hz blink)
//   LD2      lit while BTN0 is held
//   RGB LED  each BTN1 press cycles off -> red -> green -> blue -> white (1/16 PWM duty)
//   UART     sends "CMODA7 OK B0=b B1=b C=c\r\n" on any button edge or when '?' is received
module top #(
  parameter CLK_HZ          = 12_000_000,
  parameter BAUD            = 115_200,
  parameter DEBOUNCE_CYCLES = CLK_HZ / 100,  // 10 ms
  parameter BLINK_HALF      = CLK_HZ / 2
) (
  input        sysclk,
  input  [1:0] btn,
  input        uart_txd_in,   // host -> FPGA
  output       uart_rxd_out,  // FPGA -> host
  output [1:0] led,
  output       led0_r,        // RGB LED, active low
  output       led0_g,
  output       led0_b
);
  localparam CLKS_PER_BIT = (CLK_HZ + BAUD / 2) / BAUD;
  localparam LINE_LEN     = 25;
  localparam [2:0] NUM_COLORS = 5;

  // Heartbeat
  reg [$clog2(BLINK_HALF)-1:0] blink_count = 0;
  reg heartbeat = 1'b0;
  always @(posedge sysclk)
    if (blink_count == BLINK_HALF - 1) begin
      blink_count <= 0;
      heartbeat   <= ~heartbeat;
    end else
      blink_count <= blink_count + 1'b1;

  // Buttons
  wire [1:0] pressed, press_edge, release_edge;
  genvar i;
  generate for (i = 0; i < 2; i = i + 1) begin : g_btn
    debounce #(.CYCLES(DEBOUNCE_CYCLES)) db (
      .clk(sysclk), .in(btn[i]), .out(pressed[i]), .rise(press_edge[i]), .fall(release_edge[i]));
  end endgenerate

  assign led = {pressed[0], heartbeat};

  // RGB colour selection and dimming
  reg [2:0] color = 0;
  reg [3:0] pwm   = 0;
  always @(posedge sysclk) begin
    pwm <= pwm + 1'b1;
    if (press_edge[1]) color <= (color == NUM_COLORS - 1) ? 3'd0 : color + 1'b1;
  end
  wire lit = (pwm == 0);
  assign led0_r = ~(lit && (color == 1 || color == 4));
  assign led0_g = ~(lit && (color == 2 || color == 4));
  assign led0_b = ~(lit && (color == 3 || color == 4));

  // UART status reporting. The line is latched when sending starts; an event that arrives on
  // that same cycle (e.g. a BTN1 press, before the new colour is visible) queues another line.
  wire       rx_valid, line_busy;
  wire [7:0] rx_data;
  uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (.clk(sysclk), .rx(uart_txd_in), .valid(rx_valid), .data(rx_data));

  wire report = (rx_valid && rx_data == "?") || |press_edge || |release_edge;
  reg  pending = 1'b0;
  always @(posedge sysclk)
    if (!line_busy && pending) pending <= report;
    else if (report)           pending <= 1'b1;

  uart_line_tx #(.CLKS_PER_BIT(CLKS_PER_BIT), .LEN(LINE_LEN)) u_line (
    .clk(sysclk), .start(pending), .busy(line_busy), .tx(uart_rxd_out),
    .line({"CMODA7 OK B0=", "0" + pressed[0], " B1=", "0" + pressed[1], " C=", "0" + color, 8'h0D, 8'h0A}));
endmodule
