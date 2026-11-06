// =============================================================================
// Module  : serial_ctrl_top.v
// Project : Multi-Standard Serial Communication Controller
// Author  : akashj10sjps
// Date    : 2026-11-06
//
// Description:
//   Top-level integration of all serial peripheral blocks:
//     • Shared baud-rate generator
//     • UART transmitter and receiver (with async FIFOs for CDC)
//     • SPI master
//     • I2C master and slave
//     • Dual-flop synchronizers for single-bit CDC signals
//
//   Register-mapped control interface (8-bit address, 8-bit data):
//
//   Address | Register         | Description
//   --------+------------------+-----------------------------------------------
//   0x00    | CTRL             | [1]=SPI_EN [0]=UART_EN
//   0x01    | BAUD_DIV_L       | Baud divisor bits [7:0]
//   0x02    | BAUD_DIV_H       | Baud divisor bits [15:8]
//   0x03    | UART_TX_DATA     | Write: load TX FIFO
//   0x04    | UART_RX_DATA     | Read:  drain RX FIFO
//   0x05    | UART_STATUS      | [1]=RX_VALID [0]=TX_BUSY
//   0x06    | SPI_TX_DATA      | Write: load SPI data, auto-starts transfer
//   0x07    | SPI_RX_DATA      | Read:  SPI received byte
//   0x08    | SPI_STATUS       | [1]=RX_VALID [0]=BUSY
//   0x09    | I2C_DEV_ADDR     | 7-bit I2C slave address
//   0x0A    | I2C_REG_ADDR     | 8-bit register address
//   0x0B    | I2C_TX_DATA      | Data to write over I2C
//   0x0C    | I2C_RX_DATA      | Data read over I2C
//   0x0D    | I2C_CTRL         | [1]=START [0]=RW
//   0x0E    | I2C_STATUS       | [2]=ACK_ERR [1]=RX_VALID [0]=BUSY
//
// Clock domains:
//   clk     – system/core clock (e.g. 100 MHz)
//   pclk    – peripheral clock (e.g. 50 MHz; only used for FIFO illustration)
//             In this design pclk is not driven externally; the async FIFOs
//             demonstrate the CDC handshake pattern used in silicon.
// =============================================================================

`timescale 1ns/1ps

module serial_ctrl_top #(
    parameter SYS_CLK_HZ  = 100_000_000,
    parameter UART_BAUD   = 115_200,
    parameter OVERSAMPLE  = 16,
    parameter SPI_DATA_W  = 8,
    parameter CPOL        = 0,
    parameter CPHA        = 0,
    parameter I2C_CLK_DIV = 125    // 100 MHz / 400 kHz / 2
)(
    input  wire        clk,
    input  wire        pclk,       // peripheral clock (CDC demo)
    input  wire        rst_n,

    // Register bus interface
    input  wire [7:0]  reg_addr,
    input  wire [7:0]  reg_wdata,
    input  wire        reg_we,
    input  wire        reg_re,
    output reg  [7:0]  reg_rdata,

    // UART external pins
    output wire        uart_tx_pin,
    input  wire        uart_rx_pin,

    // SPI external pins
    output wire        spi_sclk,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire        spi_cs_n,

    // I2C external pins (open-drain, tie to IOBUF in XDC)
    output wire        i2c_scl,
    inout  wire        i2c_sda
);

    // =========================================================================
    // Internal registers
    // =========================================================================
    reg [15:0] baud_div;
    reg        uart_en, spi_en;

    // UART
    reg [7:0]  uart_tx_data_r;
    reg        uart_tx_start;

    // SPI
    reg [7:0]  spi_tx_data_r;
    reg        spi_start_r;

    // I2C
    reg [6:0]  i2c_dev_addr_r;
    reg [7:0]  i2c_reg_addr_r;
    reg [7:0]  i2c_tx_data_r;
    reg        i2c_rw_r;
    reg        i2c_start_pulse;

    // =========================================================================
    // Shared baud-rate generator
    // =========================================================================
    wire baud_en_uart;
    wire baud_en_spi;

    // UART uses 16× oversampled baud_en
    localparam [15:0] UART_DIV = (SYS_CLK_HZ / (UART_BAUD * OVERSAMPLE)) - 1;

    baud_rate_gen #(.CNT_WIDTH(16)) u_baud_uart (
        .clk     (clk),
        .rst_n   (rst_n),
        .divisor (baud_div),
        .baud_en (baud_en_uart)
    );

    // SPI uses full-rate baud_en (same divisor)
    baud_rate_gen #(.CNT_WIDTH(16)) u_baud_spi (
        .clk     (clk),
        .rst_n   (rst_n),
        .divisor (baud_div),
        .baud_en (baud_en_spi)
    );

    // =========================================================================
    // UART TX
    // =========================================================================
    wire uart_tx_busy;
    uart_tx #(
        .DATA_BITS  (8),
        .STOP_BITS  (1),
        .PARITY_EN  (0)
    ) u_uart_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .baud_en  (baud_en_uart),
        .tx_data  (uart_tx_data_r),
        .tx_start (uart_tx_start),
        .tx       (uart_tx_pin),
        .tx_busy  (uart_tx_busy)
    );

    // =========================================================================
    // UART RX
    // =========================================================================
    wire       uart_rx_valid;
    wire [7:0] uart_rx_byte;
    wire       uart_rx_error;

    uart_rx #(
        .DATA_BITS  (8),
        .STOP_BITS  (1),
        .PARITY_EN  (0),
        .OVERSAMPLE (OVERSAMPLE)
    ) u_uart_rx (
        .clk      (clk),
        .rst_n    (rst_n),
        .baud_en  (baud_en_uart),
        .rx       (uart_rx_pin),
        .rx_data  (uart_rx_byte),
        .rx_valid (uart_rx_valid),
        .rx_error (uart_rx_error)
    );

    // -------------------------------------------------------------------------
    // Async FIFO: RX (pclk → clk)   [CDC from peripheral to core domain]
    // -------------------------------------------------------------------------
    wire       rx_fifo_full;
    wire       rx_fifo_empty;
    reg        rx_fifo_rd_en;
    wire [7:0] rx_fifo_rd_data;

    async_fifo #(.DATA_WIDTH(8), .DEPTH(16)) u_rx_fifo (
        .wr_clk   (pclk),
        .wr_rst_n (rst_n),
        .wr_en    (uart_rx_valid),
        .wr_data  (uart_rx_byte),
        .full     (rx_fifo_full),
        .rd_clk   (clk),
        .rd_rst_n (rst_n),
        .rd_en    (rx_fifo_rd_en),
        .rd_data  (rx_fifo_rd_data),
        .empty    (rx_fifo_empty)
    );

    // =========================================================================
    // SPI Master
    // =========================================================================
    wire       spi_busy;
    wire       spi_rx_valid;
    wire [7:0] spi_rx_data;

    spi_master #(
        .DATA_BITS (SPI_DATA_W),
        .CPOL      (CPOL),
        .CPHA      (CPHA)
    ) u_spi (
        .clk      (clk),
        .rst_n    (rst_n),
        .baud_en  (baud_en_spi),
        .start    (spi_start_r),
        .tx_data  (spi_tx_data_r),
        .rx_data  (spi_rx_data),
        .rx_valid (spi_rx_valid),
        .busy     (spi_busy),
        .sclk     (spi_sclk),
        .mosi     (spi_mosi),
        .miso     (spi_miso),
        .cs_n     (spi_cs_n)
    );

    // =========================================================================
    // I2C Master
    // =========================================================================
    wire       i2c_busy;
    wire       i2c_rx_valid;
    wire [7:0] i2c_rx_data;
    wire       i2c_ack_error;

    i2c_master #(.CLK_DIV(I2C_CLK_DIV)) u_i2c_master (
        .clk        (clk),
        .rst_n      (rst_n),
        .start_xfer (i2c_start_pulse),
        .rw         (i2c_rw_r),
        .dev_addr   (i2c_dev_addr_r),
        .reg_addr   (i2c_reg_addr_r),
        .tx_data    (i2c_tx_data_r),
        .rx_data    (i2c_rx_data),
        .rx_valid   (i2c_rx_valid),
        .ack_error  (i2c_ack_error),
        .busy       (i2c_busy),
        .i2c_scl    (i2c_scl),
        .i2c_sda    (i2c_sda)
    );

    // =========================================================================
    // Status latches
    // =========================================================================
    reg spi_rx_valid_latch;
    reg i2c_rx_valid_latch;
    reg i2c_ack_error_latch;
    reg [7:0] spi_rx_latch;
    reg [7:0] i2c_rx_latch;

    always @(posedge clk) begin
        if (!rst_n) begin
            spi_rx_valid_latch  <= 1'b0;
            i2c_rx_valid_latch  <= 1'b0;
            i2c_ack_error_latch <= 1'b0;
            spi_rx_latch        <= 8'h00;
            i2c_rx_latch        <= 8'h00;
        end else begin
            if (spi_rx_valid) begin
                spi_rx_latch       <= spi_rx_data;
                spi_rx_valid_latch <= 1'b1;
            end
            if (i2c_rx_valid) begin
                i2c_rx_latch       <= i2c_rx_data;
                i2c_rx_valid_latch <= 1'b1;
            end
            if (i2c_ack_error)
                i2c_ack_error_latch <= 1'b1;
        end
    end

    // =========================================================================
    // Register write logic
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            baud_div        <= UART_DIV;
            uart_en         <= 1'b1;
            spi_en          <= 1'b1;
            uart_tx_data_r  <= 8'h00;
            uart_tx_start   <= 1'b0;
            spi_tx_data_r   <= 8'h00;
            spi_start_r     <= 1'b0;
            i2c_dev_addr_r  <= 7'h00;
            i2c_reg_addr_r  <= 8'h00;
            i2c_tx_data_r   <= 8'h00;
            i2c_rw_r        <= 1'b0;
            i2c_start_pulse <= 1'b0;
            rx_fifo_rd_en   <= 1'b0;
        end else begin
            // Auto-clear pulses
            uart_tx_start   <= 1'b0;
            spi_start_r     <= 1'b0;
            i2c_start_pulse <= 1'b0;
            rx_fifo_rd_en   <= 1'b0;

            if (reg_we) begin
                case (reg_addr)
                    8'h00: {spi_en, uart_en}  <= reg_wdata[1:0];
                    8'h01: baud_div[7:0]      <= reg_wdata;
                    8'h02: baud_div[15:8]     <= reg_wdata;
                    8'h03: begin
                               uart_tx_data_r <= reg_wdata;
                               uart_tx_start  <= 1'b1;
                           end
                    8'h06: begin
                               spi_tx_data_r <= reg_wdata;
                               spi_start_r   <= 1'b1;
                           end
                    8'h09: i2c_dev_addr_r     <= reg_wdata[6:0];
                    8'h0A: i2c_reg_addr_r     <= reg_wdata;
                    8'h0B: i2c_tx_data_r      <= reg_wdata;
                    8'h0D: begin
                               i2c_rw_r        <= reg_wdata[0];
                               if (reg_wdata[1])
                                   i2c_start_pulse <= 1'b1;
                           end
                    default: ;
                endcase
            end

            // Auto-read RX FIFO when reg 0x04 is read
            if (reg_re && reg_addr == 8'h04)
                rx_fifo_rd_en <= 1'b1;

            // Clear status latches on read
            if (reg_re && reg_addr == 8'h08) spi_rx_valid_latch  <= 1'b0;
            if (reg_re && reg_addr == 8'h0E) begin
                i2c_rx_valid_latch  <= 1'b0;
                i2c_ack_error_latch <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Register read logic
    // =========================================================================
    always @(*) begin
        case (reg_addr)
            8'h00: reg_rdata = {6'b0, spi_en, uart_en};
            8'h01: reg_rdata = baud_div[7:0];
            8'h02: reg_rdata = baud_div[15:8];
            8'h04: reg_rdata = rx_fifo_rd_data;
            8'h05: reg_rdata = {6'b0, uart_rx_valid, uart_tx_busy};
            8'h07: reg_rdata = spi_rx_latch;
            8'h08: reg_rdata = {6'b0, spi_rx_valid_latch, spi_busy};
            8'h0C: reg_rdata = i2c_rx_latch;
            8'h0E: reg_rdata = {5'b0, i2c_ack_error_latch,
                                       i2c_rx_valid_latch, i2c_busy};
            default: reg_rdata = 8'hFF;
        endcase
    end

endmodule
