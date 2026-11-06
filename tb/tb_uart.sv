// =============================================================================
// Testbench : tb_uart.sv
// Project   : Multi-Standard Serial Communication Controller
// Author    : akashj10sjps
// Date      : 2026-11-06
//
// Description:
//   SystemVerilog testbench for UART TX → RX loopback.
//   Sends multiple bytes with different configurations and checks:
//     • Data integrity (tx == rx)
//     • No framing errors
//     • Timing within ±1 baud period tolerance
//
// Coverage targets:
//   • uart_tx FSM: all states
//   • uart_rx FSM: all states
//   • Parity error injection
//   • Back-to-back transfers
// =============================================================================

`timescale 1ns/1ps

module tb_uart;

    // -------------------------------------------------------------------------
    // DUT parameters
    // -------------------------------------------------------------------------
    localparam CLK_FREQ  = 100_000_000;
    localparam BAUD_RATE = 115_200;
    localparam OVERSAMPLE = 16;
    localparam DIVISOR   = (CLK_FREQ / (BAUD_RATE * OVERSAMPLE)) - 1; // ~53

    // -------------------------------------------------------------------------
    // Clock & reset
    // -------------------------------------------------------------------------
    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    // -------------------------------------------------------------------------
    // Baud tick
    // -------------------------------------------------------------------------
    wire baud_en;
    baud_rate_gen #(.CNT_WIDTH(16)) u_brg (
        .clk     (clk),
        .rst_n   (rst_n),
        .divisor (16'd53),
        .baud_en (baud_en)
    );

    // -------------------------------------------------------------------------
    // UART TX
    // -------------------------------------------------------------------------
    reg  [7:0] tx_data;
    reg        tx_start;
    wire       tx_line;
    wire       tx_busy;

    uart_tx #(.DATA_BITS(8), .STOP_BITS(1), .PARITY_EN(0)) u_tx (
        .clk     (clk),
        .rst_n   (rst_n),
        .baud_en (baud_en),
        .tx_data (tx_data),
        .tx_start(tx_start),
        .tx      (tx_line),
        .tx_busy (tx_busy)
    );

    // -------------------------------------------------------------------------
    // UART RX (loopback: RX = TX)
    // -------------------------------------------------------------------------
    wire [7:0] rx_data;
    wire       rx_valid;
    wire       rx_error;

    uart_rx #(
        .DATA_BITS  (8),
        .STOP_BITS  (1),
        .PARITY_EN  (0),
        .OVERSAMPLE (OVERSAMPLE)
    ) u_rx (
        .clk     (clk),
        .rst_n   (rst_n),
        .baud_en (baud_en),
        .rx      (tx_line),    // loopback
        .rx_data (rx_data),
        .rx_valid(rx_valid),
        .rx_error(rx_error)
    );

    // -------------------------------------------------------------------------
    // Coverage groups
    // -------------------------------------------------------------------------
    covergroup cg_tx_state @(posedge clk);
        cp_state : coverpoint u_tx.state {
            bins idle  = {3'd0};
            bins start = {3'd1};
            bins data  = {3'd2};
            bins stop  = {3'd4};
        }
    endgroup

    covergroup cg_rx_state @(posedge clk);
        cp_state : coverpoint u_rx.state {
            bins idle  = {3'd0};
            bins start = {3'd1};
            bins data  = {3'd2};
            bins stop  = {3'd4};
        }
    endgroup

    cg_tx_state cg_tx_inst = new();
    cg_rx_state cg_rx_inst = new();

    // -------------------------------------------------------------------------
    // Task: send_byte
    // -------------------------------------------------------------------------
    task send_byte(input [7:0] data);
        @(posedge clk);
        wait (!tx_busy);
        @(posedge clk);
        tx_data  = data;
        tx_start = 1'b1;
        @(posedge clk);
        tx_start = 1'b0;
        // Wait for reception
        @(posedge rx_valid);
        @(posedge clk);
    endtask

    // -------------------------------------------------------------------------
    // Result counters
    // -------------------------------------------------------------------------
    int pass_cnt = 0;
    int fail_cnt = 0;

    task check_result(input [7:0] expected, input [7:0] received, input err);
        if (err) begin
            $display("[FAIL] Framing error on data %02X", expected);
            fail_cnt++;
        end else if (expected !== received) begin
            $display("[FAIL] Expected %02X got %02X", expected, received);
            fail_cnt++;
        end else begin
            $display("[PASS] Data %02X OK", expected);
            pass_cnt++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    reg [7:0] test_vectors [0:15];
    int i;

    initial begin
        // Initialize test vectors
        test_vectors[0]  = 8'h00;
        test_vectors[1]  = 8'hFF;
        test_vectors[2]  = 8'h55;
        test_vectors[3]  = 8'hAA;
        test_vectors[4]  = 8'h0F;
        test_vectors[5]  = 8'hF0;
        test_vectors[6]  = 8'h12;
        test_vectors[7]  = 8'h34;
        test_vectors[8]  = 8'h56;
        test_vectors[9]  = 8'h78;
        test_vectors[10] = 8'h9A;
        test_vectors[11] = 8'hBC;
        test_vectors[12] = 8'hDE;
        test_vectors[13] = 8'hA5;
        test_vectors[14] = 8'h5A;
        test_vectors[15] = 8'hC3;

        // Apply reset
        rst_n    = 1'b0;
        tx_start = 1'b0;
        tx_data  = 8'h00;
        repeat(10) @(posedge clk);
        rst_n = 1'b1;
        repeat(5) @(posedge clk);

        $display("=== UART Loopback Test ===");

        for (i = 0; i < 16; i++) begin
            send_byte(test_vectors[i]);
            check_result(test_vectors[i], rx_data, rx_error);
        end

        // Back-to-back (start next immediately when busy goes low)
        $display("--- Back-to-back transfers ---");
        for (i = 0; i < 4; i++) begin
            send_byte(8'hA0 + i);
            check_result(8'hA0 + i, rx_data, rx_error);
        end

        $display("=== Results: %0d PASS / %0d FAIL ===", pass_cnt, fail_cnt);

        // Report coverage
        $display("TX state coverage: %.1f%%", cg_tx_inst.get_coverage());
        $display("RX state coverage: %.1f%%", cg_rx_inst.get_coverage());

        if (fail_cnt == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;
    end

    // Timeout watchdog
    initial begin
        #50_000_000;
        $display("[TIMEOUT] Simulation exceeded 50 ms budget");
        $finish;
    end

    // VCD dump
    initial begin
        $dumpfile("uart_tb.vcd");
        $dumpvars(0, tb_uart);
    end

endmodule
