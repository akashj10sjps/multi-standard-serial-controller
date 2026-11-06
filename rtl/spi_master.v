// =============================================================================
// Module  : spi_master.v
// Project : Multi-Standard Serial Communication Controller
// Author  : akashj10sjps
// Date    : 2026-11-06
//
// Description:
//   SPI Master controller supporting CPOL/CPHA modes 0–3.
//   The serial clock (sclk) is derived from the shared baud_en tick.
//   Full-duplex operation: MOSI sends tx_data MSB-first while MISO data
//   is captured into rx_data, presented with rx_valid.
//
// Parameters:
//   DATA_BITS – transaction width in bits (default 8)
//   CPOL      – clock polarity (0 or 1)
//   CPHA      – clock phase    (0 or 1)
// =============================================================================

`timescale 1ns/1ps

module spi_master #(
    parameter DATA_BITS = 8,
    parameter CPOL      = 0,
    parameter CPHA      = 0
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             baud_en,          // Shared baud tick

    // Control
    input  wire             start,            // Pulse to begin transfer
    input  wire [DATA_BITS-1:0] tx_data,
    output reg  [DATA_BITS-1:0] rx_data,
    output reg              rx_valid,
    output reg              busy,

    // SPI bus
    output reg              sclk,
    output reg              mosi,
    input  wire             miso,
    output reg              cs_n              // Active-low chip select
);

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------
    localparam [1:0]
        S_IDLE    = 2'd0,
        S_ASSERT  = 2'd1,   // assert CS, optional CPHA=1 half-cycle
        S_XFER    = 2'd2,
        S_DONE    = 2'd3;

    reg [1:0]            state;
    reg [$clog2(DATA_BITS*2+1)-1:0] clk_cnt;   // half-cycle counter
    reg [DATA_BITS-1:0]  shift_tx;
    reg [DATA_BITS-1:0]  shift_rx;
    reg                  sclk_r;               // SCLK register

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            cs_n      <= 1'b1;
            sclk      <= CPOL ? 1'b1 : 1'b0;
            mosi      <= 1'b1;
            rx_data   <= {DATA_BITS{1'b0}};
            rx_valid  <= 1'b0;
            busy      <= 1'b0;
            clk_cnt   <= '0;
            shift_tx  <= {DATA_BITS{1'b0}};
            shift_rx  <= {DATA_BITS{1'b0}};
            sclk_r    <= CPOL ? 1'b1 : 1'b0;
        end else begin
            rx_valid <= 1'b0;

            case (state)
                // ---------------------------------------------------------
                S_IDLE: begin
                    cs_n   <= 1'b1;
                    sclk   <= CPOL ? 1'b1 : 1'b0;
                    busy   <= 1'b0;
                    if (start) begin
                        shift_tx <= tx_data;
                        shift_rx <= {DATA_BITS{1'b0}};
                        clk_cnt  <= '0;
                        busy     <= 1'b1;
                        state    <= S_ASSERT;
                    end
                end

                // ---------------------------------------------------------
                // Assert CS; for CPHA=1 output the first MOSI bit before SCLK
                S_ASSERT: begin
                    if (baud_en) begin
                        cs_n <= 1'b0;
                        if (CPHA == 1) begin
                            mosi     <= shift_tx[DATA_BITS-1];
                            shift_tx <= shift_tx << 1;
                        end
                        clk_cnt <= '0;
                        state   <= S_XFER;
                    end
                end

                // ---------------------------------------------------------
                // Toggle SCLK every baud_en; sample / shift on each edge
                S_XFER: begin
                    if (baud_en) begin
                        sclk_r  <= ~sclk_r;
                        sclk    <= ~sclk_r;
                        clk_cnt <= clk_cnt + 1'b1;

                        // Leading edge: for CPHA=0 sample, for CPHA=1 output
                        if (sclk_r == (CPOL ^ CPHA)) begin
                            if (CPHA == 0) begin
                                // Sample MISO
                                shift_rx <= {shift_rx[DATA_BITS-2:0], miso};
                            end else begin
                                // Drive MOSI
                                mosi     <= shift_tx[DATA_BITS-1];
                                shift_tx <= shift_tx << 1;
                            end
                        end else begin
                            // Trailing edge
                            if (CPHA == 0) begin
                                // Drive MOSI
                                mosi     <= shift_tx[DATA_BITS-1];
                                shift_tx <= shift_tx << 1;
                            end else begin
                                // Sample MISO
                                shift_rx <= {shift_rx[DATA_BITS-2:0], miso};
                            end
                        end

                        if (clk_cnt == DATA_BITS * 2 - 1) begin
                            state <= S_DONE;
                        end
                    end
                end

                // ---------------------------------------------------------
                S_DONE: begin
                    if (baud_en) begin
                        cs_n     <= 1'b1;
                        sclk     <= CPOL ? 1'b1 : 1'b0;
                        rx_data  <= shift_rx;
                        rx_valid <= 1'b1;
                        busy     <= 1'b0;
                        state    <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // Initialise sclk_r
    initial sclk_r = CPOL ? 1'b1 : 1'b0;

endmodule
