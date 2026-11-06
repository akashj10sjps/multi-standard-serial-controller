# =============================================================================
# ModelSim / QuestaSim simulation script
# Project : Multi-Standard Serial Communication Controller
# Author  : akashj10sjps
# Usage   : vsim -do sim/run_all.tcl
# =============================================================================

# Compilation output directory
set LIB work
vlib $LIB

# -----------------------------------------------------------------------
# Compile RTL sources
# -----------------------------------------------------------------------
set RTL_DIR "../rtl"

vlog -sv +acc "$RTL_DIR/baud_rate_gen.v"
vlog -sv +acc "$RTL_DIR/dual_flop_sync.v"
vlog -sv +acc "$RTL_DIR/async_fifo.v"
vlog -sv +acc "$RTL_DIR/uart_tx.v"
vlog -sv +acc "$RTL_DIR/uart_rx.v"
vlog -sv +acc "$RTL_DIR/spi_master.v"
vlog -sv +acc "$RTL_DIR/i2c_master.v"
vlog -sv +acc "$RTL_DIR/i2c_slave.v"
vlog -sv +acc "$RTL_DIR/serial_ctrl_top.v"

# -----------------------------------------------------------------------
# Compile testbenches
# -----------------------------------------------------------------------
set TB_DIR "../tb"

vlog -sv +acc "$TB_DIR/tb_uart.sv"
vlog -sv +acc "$TB_DIR/tb_spi.sv"
vlog -sv +acc "$TB_DIR/tb_i2c.sv"
vlog -sv +acc "$TB_DIR/tb_async_fifo.sv"

# -----------------------------------------------------------------------
# Run UART testbench
# -----------------------------------------------------------------------
puts "\n========== Running UART Testbench =========="
vsim -t 1ps -coverage work.tb_uart
add wave -recursive *
coverage save uart_cov.ucdb
run -all
coverage report -detail
quit -sim

# -----------------------------------------------------------------------
# Run SPI testbench
# -----------------------------------------------------------------------
puts "\n========== Running SPI Testbench =========="
vsim -t 1ps -coverage work.tb_spi
add wave -recursive *
coverage save spi_cov.ucdb
run -all
coverage report -detail
quit -sim

# -----------------------------------------------------------------------
# Run I2C testbench
# -----------------------------------------------------------------------
puts "\n========== Running I2C Testbench =========="
vsim -t 1ps -coverage work.tb_i2c
add wave -recursive *
coverage save i2c_cov.ucdb
run -all
coverage report -detail
quit -sim

# -----------------------------------------------------------------------
# Run Async FIFO testbench
# -----------------------------------------------------------------------
puts "\n========== Running Async FIFO Testbench =========="
vsim -t 1ps -coverage work.tb_async_fifo
add wave -recursive *
coverage save fifo_cov.ucdb
run -all
coverage report -detail
quit -sim

# -----------------------------------------------------------------------
# Merge coverage databases
# -----------------------------------------------------------------------
puts "\n========== Merging Coverage Databases =========="
coverage merge -out merged.ucdb uart_cov.ucdb spi_cov.ucdb i2c_cov.ucdb fifo_cov.ucdb
coverage report -html -output coverage_html -details -annotate merged.ucdb

puts "\n========== All simulations complete =========="
puts "Coverage report written to: sim/coverage_html/index.html"
