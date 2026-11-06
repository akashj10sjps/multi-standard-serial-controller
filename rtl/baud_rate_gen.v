// =============================================================================
// Module  : baud_rate_gen.v
// Project : Multi-Standard Serial Communication Controller
// Author  : akashj10sjps
// Date    : 2026-11-06
// 
// Description:
//   Shared baud-rate / clock-enable generator used by both UART and SPI
//   modules.  A single 16-bit counter divides the system clock (clk) down
//   to a programmable baud tick (baud_en).  The divisor is loaded via the
//   DIVISOR input so both peripherals share the same hardware at the cost
//   of not being able to run at independent full-speed rates simultaneously.
//
//   baud_en is a single-cycle pulse asserted once every (DIVISOR+1) clk
//   cycles.  For 115 200 baud on a 100 MHz system clock set DIVISOR = 867.
//
// Parameters:
//   CNT_WIDTH – width of the internal counter (default 16 bits supports
//               divisors up to 65535, i.e. ≥ 1526 baud @ 100 MHz)
// =============================================================================

`timescale 1ns/1ps

module baud_rate_gen #(
    parameter CNT_WIDTH = 16
)(
    input  wire                 clk,        // System clock
    input  wire                 rst_n,      // Active-low synchronous reset
    input  wire [CNT_WIDTH-1:0] divisor,    // (clk_freq / baud_rate) - 1
    output reg                  baud_en     // Single-cycle baud tick
);

    reg [CNT_WIDTH-1:0] counter;

    always @(posedge clk) begin
        if (!rst_n) begin
            counter  <= {CNT_WIDTH{1'b0}};
            baud_en  <= 1'b0;
        end else begin
            if (counter == divisor) begin
                counter <= {CNT_WIDTH{1'b0}};
                baud_en <= 1'b1;
            end else begin
                counter <= counter + 1'b1;
                baud_en <= 1'b0;
            end
        end
    end

endmodule
