// Block RAM initialisation check. BANKS RAMs are preloaded by the bitstream (see pattern.vh).
//   '?'  scan every word of every bank against the expected pattern, then report
//        "BRAM N=<banks> ERR=<count> AT=<bank>:<addr>\r\n" (hex; AT = first mismatch)
//   'x'  corrupt bank 0, word 5          'y'  corrupt the last bank's last word
// LD1 lights once a scan has found no errors; LD2 lights if one found errors.
module top #(
  parameter CLK_HZ = 12_000_000,
  parameter BAUD   = 115_200,
  parameter BANKS  = 32
) (
  input        sysclk,
  input  [1:0] btn,
  input        uart_txd_in,
  output       uart_rxd_out,
  output [1:0] led,
  output       led0_r,
  output       led0_g,
  output       led0_b
);
  `include "pattern.vh"
  localparam CLKS_PER_BIT = (CLK_HZ + BAUD / 2) / BAUD;
  localparam LINE_LEN     = 30;
  localparam [5:0] LAST   = BANKS - 1;

  assign {led0_r, led0_g, led0_b} = 3'b111;

  wire       rx_valid;
  wire [7:0] rx_data;
  uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (.clk(sysclk), .rx(uart_txd_in), .valid(rx_valid), .data(rx_data));
  wire cmd_scan = rx_valid && rx_data == "?";
  wire cmd_x    = rx_valid && rx_data == "x";
  wire cmd_y    = rx_valid && rx_data == "y";

  // Scan: one word per clock; read data arrives a cycle later, tracked by the *_q registers.
  reg        scanning = 1'b0, check = 1'b0, report = 1'b0;
  reg [5:0]  bank = 0, bank_q = 0;
  reg [9:0]  addr = 0, addr_q = 0;
  reg [15:0] errors = 0;
  reg [5:0]  err_bank = 0;
  reg [9:0]  err_addr = 0;
  reg        passed = 1'b0, failed = 1'b0;

  wire [31:0] rdata [0:BANKS-1];
  genvar b;
  generate for (b = 0; b < BANKS; b = b + 1) begin : g_bank
    pattern_ram #(.BANK(b)) ram (
      .clk(sysclk),
      .we((cmd_x && b == 0) || (cmd_y && b == BANKS - 1)),
      .waddr(cmd_x ? 10'd5 : 10'd1023),
      .wdata(~pattern(b, cmd_x ? 10'd5 : 10'd1023)),
      .raddr(addr), .rdata(rdata[b]));
  end endgenerate

  always @(posedge sysclk) begin
    report <= 1'b0;
    check  <= scanning;
    bank_q <= bank;
    addr_q <= addr;
    if (cmd_scan && !scanning) begin
      scanning <= 1'b1;
      {bank, addr} <= 0;
      errors   <= 0;
    end else if (scanning) begin
      addr <= addr + 1'b1;
      if (addr == 10'd1023) begin
        bank <= bank + 1'b1;
        if (bank == LAST) scanning <= 1'b0;
      end
    end
    if (check) begin
      if (rdata[bank_q] == pattern(bank_q, addr_q)) ;
      else begin  // written this way round so an unknown (X) word counts as an error in simulation
        if (errors == 0) {err_bank, err_addr} <= {bank_q, addr_q};
        if (errors != 16'hFFFF) errors <= errors + 1'b1;
      end
      if (!scanning) report <= 1'b1;  // that was the last word
    end
    if (report) {passed, failed} <= {errors == 0, errors != 0};
  end
  assign led = {failed, passed};

  function [7:0] hex(input [3:0] n);
    hex = n < 10 ? "0" + n : "A" + n - 10;
  endfunction

  wire [5:0] n_banks = BANKS;
  wire [9:0] at_addr = errors == 0 ? 10'd0 : err_addr;
  wire [5:0] at_bank = errors == 0 ? 6'd0 : err_bank;
  uart_line_tx #(.CLKS_PER_BIT(CLKS_PER_BIT), .LEN(LINE_LEN)) u_line (
    .clk(sysclk), .start(report), .busy(), .tx(uart_rxd_out),
    .line({"BRAM N=", hex(n_banks[5:4]), hex(n_banks[3:0]),
           " ERR=", hex(errors[15:12]), hex(errors[11:8]), hex(errors[7:4]), hex(errors[3:0]),
           " AT=", hex(at_bank[5:4]), hex(at_bank[3:0]), ":",
           hex(at_addr[9:8]), hex(at_addr[7:4]), hex(at_addr[3:0]), 8'h0D, 8'h0A}));
endmodule
