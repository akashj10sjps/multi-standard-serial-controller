// =============================================================================
// Module  : async_fifo.v
// Project : Multi-Standard Serial Communication Controller
// Author  : akashj10sjps
// Date    : 2026-11-06
//
// Description:
//   Asynchronous FIFO for clock-domain crossing (CDC) between the peripheral
//   clock and the core/system clock.  Uses the Gray-code pointer technique to
//   safely compare read/write pointers across clock domains.
//
//   The design prevents metastability with two-flop synchronizers on each
//   Gray-coded pointer.
//
// Parameters:
//   DATA_WIDTH – width of each data word (default 8)
//   DEPTH      – number of entries; must be a power of 2 (default 16)
// =============================================================================

`timescale 1ns/1ps

module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 16
)(
    // Write port (peripheral clock domain)
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output wire                  full,

    // Read port (core clock domain)
    input  wire                  rd_clk,
    input  wire                  rd_rst_n,
    input  wire                  rd_en,
    output reg  [DATA_WIDTH-1:0] rd_data,
    output wire                  empty
);

    localparam ADDR_W = $clog2(DEPTH);

    // -------------------------------------------------------------------------
    // Dual-port RAM
    // -------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // -------------------------------------------------------------------------
    // Write-domain pointers
    // -------------------------------------------------------------------------
    reg  [ADDR_W:0] wr_ptr_bin;    // binary
    wire [ADDR_W:0] wr_ptr_gray;   // Gray coded

    // -------------------------------------------------------------------------
    // Read-domain pointers
    // -------------------------------------------------------------------------
    reg  [ADDR_W:0] rd_ptr_bin;
    wire [ADDR_W:0] rd_ptr_gray;

    // -------------------------------------------------------------------------
    // Gray code helpers
    // -------------------------------------------------------------------------
    assign wr_ptr_gray = wr_ptr_bin ^ (wr_ptr_bin >> 1);
    assign rd_ptr_gray = rd_ptr_bin ^ (rd_ptr_bin >> 1);

    // -------------------------------------------------------------------------
    // Synchronize rd_ptr_gray into write clock domain (for full detection)
    // -------------------------------------------------------------------------
    reg [ADDR_W:0] rd_gray_sync1_wr, rd_gray_sync2_wr;

    always @(posedge wr_clk) begin
        if (!wr_rst_n) begin
            rd_gray_sync1_wr <= {(ADDR_W+1){1'b0}};
            rd_gray_sync2_wr <= {(ADDR_W+1){1'b0}};
        end else begin
            rd_gray_sync1_wr <= rd_ptr_gray;
            rd_gray_sync2_wr <= rd_gray_sync1_wr;
        end
    end

    // -------------------------------------------------------------------------
    // Synchronize wr_ptr_gray into read clock domain (for empty detection)
    // -------------------------------------------------------------------------
    reg [ADDR_W:0] wr_gray_sync1_rd, wr_gray_sync2_rd;

    always @(posedge rd_clk) begin
        if (!rd_rst_n) begin
            wr_gray_sync1_rd <= {(ADDR_W+1){1'b0}};
            wr_gray_sync2_rd <= {(ADDR_W+1){1'b0}};
        end else begin
            wr_gray_sync1_rd <= wr_ptr_gray;
            wr_gray_sync2_rd <= wr_gray_sync1_rd;
        end
    end

    // -------------------------------------------------------------------------
    // Write logic
    // -------------------------------------------------------------------------
    always @(posedge wr_clk) begin
        if (!wr_rst_n) begin
            wr_ptr_bin <= {(ADDR_W+1){1'b0}};
        end else if (wr_en && !full) begin
            mem[wr_ptr_bin[ADDR_W-1:0]] <= wr_data;
            wr_ptr_bin                  <= wr_ptr_bin + 1'b1;
        end
    end

    // Full when MSB differs but remaining bits match (Gray-code full condition)
    assign full = (wr_ptr_gray == {~rd_gray_sync2_wr[ADDR_W:ADDR_W-1],
                                    rd_gray_sync2_wr[ADDR_W-2:0]});

    // -------------------------------------------------------------------------
    // Read logic
    // -------------------------------------------------------------------------
    always @(posedge rd_clk) begin
        if (!rd_rst_n) begin
            rd_ptr_bin <= {(ADDR_W+1){1'b0}};
            rd_data    <= {DATA_WIDTH{1'b0}};
        end else if (rd_en && !empty) begin
            rd_data    <= mem[rd_ptr_bin[ADDR_W-1:0]];
            rd_ptr_bin <= rd_ptr_bin + 1'b1;
        end
    end

    assign empty = (rd_ptr_gray == wr_gray_sync2_rd);

endmodule
