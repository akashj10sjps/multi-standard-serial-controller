# =============================================================================
# Vivado synthesis + implementation Tcl script
# Project : Multi-Standard Serial Communication Controller
# Target  : Xilinx Artix-7 XC7A100TCSG324-1 (Arty A7-100T)
# Author  : akashj10sjps
# Usage   : vivado -mode batch -source synth/vivado_build.tcl
# =============================================================================

set PROJECT_NAME serial_ctrl
set TOP_MODULE   serial_ctrl_top
set PART         xc7a100tcsg324-1
set BOARD        digilentinc.com:arty-a7-100:part0:1.1

# -----------------------------------------------------------------------
# Create project
# -----------------------------------------------------------------------
create_project $PROJECT_NAME ./$PROJECT_NAME -part $PART -force
set_property board_part $BOARD [current_project]

# -----------------------------------------------------------------------
# Add RTL sources
# -----------------------------------------------------------------------
set RTL_FILES {
    ../rtl/baud_rate_gen.v
    ../rtl/dual_flop_sync.v
    ../rtl/async_fifo.v
    ../rtl/uart_tx.v
    ../rtl/uart_rx.v
    ../rtl/spi_master.v
    ../rtl/i2c_master.v
    ../rtl/i2c_slave.v
    ../rtl/serial_ctrl_top.v
}

foreach f $RTL_FILES {
    add_files -norecurse $f
}

# -----------------------------------------------------------------------
# Add constraints
# -----------------------------------------------------------------------
add_files -fileset constrs_1 -norecurse ../constraints/artix7_top.xdc

# -----------------------------------------------------------------------
# Set top module
# -----------------------------------------------------------------------
set_property top $TOP_MODULE [current_fileset]

# -----------------------------------------------------------------------
# Synthesis
# -----------------------------------------------------------------------
puts "INFO: Starting Synthesis..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1
puts "INFO: Synthesis complete."

# -----------------------------------------------------------------------
# Implementation
# -----------------------------------------------------------------------
puts "INFO: Starting Implementation..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "INFO: Implementation complete."

# -----------------------------------------------------------------------
# Reports
# -----------------------------------------------------------------------
open_run impl_1
report_timing_summary -file timing_summary.rpt
report_utilization    -file utilization.rpt
report_power          -file power.rpt
report_cdc            -file cdc_report.rpt
report_methodology    -file methodology.rpt

puts "INFO: Reports written."
puts "INFO: Bitstream location: [get_property DIRECTORY [get_runs impl_1]]/$PROJECT_NAME.runs/impl_1/${TOP_MODULE}.bit"
