`include "tb_util.vh"

module tb_top;
  // Scaled-down timing: 8 clocks per UART bit, 4-clock debounce, 50-clock blink half period.
  localparam CLK_HZ = 1200, BAUD = 150, DEBOUNCE = 4, BLINK_HALF = 50, CPB = CLK_HZ / BAUD;
  localparam LINE_LEN = 25;

  reg clk;
  reg [1:0] btn = 2'b00;
  wire [1:0] led;
  wire led0_r, led0_g, led0_b, fpga_tx;
  reg  host_valid = 0;
  reg  [7:0] host_data = 0;
  wire host_ready, host_tx, rx_valid;
  wire [7:0] rx_data;

  top #(.CLK_HZ(CLK_HZ), .BAUD(BAUD), .DEBOUNCE_CYCLES(DEBOUNCE), .BLINK_HALF(BLINK_HALF)) dut (
    .sysclk(clk), .btn(btn), .led(led), .led0_r(led0_r), .led0_g(led0_g), .led0_b(led0_b),
    .uart_txd_in(host_tx), .uart_rxd_out(fpga_tx));

  // Host side of the serial link, built from the (separately tested) library UART.
  uart_tx #(.CLKS_PER_BIT(CPB)) host_uart_tx (.clk(clk), .valid(host_valid), .data(host_data), .ready(host_ready), .tx(host_tx));
  uart_rx #(.CLKS_PER_BIT(CPB)) host_uart_rx (.clk(clk), .rx(fpga_tx), .valid(rx_valid), .data(rx_data));

  `TB_CLOCK(clk, 5, 50000000)

  localparam BUF_LEN = 1024;
  reg [7:0] rx_buf [0:BUF_LEN-1];
  integer wr = 0, rd = 0;
  always @(posedge clk) if (rx_valid) begin rx_buf[wr % BUF_LEN] <= rx_data; wr <= wr + 1; end

  function [8*LINE_LEN-1:0] status(input b0, input b1, input [2:0] c);
    status = {"CMODA7 OK B0=", "0" + b0, " B1=", "0" + b1, " C=", "0" + c, 8'h0D, 8'h0A};
  endfunction

  task host_send(input [7:0] b);
    begin
      host_data = b; host_valid = 1;
      @(posedge clk); while (!host_ready) @(posedge clk);
      #1 host_valid = 0;
    end
  endtask

  task expect_line(input [8*LINE_LEN-1:0] exp);
    integer i;
    for (i = 0; i < LINE_LEN; i = i + 1) begin
      wait (wr > rd);
      `CHECK_EQ(rx_buf[rd % BUF_LEN], exp[8*(LINE_LEN-1-i) +: 8], "status line byte")
      rd = rd + 1;
    end
  endtask

  task expect_quiet(input integer cycles);
    begin repeat (cycles) @(posedge clk); `CHECK_EQ(wr, rd, "no unexpected serial output") end
  endtask

  task press(input integer i, input v);
    begin btn[i] = v; repeat (DEBOUNCE + 4) @(posedge clk); #1; end
  endtask

  // Counts cycles each RGB channel is lit (active low) over one 16-cycle PWM period.
  task expect_rgb(input r, input g, input b);
    integer n, nr, ng, nb;
    begin
      nr = 0; ng = 0; nb = 0;
      for (n = 0; n < 16; n = n + 1) begin
        @(posedge clk); #1;
        nr = nr + !led0_r; ng = ng + !led0_g; nb = nb + !led0_b;
      end
      `CHECK_EQ(nr, r ? 1 : 0, "red PWM duty")
      `CHECK_EQ(ng, g ? 1 : 0, "green PWM duty")
      `CHECK_EQ(nb, b ? 1 : 0, "blue PWM duty")
    end
  endtask

  // Waits for the link to go quiet, then checks the most recent line and discards the rest.
  task expect_last_line(input [8*LINE_LEN-1:0] exp);
    integer last;
    begin
      last = -1;
      while (wr != last) begin last = wr; repeat (30 * CPB) @(posedge clk); end
      `CHECK(wr - rd >= LINE_LEN, "at least one line")
      rd = wr - LINE_LEN;
      expect_line(exp);
    end
  endtask

  integer t0, k, off, color;
  initial begin
    // Heartbeat: LD1 toggles every BLINK_HALF cycles.
    @(led[0]); t0 = $time;
    @(led[0]);
    `CHECK_EQ(($time - t0) / 10, BLINK_HALF, "heartbeat half period")

    // Idle: RGB off, LD2 off, no serial chatter.
    expect_rgb(0, 0, 0);
    `CHECK_EQ(led[1], 1'b0, "LD2 off at idle")
    expect_quiet(20 * CPB);

    // '?' requests a status line; other characters are ignored.
    host_send("?");
    expect_line(status(0, 0, 0));
    host_send("x");
    expect_quiet(30 * CPB);

    // BTN0 drives LD2 and reports both edges.
    press(0, 1);
    `CHECK_EQ(led[1], 1'b1, "LD2 follows BTN0 press")
    expect_line(status(1, 0, 0));
    press(0, 0);
    `CHECK_EQ(led[1], 1'b0, "LD2 follows BTN0 release")
    expect_line(status(0, 0, 0));

    // BTN1 cycles the RGB LED: red, green, blue, white, off.
    press(1, 1); expect_line(status(0, 1, 1)); expect_rgb(1, 0, 0);
    press(1, 0); expect_line(status(0, 0, 1)); expect_rgb(1, 0, 0);
    for (k = 2; k <= 5; k = k + 1) begin
      press(1, 1); expect_line(status(0, 1, k % 5));
      press(1, 0); expect_line(status(0, 0, k % 5));
      case (k % 5)
        2: expect_rgb(0, 1, 0);
        3: expect_rgb(0, 0, 1);
        4: expect_rgb(1, 1, 1);
        0: expect_rgb(0, 0, 0);
      endcase
    end

    // An event during transmission is queued: first line is the snapshot, second the new state.
    press(0, 1);
    press(1, 1);
    expect_line(status(1, 0, 0));
    expect_line(status(1, 1, 1));
    expect_quiet(30 * CPB);

    // No lost updates: wherever a BTN1 edge lands relative to a '?' query (including the cycle
    // a line starts, before the new colour is visible), the last line reports the final state.
    press(0, 0); press(1, 0);
    expect_last_line(status(0, 0, 1));
    color = 1;
    for (off = 0; off < 12 * CPB; off = off + 1) begin
      fork
        host_send("?");
        begin repeat (off) @(posedge clk); btn[1] = 1; end
      join
      color = (color + 1) % 5;
      expect_last_line(status(0, 1, color));
      press(1, 0);
      expect_last_line(status(0, 0, color));
    end
    `TB_PASS
  end
endmodule
