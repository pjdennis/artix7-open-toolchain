`include "tb_util.vh"

module tb_top;
  localparam CLK_HZ = 1200, BAUD = 150, CPB = CLK_HZ / BAUD, BANKS = 3;
  localparam LINE_LEN = 30;

  reg clk;
  wire fpga_tx, host_ready, host_tx, rx_valid;
  wire [7:0] rx_data;
  reg host_valid = 0;
  reg [7:0] host_data = 0;

  top #(.CLK_HZ(CLK_HZ), .BAUD(BAUD), .BANKS(BANKS)) dut (
    .sysclk(clk), .btn(2'b00), .uart_txd_in(host_tx), .uart_rxd_out(fpga_tx),
    .led(), .led0_r(), .led0_g(), .led0_b());
  uart_tx #(.CLKS_PER_BIT(CPB)) host_uart_tx (.clk(clk), .valid(host_valid), .data(host_data), .ready(host_ready), .tx(host_tx));
  uart_rx #(.CLKS_PER_BIT(CPB)) host_uart_rx (.clk(clk), .rx(fpga_tx), .valid(rx_valid), .data(rx_data));

  `TB_CLOCK(clk, 5, 50000000)

  localparam BUF_LEN = 256;
  reg [7:0] rx_buf [0:BUF_LEN-1];
  integer wr = 0, rd = 0;
  always @(posedge clk) if (rx_valid) begin rx_buf[wr % BUF_LEN] <= rx_data; wr <= wr + 1; end

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
      `CHECK_EQ(rx_buf[rd % BUF_LEN], exp[8*(LINE_LEN-1-i) +: 8], "report byte")
      rd = rd + 1;
    end
  endtask

  task expect_quiet(input integer cycles);
    begin repeat (cycles) @(posedge clk); `CHECK_EQ(wr, rd, "no unexpected serial output") end
  endtask

  function [8*LINE_LEN-1:0] report(input [15:0] errs, input [3:0] bank, input [11:0] addr);
    report = {"BRAM N=03 ERR=", hex4(errs), " AT=0", hex1(bank), ":", hex1(addr[11:8]), hex1(addr[7:4]),
              hex1(addr[3:0]), 8'h0D, 8'h0A};
  endfunction
  function [7:0] hex1(input [3:0] n); hex1 = n < 10 ? "0" + n : "A" + n - 10; endfunction
  function [31:0] hex4(input [15:0] n); hex4 = {hex1(n[15:12]), hex1(n[11:8]), hex1(n[7:4]), hex1(n[3:0])}; endfunction

  // Flips one word through the hierarchy, checks the scan reports exactly it, then restores it.
  task corrupt_and_check(input integer bank, input integer addr);
    reg [31:0] saved;
    begin
      case (bank)
        0: begin saved = dut.g_bank[0].ram.mem[addr]; dut.g_bank[0].ram.mem[addr] = ~saved; end
        1: begin saved = dut.g_bank[1].ram.mem[addr]; dut.g_bank[1].ram.mem[addr] = ~saved; end
        2: begin saved = dut.g_bank[2].ram.mem[addr]; dut.g_bank[2].ram.mem[addr] = ~saved; end
      endcase
      host_send("?");
      expect_line(report(1, bank, addr));
      case (bank)
        0: dut.g_bank[0].ram.mem[addr] = saved;
        1: dut.g_bank[1].ram.mem[addr] = saved;
        2: dut.g_bank[2].ram.mem[addr] = saved;
      endcase
    end
  endtask

  initial begin
    expect_quiet(20 * CPB);

    host_send("?");
    expect_line({"BRAM N=03 ERR=0000 AT=00:000", 8'h0D, 8'h0A});

    // Scan coverage: corrupting the first or last word of any bank is reported at exactly that spot.
    corrupt_and_check(0, 0);    corrupt_and_check(0, 1023);
    corrupt_and_check(1, 0);    corrupt_and_check(1, 1023);
    corrupt_and_check(2, 0);    corrupt_and_check(2, 1023);

    host_send("y");  // corrupt the last word of the last bank: the scan must reach it
    expect_quiet(20 * CPB);
    host_send("?");
    expect_line({"BRAM N=03 ERR=0001 AT=02:3FF", 8'h0D, 8'h0A});

    host_send("x");  // corrupt bank 0, word 5: reported as the first error
    host_send("?");
    expect_line({"BRAM N=03 ERR=0002 AT=00:005", 8'h0D, 8'h0A});
    expect_quiet(30 * CPB);
    `TB_PASS
  end
endmodule
