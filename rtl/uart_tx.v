// =============================================================================
// Module  : uart_tx.v
// Project : Multi-Standard Serial Communication Controller
// Author  : akashj10sjps
// Date    : 2026-11-06
//
// Description:
//   UART transmitter.  Data is sampled from tx_data when tx_start is pulsed
//   and tx_busy is low.  The module serialises the byte as:
//     Idle → Start bit (0) → D[0..7] → Parity (optional) → Stop bit(s)
//
//   The parity_en / parity_even parameters select None / Odd / Even parity.
//   baud_en is the shared single-cycle enable from baud_rate_gen.
//
// Parameters:
//   DATA_BITS   – payload width (5–8, default 8)
//   STOP_BITS   – number of stop bits (1 or 2, default 1)
//   PARITY_EN   – 0 = none, 1 = enabled
//   PARITY_EVEN – 0 = odd,  1 = even (only when PARITY_EN = 1)
// =============================================================================

`timescale 1ns/1ps

module uart_tx #(
    parameter DATA_BITS   = 8,
    parameter STOP_BITS   = 1,
    parameter PARITY_EN   = 0,
    parameter PARITY_EVEN = 1
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             baud_en,          // From shared baud_rate_gen
    input  wire [DATA_BITS-1:0] tx_data,
    input  wire             tx_start,
    output reg              tx,               // Serial output
    output reg              tx_busy
);

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
    reg [2:0]           bit_idx;        // current data bit index
    reg [DATA_BITS-1:0] shift_reg;
    reg                 parity_bit;
    reg [1:0]           stop_cnt;

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            tx          <= 1'b1;        // Idle high (mark)
            tx_busy     <= 1'b0;
            bit_idx     <= 3'd0;
            shift_reg   <= {DATA_BITS{1'b0}};
            parity_bit  <= 1'b0;
            stop_cnt    <= 2'd0;
        end else begin
            case (state)
                // ---------------------------------------------------------
                S_IDLE: begin
                    tx      <= 1'b1;
                    tx_busy <= 1'b0;
                    if (tx_start) begin
                        shift_reg  <= tx_data;
                        parity_bit <= (PARITY_EVEN) ? ^tx_data : ~^tx_data;
                        tx_busy    <= 1'b1;
                        state      <= S_START;
                    end
                end

                // ---------------------------------------------------------
                S_START: begin
                    if (baud_en) begin
                        tx      <= 1'b0;   // start bit
                        bit_idx <= 3'd0;
                        state   <= S_DATA;
                    end
                end

                // ---------------------------------------------------------
                S_DATA: begin
                    if (baud_en) begin
                        tx        <= shift_reg[0];
                        shift_reg <= shift_reg >> 1;
                        if (bit_idx == DATA_BITS - 1) begin
                            bit_idx <= 3'd0;
                            state   <= (PARITY_EN) ? S_PAR : S_STOP;
                            stop_cnt<= 2'd0;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end
                end

                // ---------------------------------------------------------
                S_PAR: begin
                    if (baud_en) begin
                        tx    <= parity_bit;
                        state <= S_STOP;
                        stop_cnt <= 2'd0;
                    end
                end

                // ---------------------------------------------------------
                S_STOP: begin
                    if (baud_en) begin
                        tx <= 1'b1;
                        if (stop_cnt == STOP_BITS - 1) begin
                            state   <= S_IDLE;
                            tx_busy <= 1'b0;
                        end else begin
                            stop_cnt <= stop_cnt + 1'b1;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
