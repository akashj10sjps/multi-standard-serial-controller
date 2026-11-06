// =============================================================================
// Testbench : tb_i2c.sv
// Project   : Multi-Standard Serial Communication Controller
// Author    : akashj10sjps
// Date      : 2026-11-06
//
// Description:
//   SystemVerilog testbench for the I2C master + slave pair.
//   The master and slave share the same bi-directional SDA bus (pull-up
//   modelled with a wired-OR and a 1 kΩ pull-up represented by a weak-1).
//
//   Test scenarios:
//     1. Write transaction: master writes to slave register file
//     2. Read transaction:  master reads from slave register file
//     3. Verify data integrity after read-back
//     4. Address mismatch: slave should NACK
// =============================================================================

`timescale 1ns/1ps

module tb_i2c;

    // -------------------------------------------------------------------------
    // Clock & reset
    // -------------------------------------------------------------------------
    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    // -------------------------------------------------------------------------
    // I2C bus: wired-AND with weak pull-up
    // -------------------------------------------------------------------------
    wire i2c_scl_m;    // master drives SCL
    tri1 i2c_sda;      // wired-AND; slave + master can drive low; pull-up = 1

    // -------------------------------------------------------------------------
    // I2C Master
    // -------------------------------------------------------------------------
    reg        start_xfer;
    reg        rw;
    reg [6:0]  dev_addr;
    reg [7:0]  reg_addr;
    reg [7:0]  tx_data;
    wire [7:0] rx_data_m;
    wire       rx_valid_m;
    wire       ack_error;
    wire       busy_m;

    i2c_master #(.CLK_DIV(10)) u_master (
        .clk        (clk),
        .rst_n      (rst_n),
        .start_xfer (start_xfer),
        .rw         (rw),
        .dev_addr   (dev_addr),
        .reg_addr   (reg_addr),
        .tx_data    (tx_data),
        .rx_data    (rx_data_m),
        .rx_valid   (rx_valid_m),
        .ack_error  (ack_error),
        .busy       (busy_m),
        .i2c_scl    (i2c_scl_m),
        .i2c_sda    (i2c_sda)
    );

    // -------------------------------------------------------------------------
    // I2C Slave (address 0x48)
    // -------------------------------------------------------------------------
    wire [7:0] slave_rdata;
    reg  [2:0] slave_sel  = 3'd0;
    reg  [7:0] slave_wdat = 8'h00;
    reg        slave_we   = 1'b0;

    i2c_slave #(.SLAVE_ADDR(7'h48)) u_slave (
        .clk      (clk),
        .rst_n    (rst_n),
        .i2c_scl  (i2c_scl_m),
        .i2c_sda  (i2c_sda),
        .reg_sel  (slave_sel),
        .reg_wdata(slave_wdat),
        .reg_we   (slave_we),
        .reg_rdata(slave_rdata)
    );

    // -------------------------------------------------------------------------
    // Coverage
    // -------------------------------------------------------------------------
    covergroup cg_i2c_master @(posedge clk);
        cp_state : coverpoint u_master.state {
            bins idle       = {5'd0};
            bins start_s    = {5'd1};
            bins addr       = {5'd2};
            bins addr_ack   = {5'd3};
            bins reg_s      = {5'd4};
            bins reg_ack    = {5'd5};
            bins write      = {5'd6};
            bins write_ack  = {5'd7};
            bins restart    = {5'd8};
            bins raddr      = {5'd9};
            bins raddr_ack  = {5'd10};
            bins read_s     = {5'd11};
            bins read_nack  = {5'd12};
            bins stop_s     = {5'd13};
        }
    endgroup

    cg_i2c_master cg_m = new();

    // -------------------------------------------------------------------------
    // Helper tasks
    // -------------------------------------------------------------------------
    int pass_cnt = 0;
    int fail_cnt = 0;

    task i2c_write(input [6:0] addr, input [7:0] reg_a, input [7:0] data);
        wait (!busy_m);
        @(posedge clk);
        dev_addr   = addr;
        reg_addr   = reg_a;
        tx_data    = data;
        rw         = 1'b0;
        start_xfer = 1'b1;
        @(posedge clk);
        start_xfer = 1'b0;
        wait (!busy_m);
        @(posedge clk);
    endtask

    task i2c_read(input [6:0] addr, input [7:0] reg_a, output [7:0] data);
        wait (!busy_m);
        @(posedge clk);
        dev_addr   = addr;
        reg_addr   = reg_a;
        rw         = 1'b1;
        start_xfer = 1'b1;
        @(posedge clk);
        start_xfer = 1'b0;
        @(posedge rx_valid_m);
        data = rx_data_m;
        @(posedge clk);
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    reg [7:0] rd_val;

    initial begin
        rst_n      = 1'b0;
        start_xfer = 1'b0;
        rw         = 1'b0;
        dev_addr   = 7'h00;
        reg_addr   = 8'h00;
        tx_data    = 8'h00;
        repeat(20) @(posedge clk);
        rst_n = 1'b1;
        repeat(10) @(posedge clk);

        $display("=== I2C Master-Slave Test ===");

        // ---- Write test ----
        $display("--- Write Transactions ---");
        i2c_write(7'h48, 8'h01, 8'hCA);
        i2c_write(7'h48, 8'h02, 8'hFE);
        i2c_write(7'h48, 8'h03, 8'hBE);
        i2c_write(7'h48, 8'h04, 8'hEF);

        // ---- Read back and verify ----
        $display("--- Read Transactions ---");
        i2c_read(7'h48, 8'h01, rd_val);
        if (rd_val === 8'hCA) begin $display("[PASS] Reg01 = %02X", rd_val); pass_cnt++; end
        else begin $display("[FAIL] Reg01: got %02X exp CA", rd_val); fail_cnt++; end

        i2c_read(7'h48, 8'h02, rd_val);
        if (rd_val === 8'hFE) begin $display("[PASS] Reg02 = %02X", rd_val); pass_cnt++; end
        else begin $display("[FAIL] Reg02: got %02X exp FE", rd_val); fail_cnt++; end

        // ---- ACK error (wrong address) ----
        $display("--- Address Mismatch Test ---");
        i2c_write(7'h50, 8'h00, 8'hFF);
        if (ack_error) begin $display("[PASS] ACK error on wrong address"); pass_cnt++; end
        else           begin $display("[FAIL] Expected ACK error"); fail_cnt++; end

        $display("=== Results: %0d PASS / %0d FAIL ===", pass_cnt, fail_cnt);
        $display("I2C Master coverage: %.1f%%", cg_m.get_coverage());

        if (fail_cnt == 0) $display("ALL I2C TESTS PASSED");
        else               $display("SOME I2C TESTS FAILED");

        $finish;
    end

    initial begin
        #20_000_000;
        $display("[TIMEOUT]");
        $finish;
    end

    initial begin
        $dumpfile("i2c_tb.vcd");
        $dumpvars(0, tb_i2c);
    end

endmodule
