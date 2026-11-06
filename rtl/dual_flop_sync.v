// =============================================================================
// Module  : dual_flop_sync.v
// Project : Multi-Standard Serial Communication Controller
// Author  : akashj10sjps
// Date    : 2026-11-06
//
// Description:
//   Generic N-bit two-flop synchronizer for clock domain crossing.
//   The first flip-flop may capture a metastable value; the second flop
//   resolves it before the destination logic samples it.
//
//   Use one instance per signal crossing from one clock domain to another.
//   For multi-bit buses, use the async_fifo or encode as Gray code first.
//
// Parameters:
//   WIDTH     – number of bits to synchronize (default 1)
//   SYNC_STGS – number of synchronizer stages (default 2; increase to 3
//               for very fast or unreliable clocks)
// =============================================================================

`timescale 1ns/1ps

module dual_flop_sync #(
    parameter WIDTH     = 1,
    parameter SYNC_STGS = 2
)(
    input  wire             dst_clk,
    input  wire             dst_rst_n,
    input  wire [WIDTH-1:0] src_data,
    output wire [WIDTH-1:0] dst_data
);

    (* ASYNC_REG = "TRUE" *)
    reg [WIDTH-1:0] sync_reg [0:SYNC_STGS-1];

    integer i;
    always @(posedge dst_clk) begin
        if (!dst_rst_n) begin
            for (i = 0; i < SYNC_STGS; i = i + 1)
                sync_reg[i] <= {WIDTH{1'b0}};
        end else begin
            sync_reg[0] <= src_data;
            for (i = 1; i < SYNC_STGS; i = i + 1)
                sync_reg[i] <= sync_reg[i-1];
        end
    end

    assign dst_data = sync_reg[SYNC_STGS-1];

endmodule
