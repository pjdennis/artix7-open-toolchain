# Cmod A7-35T pins, from Digilent's Cmod-A7-Master.xdc.
# nextpnr-xilinx's XDC parser crashes on Vivado-style "[get_ports { name }]": no spaces inside braces.

# 12 MHz clock (period enforced via nextpnr --freq; see boards/cmod_a7_35t.mk)
set_property -dict { PACKAGE_PIN L17 IOSTANDARD LVCMOS33 } [get_ports {sysclk}]

# LEDs (active high)
set_property -dict { PACKAGE_PIN A17 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN C16 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]

# RGB LED (active low)
set_property -dict { PACKAGE_PIN B17 IOSTANDARD LVCMOS33 } [get_ports {led0_b}]
set_property -dict { PACKAGE_PIN B16 IOSTANDARD LVCMOS33 } [get_ports {led0_g}]
set_property -dict { PACKAGE_PIN C17 IOSTANDARD LVCMOS33 } [get_ports {led0_r}]

# Buttons (active high)
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports {btn[0]}]
set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports {btn[1]}]

# USB-UART (FT2232H channel B); names are from the host's point of view
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports {uart_rxd_out}]
set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 } [get_ports {uart_txd_in}]
