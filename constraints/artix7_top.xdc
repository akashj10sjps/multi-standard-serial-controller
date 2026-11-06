## =============================================================================
## Xilinx Artix-7 XDC Constraints
## Project : Multi-Standard Serial Communication Controller
## Target  : Digilent Arty A7-100T (XC7A100TCSG324-1)
## Author  : akashj10sjps
## Date    : 2026-11-06
##
## Modify pin assignments to match your specific board variant.
## =============================================================================

# -----------------------------------------------------------------------
# System Clock — 100 MHz onboard oscillator (Arty A7)
# -----------------------------------------------------------------------
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -name sys_clk -period 10.000 -waveform {0.000 5.000} [get_ports clk]

# -----------------------------------------------------------------------
# Peripheral clock (optional; set to 50 MHz if using pclk externally)
# -----------------------------------------------------------------------
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports pclk]
create_clock -name pclk -period 20.000 [get_ports pclk]

# -----------------------------------------------------------------------
# Active-low reset (BTN0 on Arty A7)
# -----------------------------------------------------------------------
set_property -dict { PACKAGE_PIN D9  IOSTANDARD LVCMOS33 } [get_ports rst_n]

# -----------------------------------------------------------------------
# UART pins (Arty A7 USB-UART Bridge — FTDI)
# -----------------------------------------------------------------------
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports uart_tx_pin]
set_property -dict { PACKAGE_PIN A9  IOSTANDARD LVCMOS33 } [get_ports uart_rx_pin]

# -----------------------------------------------------------------------
# SPI pins (Pmod JA — J1 header)
#   JA1  → spi_cs_n
#   JA2  → spi_mosi
#   JA3  → spi_miso
#   JA4  → spi_sclk
# -----------------------------------------------------------------------
set_property -dict { PACKAGE_PIN G13 IOSTANDARD LVCMOS33 } [get_ports spi_cs_n]
set_property -dict { PACKAGE_PIN B11 IOSTANDARD LVCMOS33 } [get_ports spi_mosi]
set_property -dict { PACKAGE_PIN A11 IOSTANDARD LVCMOS33 } [get_ports spi_miso]
set_property -dict { PACKAGE_PIN D12 IOSTANDARD LVCMOS33 } [get_ports spi_sclk]

# -----------------------------------------------------------------------
# I2C pins (Pmod JB — J2 header, with external 4.7 kΩ pull-ups to 3.3 V)
#   JB1  → i2c_scl
#   JB2  → i2c_sda  (inout — requires IOBUF in design)
# -----------------------------------------------------------------------
set_property -dict { PACKAGE_PIN E15 IOSTANDARD LVCMOS33 } [get_ports i2c_scl]
set_property -dict { PACKAGE_PIN E16 IOSTANDARD LVCMOS33 } [get_ports i2c_sda]

# -----------------------------------------------------------------------
# Register bus (tied to on-chip logic; no external IO)
# -----------------------------------------------------------------------
# reg_addr, reg_wdata, reg_we, reg_re, reg_rdata are internal AXI-lite
# or APB interface ports — not brought out to external pins in this XDC.

# -----------------------------------------------------------------------
# Timing constraints
# -----------------------------------------------------------------------
# False paths across the async FIFO clock domain crossing
set_false_path -from [get_clocks sys_clk] -to [get_clocks pclk]
set_false_path -from [get_clocks pclk]    -to [get_clocks sys_clk]

# Multi-cycle path for I2C (SCL ≪ sys_clk)
set_multicycle_path -setup 10 -from [get_pins u_i2c_master/*/C] \
                              -to   [get_pins u_i2c_master/*/D]
set_multicycle_path -hold   9 -from [get_pins u_i2c_master/*/C] \
                              -to   [get_pins u_i2c_master/*/D]

# -----------------------------------------------------------------------
# ASYNC_REG attribute propagation (dual-flop synchronizers)
# -----------------------------------------------------------------------
set_property ASYNC_REG TRUE [get_cells -hier -filter {NAME =~ *sync_reg*}]

# -----------------------------------------------------------------------
# Bitstream configuration
# -----------------------------------------------------------------------
set_property CFGBVS         VCCO [current_design]
set_property CONFIG_VOLTAGE  3.3  [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
