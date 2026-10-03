# Digilent Cmod A7-35T: XC7A35T-1CPG236C, 12 MHz clock, FT2232H JTAG/UART, 32 Mbit (4 MiB) QSPI flash.
PART        := xc7a35tcpg236-1
FAMILY      := artix7
CHIPDB_DIE  := xc7a50t
BOARD       := cmoda7_35t
CLK_MHZ     := 12
FLASH_BYTES := 4194304
# Flash boot clock (COR0.OSCFSEL). Measured on this board: 0 = 3.3 MHz (default), 4 = 23 MHz,
# 6 = ~31 MHz (Vivado's ConfigRate 33), 8 = ~37 MHz.
OSCFSEL     := 6
