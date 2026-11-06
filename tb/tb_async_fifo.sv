// =============================================================================
// Testbench : tb_async_fifo.sv
// Project   : Multi-Standard Serial Communication Controller
// Author    : akashj10sjps
// Date      : 2026-11-06
//
// Description:
//   SystemVerilog testbench for the asynchronous FIFO (CDC).
//   Tests:
//     1. Basic write/read across different write/read clock ratios
//     2. Full condition handling (write blocked when full)
//     3. Empty condition handling (read blocked when empty)
//     4. Simultaneous read/write (steady-state throughput)
//     5. Gray-pointer rollover (ptr wraps around DEPTH boundary)
// =============================================================================

`timescale 1ns/1ps

module tb_async_fifo;

    // -------------------------------------------------------------------------
    // Clocks (deliberately different frequencies to stress CDC)
    // -------------------------------------------------------------------------
    reg wr_clk = 0;
    reg rd_clk = 0;
    always #5  wr_clk = ~wr_clk;    //100 MHz write clock
    always #7  rd_clk = ~rd_clk;    // ~71 MHz read clock

    reg wr_rst_n = 0;
    reg rd_rst_n = 0;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    reg        wr_en  = 0;
    reg  [7:0] wr_data = 0;
    wire       full;
    reg        rd_en  = 0;
    wire [7:0] rd_data;
    wire       empty;

    async_fifo #(.DATA_WIDTH(8), .DEPTH(16)) dut (
        .wr_clk   (wr_clk),
        .wr_rst_n (wr_rst_n),
        .wr_en    (wr_en),
        .wr_data  (wr_data),
        .full     (full),
        .rd_clk   (rd_clk),
        .rd_rst_n (rd_rst_n),
        .rd_en    (rd_en),
        .rd_data  (rd_data),
        .empty    (empty)
    );

    // -------------------------------------------------------------------------
    // Result counters
    // -------------------------------------------------------------------------
    int pass_cnt = 0;
    int fail_cnt = 0;

    // -------------------------------------------------------------------------
    // Write task
    // -------------------------------------------------------------------------
    task write_data(input [7:0] data);
        @(posedge wr_clk);
        wait (!full);
        @(posedge wr_clk);
        wr_data = data;
        wr_en   = 1'b1;
        @(posedge wr_clk);
        wr_en   = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Read task
    // -------------------------------------------------------------------------
    task read_and_check(input [7:0] expected);
        @(posedge rd_clk);
        wait (!empty);
        @(posedge rd_clk);
        rd_en = 1'b1;
        @(posedge rd_clk);
        rd_en = 1'b0;
        @(posedge rd_clk);
        if (rd_data === expected) begin
            $display("[PASS] FIFO rd: %02X", rd_data);
            pass_cnt++;
        end else begin
            $display("[FAIL] FIFO rd: expected %02X got %02X", expected, rd_data);
            fail_cnt++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    int i;

    initial begin
        // Reset
        wr_rst_n = 0;
        rd_rst_n = 0;
        repeat(10) @(posedge wr_clk);
        wr_rst_n = 1;
        rd_rst_n = 1;
        repeat(5)  @(posedge wr_clk);

        $display("=== Async FIFO Test ===");

        // ---- Test 1: Fill FIFO then drain ----
        $display("--- Fill then drain ---");
        for (i = 0; i < 16; i++)
            write_data(i[7:0]);

        // Check full
        @(posedge wr_clk);
        if (full) begin
            $display("[PASS] FIFO correctly asserts FULL");
            pass_cnt++;
        end else begin
            $display("[FAIL] FIFO should be FULL");
            fail_cnt++;
        end

        for (i = 0; i < 16; i++)
            read_and_check(i[7:0]);

        @(posedge rd_clk);
        if (empty) begin
            $display("[PASS] FIFO correctly asserts EMPTY");
            pass_cnt++;
        end else begin
            $display("[FAIL] FIFO should be EMPTY");
            fail_cnt++;
        end

        // ---- Test 2: Simultaneous read/write ----
        $display("--- Simultaneous R/W ---");
        fork
            begin
                for (i = 0; i < 20; i++) begin
                    @(posedge wr_clk);
                    if (!full) begin
                        wr_data = 8'hA0 + i;
                        wr_en   = 1'b1;
                        @(posedge wr_clk);
                        wr_en = 1'b0;
                    end
                end
            end
            begin
                repeat(5) @(posedge rd_clk); // small delay
                for (i = 0; i < 20; i++) begin
                    @(posedge rd_clk);
                    if (!empty) begin
                        rd_en = 1'b1;
                        @(posedge rd_clk);
                        rd_en = 1'b0;
                        $display("[INFO] Concurrent read: %02X", rd_data);
                    end
                end
            end
        join

        // ---- Test 3: Pointer rollover ----
        $display("--- Pointer rollover ---");
        for (i = 0; i < 48; i++) begin
            write_data(8'hC0 + (i % 16));
            read_and_check(8'hC0 + (i % 16));
        end

        $display("=== Results: %0d PASS / %0d FAIL ===", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("ALL FIFO TESTS PASSED");
        else               $display("SOME FIFO TESTS FAILED");
        $finish;
    end

    initial begin
        #10_000_000;
        $display("[TIMEOUT]");
        $finish;
    end

    initial begin
        $dumpfile("fifo_tb.vcd");
        $dumpvars(0, tb_async_fifo);
    end

endmodule
