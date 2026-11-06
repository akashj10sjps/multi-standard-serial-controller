# Multi-Standard Serial Communication Controller

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Verilog/SystemVerilog](https://img.shields.io/badge/HDL-Verilog%20%2F%20SystemVerilog-orange)
![Target FPGA](https://img.shields.io/badge/FPGA-Xilinx%20Artix--7-red)
![Coverage](https://img.shields.io/badge/Code%20Coverage-%3E98%25-brightgreen)

> A configurable, multi-protocol serial communication controller implemented
> in Verilog/SystemVerilog and validated on a **Xilinx Artix-7 FPGA** (Arty A7-100T).  
> Supports **UART**, **SPI (master)**, and **I2C (master + slave)** from a shared
> register-mapped control interface.

---

## ✨ Feature Highlights

| Feature | Detail |
|---|---|
| **Protocols** | UART full-duplex · SPI master (modes 0–3) · I2C master + slave |
| **Shared baud generator** | One 16-bit counter drives both UART and SPI to save gate count |
| **CDC** | Dual-flop synchronizers + Gray-coded async FIFOs between peripheral ↔ core clocks |
| **UART** | 5–8 data bits · 1–2 stop bits · Even/Odd/No parity · 16× oversampling |
| **SPI** | Configurable CPOL/CPHA · Full-duplex · Programmable word width |
| **I2C** | 7-bit addressing · 100/400 kHz · ACK/NACK detection · Register-file slave |
| **Register bus** | 8-bit address / 8-bit data APB-like interface |
| **Target** | Xilinx Artix-7 XC7A100TCSG324-1 (Arty A7-100T) |
| **Simulation** | ModelSim/QuestaSim with SystemVerilog cover groups, > 98% code coverage |

---

## 📁 Repository Layout

```
.
├── rtl/
│   ├── baud_rate_gen.v        # Shared 16-bit programmable baud-rate generator
│   ├── uart_tx.v              # UART transmitter (configurable framing)
│   ├── uart_rx.v              # UART receiver  (16× oversampling, error detect)
│   ├── spi_master.v           # SPI master (CPOL/CPHA 0–3, full-duplex)
│   ├── i2c_master.v           # I2C master (START/STOP/ACK/NACK)
│   ├── i2c_slave.v            # I2C slave (8×8 register file, address match)
│   ├── async_fifo.v           # Asynchronous FIFO (Gray-code CDC)
│   ├── dual_flop_sync.v       # Parameterizable 2-flop synchronizer
│   └── serial_ctrl_top.v      # Top-level integration + register bus
│
├── tb/
│   ├── tb_uart.sv             # UART TX→RX loopback, 16-vector, coverage
│   ├── tb_spi.sv              # SPI loopback, all CPOL/CPHA modes
│   ├── tb_i2c.sv              # I2C master+slave write/read/NACK test
│   └── tb_async_fifo.sv       # FIFO: fill/drain, concurrent R/W, rollover
│
├── sim/
│   └── run_all.tcl            # ModelSim Tcl: compile → simulate → coverage merge
│
├── synth/
│   └── vivado_build.tcl       # Vivado batch script: synth → impl → bitstream
│
├── constraints/
│   └── artix7_top.xdc         # Pin, timing, CDC false-path constraints
│
└── README.md
```

---

## 🔧 Architecture

```
                    ┌─────────────────────────────────────────────────────┐
                    │               serial_ctrl_top.v                     │
                    │                                                     │
  reg_addr ────────►│                                                     │
  reg_wdata────────►│  ┌─────────────────┐  ┌──────────────────────────┐ │
  reg_we  ─────────►│  │  baud_rate_gen  │  │       async_fifo         │ │
  reg_re  ─────────►│  │  (shared 16-bit)│  │  (Gray-code CDC FIFO)   │ │
  reg_rdata◄────────│  └────────┬────────┘  └──────────────────────────┘ │
                    │           │baud_en                                  │
                    │   ┌───────┴──────────────────────────┐              │
                    │   │                                  │              │
                    │   ▼               ▼                  ▼              │
                    │  uart_tx       spi_master        i2c_master        │
                    │  uart_rx       (CPOL/CPHA)       i2c_slave         │
                    │                                                     │
                    └─────────────────────────────────────────────────────┘
                           │                │               │
                       uart_tx/rx        spi_sclk/        i2c_scl/sda
                       (serial)          mosi/miso/cs_n   (open-drain)
```

### Clock Domain Crossing

```
  pclk domain                       clk domain (100 MHz)
 ─────────────                     ──────────────────────
  Peripheral                         Core logic
  UART RX ──► [ async_fifo ] ──────► rx_fifo_rd_data
              (Gray-code pointers)
              synchronized by
              dual-flop synchronizers
```

---

## ⚡ Register Map

| Address | Register | Access | Description |
|---------|----------|--------|-------------|
| `0x00` | `CTRL` | R/W | `[1]` SPI_EN · `[0]` UART_EN |
| `0x01` | `BAUD_DIV_L` | R/W | Divisor bits [7:0] |
| `0x02` | `BAUD_DIV_H` | R/W | Divisor bits [15:8] |
| `0x03` | `UART_TX_DATA` | W | Write byte → TX FIFO (auto-starts) |
| `0x04` | `UART_RX_DATA` | R | Read byte from RX FIFO |
| `0x05` | `UART_STATUS` | R | `[1]` RX_VALID · `[0]` TX_BUSY |
| `0x06` | `SPI_TX_DATA` | W | Write byte → SPI (auto-starts) |
| `0x07` | `SPI_RX_DATA` | R | SPI received byte |
| `0x08` | `SPI_STATUS` | R | `[1]` RX_VALID · `[0]` BUSY |
| `0x09` | `I2C_DEV_ADDR` | R/W | 7-bit slave address |
| `0x0A` | `I2C_REG_ADDR` | R/W | 8-bit register address |
| `0x0B` | `I2C_TX_DATA` | R/W | Data to write |
| `0x0C` | `I2C_RX_DATA` | R | Data received |
| `0x0D` | `I2C_CTRL` | W | `[1]` START · `[0]` R/W |
| `0x0E` | `I2C_STATUS` | R | `[2]` ACK_ERR · `[1]` RX_VALID · `[0]` BUSY |

### Baud Divisor Formula

```
DIVISOR = (clk_freq / (baud_rate × oversample)) - 1

Example: 115200 baud, 100 MHz, 16× oversample
DIVISOR = (100_000_000 / (115_200 × 16)) - 1 ≈ 53
```

---

## 🚀 Simulation (ModelSim / QuestaSim)

```bash
# From the sim/ directory:
vsim -do run_all.tcl

# Or compile + run individual testbench:
vlog -sv +acc ../rtl/*.v ../tb/tb_uart.sv
vsim -t 1ps -coverage work.tb_uart
run -all
```

Coverage HTML report will be generated at `sim/coverage_html/index.html`.

---

## 🏗 Synthesis & Implementation (Vivado)

```bash
# From the synth/ directory:
vivado -mode batch -source vivado_build.tcl
```

Generated reports:
- `timing_summary.rpt`
- `utilization.rpt`
- `power.rpt`
- `cdc_report.rpt`
- `methodology.rpt`

---

## 📊 Resource Utilization (Artix-7 XC7A100T — post-implementation estimate)

| Module | LUTs | FFs | BRAM | DSPs |
|--------|------|-----|------|------|
| baud_rate_gen | ~20 | ~18 | 0 | 0 |
| uart_tx | ~35 | ~30 | 0 | 0 |
| uart_rx | ~55 | ~45 | 0 | 0 |
| spi_master | ~60 | ~50 | 0 | 0 |
| i2c_master | ~90 | ~75 | 0 | 0 |
| i2c_slave | ~70 | ~60 | 0 | 0 |
| async_fifo × 2 | ~50 | ~40 | 1 | 0 |
| dual_flop_sync | ~5 | ~8 | 0 | 0 |
| **Total** | **~385** | **~326** | **1** | **0** |

---

## 🛡 Key Design Decisions

### Shared Baud-Rate Generator
Both UART and SPI derive their clocking from the same 16-bit counter.  
**Trade-off:** Cannot run UART at 115 200 baud and SPI at a different independent rate simultaneously, but gate count is reduced (~20 LUTs saved).

### Metastability Mitigation
- Single-bit signals crossing clock domains use `dual_flop_sync` (2-stage FF chain, Xilinx `ASYNC_REG` attribute).
- Multi-bit data crossing via `async_fifo` with Gray-coded binary pointers — only one bit changes per increment, eliminating multi-bit metastability.

### I2C Open-Drain SDA
SDA is modelled as a tri-state `inout`. The synthesis target infers an IOBUF; in simulation `1'bz` resolves to `1` via weak-pull-up (`tri1` net in testbench).

---

## 📜 License

MIT © 2026 akashj10sjps
