// =============================================================================
// Module  : uart_rx.v
// Project : Multi-Standard Serial Communication Controller
// Author  : akashj10sjps
// Date    : 2026-11-06
//
// Description:
//   UART receiver.  Detects the start-bit falling edge, then samples each
//   bit at the mid-point of the baud period (using a 16× oversampled enable
//   derived from baud_en).  After all data bits (and optional parity bit)
//   are received the byte is presented on rx_data with rx_valid pulsed for
//   one clock cycle.
//
//   rx_error is asserted when:
//     • The stop bit is not 1 (framing error)
//     • Parity does not match (parity error, only when PARITY_EN = 1)
//
// Parameters: same as uart_tx.
// =============================================================================

`timescale 1ns/1ps

module uart_rx #(
    parameter DATA_BITS   = 8,
    parameter STOP_BITS   = 1,
    parameter PARITY_EN   = 0,
    parameter PARITY_EVEN = 1,
    parameter OVERSAMPLE  = 16        // oversampling factor (must match baud_en rate × OVERSAMPLE = clk freq)
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             baud_en,          // 16× baud tick (same generator, divisor / OVERSAMPLE)
    input  wire             rx,               // Serial input (registered internally)
    output reg  [DATA_BITS-1:0] rx_data,
    output reg              rx_valid,
    output reg              rx_error
);

    // -------------------------------------------------------------------------
    // Double-flop synchronizer for rx line
    // -------------------------------------------------------------------------
    reg rx_sync0, rx_sync1, rx_prev;

    always @(posedge clk) begin
        if (!rst_n) begin
            rx_sync0 <= 1'b1;
            rx_sync1 <= 1'b1;
            rx_prev  <= 1'b1;
        end else begin
            rx_sync0 <= rx;
            rx_sync1 <= rx_sync0;
            rx_prev  <= rx_sync1;
        end
    end

    wire rx_fall = rx_prev & ~rx_sync1;   // falling edge = start bit

    // -------------------------------------------------------------------------
    // State encoding
    // -------------------------------------------------------------------------
    localparam [2:0]
        S_IDLE  = 3'd0,
        S_START = 3'd1,
        S_DATA  = 3'd2,
        S_PAR   = 3'd3,
        S_STOP  = 3'd4;

    reg [2:0]           state;
    reg [3:0]           sample_cnt;    // counts baud_en ticks within one bit period
    reg [2:0]           bit_idx;
    reg [DATA_BITS-1:0] shift_reg;
    reg                 parity_calc;

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            rx_data     <= {DATA_BITS{1'b0}};
            rx_valid    <= 1'b0;
            rx_error    <= 1'b0;
            sample_cnt  <= 4'd0;
            bit_idx     <= 3'd0;
            shift_reg   <= {DATA_BITS{1'b0}};
            parity_calc <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            rx_error <= 1'b0;

            case (state)
                // ---------------------------------------------------------
                S_IDLE: begin
                    if (rx_fall) begin
                        sample_cnt <= 4'd0;
                        state      <= S_START;
                    end
                end

                // ---------------------------------------------------------
                // Wait until mid-point of start bit (OVERSAMPLE/2 ticks)
                S_START: begin
                    if (baud_en) begin
                        if (sample_cnt == (OVERSAMPLE/2 - 1)) begin
                            if (~rx_sync1) begin
                                // Valid start bit
                                sample_cnt  <= 4'd0;
                                bit_idx     <= 3'd0;
                                parity_calc <= (PARITY_EVEN) ? 1'b0 : 1'b1;
                                state       <= S_DATA;
                            end else begin
                                // Glitch – abort
                                state <= S_IDLE;
                            end
                        end else begin
                            sample_cnt <= sample_cnt + 1'b1;
                        end
                    end
                end

                // ---------------------------------------------------------
                S_DATA: begin
                    if (baud_en) begin
                        if (sample_cnt == (OVERSAMPLE - 1)) begin
                            sample_cnt  <= 4'd0;
                            shift_reg   <= {rx_sync1, shift_reg[DATA_BITS-1:1]};
                            parity_calc <= parity_calc ^ rx_sync1;
                            if (bit_idx == DATA_BITS - 1) begin
                                bit_idx <= 3'd0;
                                state   <= (PARITY_EN) ? S_PAR : S_STOP;
                            end else begin
                                bit_idx <= bit_idx + 1'b1;
                            end
                        end else begin
                            sample_cnt <= sample_cnt + 1'b1;
                        end
                    end
                end

                // ---------------------------------------------------------
                S_PAR: begin
                    if (baud_en) begin
                        if (sample_cnt == (OVERSAMPLE - 1)) begin
                            sample_cnt <= 4'd0;
                            if (rx_sync1 != parity_calc)
                                rx_error <= 1'b1;
                            state <= S_STOP;
                        end else begin
                            sample_cnt <= sample_cnt + 1'b1;
                        end
                    end
                end

                // ---------------------------------------------------------
                S_STOP: begin
                    if (baud_en) begin
                        if (sample_cnt == (OVERSAMPLE - 1)) begin
                            sample_cnt <= 4'd0;
                            if (~rx_sync1)
                                rx_error <= 1'b1;   // framing error
                            else begin
                                rx_data  <= shift_reg;
                                rx_valid <= 1'b1;
                            end
                            state <= S_IDLE;
                        end else begin
                            sample_cnt <= sample_cnt + 1'b1;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
