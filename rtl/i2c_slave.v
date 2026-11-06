// =============================================================================
// Module  : i2c_slave.v
// Project : Multi-Standard Serial Communication Controller
// Author  : akashj10sjps
// Date    : 2026-11-06
//
// Description:
//   I2C Slave controller.  Monitors the I2C bus for its own address and
//   responds to read/write transactions.  An 8-entry × 8-bit register file
//   is provided; the host selects a register address in the first byte
//   after addressing.
//
//   Open-drain SDA:
//     sda_oe = 1 → drive low (pull-up externally = 0 on bus)
//     sda_oe = 0 → release  (pull-up = 1 on bus)
//
// Parameters:
//   SLAVE_ADDR – 7-bit I2C address (default 7'h48)
// =============================================================================

`timescale 1ns/1ps

module i2c_slave #(
    parameter [6:0] SLAVE_ADDR = 7'h48
)(
    input  wire       clk,
    input  wire       rst_n,

    // I2C bus
    input  wire       i2c_scl,
    inout  wire       i2c_sda,

    // Register file access from internal logic
    input  wire [2:0] reg_sel,
    input  wire [7:0] reg_wdata,
    input  wire       reg_we,
    output wire [7:0] reg_rdata
);

    // -------------------------------------------------------------------------
    // SDA open-drain
    // -------------------------------------------------------------------------
    reg  sda_oe;
    assign i2c_sda = sda_oe ? 1'b0 : 1'bz;
    wire sda_in = i2c_sda;

    // -------------------------------------------------------------------------
    // Synchronize SCL and SDA inputs (double-flop)
    // -------------------------------------------------------------------------
    reg scl_s0, scl_s1, scl_prev;
    reg sda_s0, sda_s1, sda_prev;

    always @(posedge clk) begin
        if (!rst_n) begin
            scl_s0 <= 1'b1; scl_s1 <= 1'b1; scl_prev <= 1'b1;
            sda_s0 <= 1'b1; sda_s1 <= 1'b1; sda_prev <= 1'b1;
        end else begin
            scl_s0 <= i2c_scl; scl_s1 <= scl_s0; scl_prev <= scl_s1;
            sda_s0 <= sda_in;  sda_s1 <= sda_s0; sda_prev <= sda_s1;
        end
    end

    wire scl_rise =  scl_s1 & ~scl_prev;
    wire scl_fall = ~scl_s1 &  scl_prev;
    // START: SDA falls while SCL high
    wire i2c_start = scl_s1 & sda_prev & ~sda_s1;
    // STOP:  SDA rises while SCL high
    wire i2c_stop  = scl_s1 & ~sda_prev & sda_s1;

    // -------------------------------------------------------------------------
    // Internal register file
    // -------------------------------------------------------------------------
    reg [7:0] regfile [0:7];
    integer k;

    always @(posedge clk) begin
        if (!rst_n) begin
            for (k = 0; k < 8; k = k + 1)
                regfile[k] <= 8'h00;
        end else if (reg_we) begin
            regfile[reg_sel] <= reg_wdata;
        end
    end

    assign reg_rdata = regfile[reg_sel];

    // -------------------------------------------------------------------------
    // State machine
    // -------------------------------------------------------------------------
    localparam [3:0]
        S_IDLE       = 4'd0,
        S_ADDR       = 4'd1,
        S_ADDR_ACK   = 4'd2,
        S_REG_ADDR   = 4'd3,
        S_REG_ACK    = 4'd4,
        S_WRITE_DATA = 4'd5,
        S_WRITE_ACK  = 4'd6,
        S_READ_DATA  = 4'd7,
        S_READ_ACK   = 4'd8;

    reg [3:0] state;
    reg [7:0] shift;
    reg [2:0] bit_cnt;
    reg       rw_bit;
    reg [2:0] reg_ptr;
    reg [7:0] rd_shift;

    always @(posedge clk) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            sda_oe  <= 1'b0;
            shift   <= 8'h00;
            bit_cnt <= 3'd7;
            rw_bit  <= 1'b0;
            reg_ptr <= 3'd0;
            rd_shift<= 8'h00;
        end else begin
            if (i2c_start) begin
                state   <= S_ADDR;
                bit_cnt <= 3'd7;
                sda_oe  <= 1'b0;
            end else if (i2c_stop) begin
                state  <= S_IDLE;
                sda_oe <= 1'b0;
            end else begin
                case (state)
                    // ---------------------------------------------------------
                    S_IDLE: ;   // wait for START

                    // ---------------------------------------------------------
                    S_ADDR: begin
                        if (scl_rise) begin
                            shift <= {shift[6:0], sda_s1};
                            if (bit_cnt == 3'd0) begin
                                rw_bit  <= sda_s1;
                                bit_cnt <= 3'd7;
                                state   <= S_ADDR_ACK;
                            end else begin
                                bit_cnt <= bit_cnt - 1'b1;
                            end
                        end
                    end

                    S_ADDR_ACK: begin
                        if (scl_fall) begin
                            // Check address match (shift[7:1] holds the 7-bit addr)
                            if (shift[7:1] == SLAVE_ADDR)
                                sda_oe <= 1'b1;   // ACK
                            else begin
                                sda_oe <= 1'b0;   // NACK – not our address
                                state  <= S_IDLE;
                            end
                        end
                        if (scl_rise) begin
                            sda_oe <= 1'b0;
                            state  <= (rw_bit) ? S_READ_DATA : S_REG_ADDR;
                            bit_cnt<= 3'd7;
                        end
                    end

                    // ---------------------------------------------------------
                    S_REG_ADDR: begin
                        if (scl_rise) begin
                            shift <= {shift[6:0], sda_s1};
                            if (bit_cnt == 3'd0) begin
                                reg_ptr <= shift[2:0];   // lower 3 bits = reg index
                                state   <= S_REG_ACK;
                            end else begin
                                bit_cnt <= bit_cnt - 1'b1;
                            end
                        end
                    end

                    S_REG_ACK: begin
                        if (scl_fall) sda_oe <= 1'b1;   // ACK
                        if (scl_rise) begin
                            sda_oe  <= 1'b0;
                            bit_cnt <= 3'd7;
                            state   <= S_WRITE_DATA;
                        end
                    end

                    // ---------------------------------------------------------
                    S_WRITE_DATA: begin
                        if (scl_rise) begin
                            shift <= {shift[6:0], sda_s1};
                            if (bit_cnt == 3'd0) begin
                                state <= S_WRITE_ACK;
                            end else begin
                                bit_cnt <= bit_cnt - 1'b1;
                            end
                        end
                    end

                    S_WRITE_ACK: begin
                        if (scl_fall) begin
                            // Write to register file
                            regfile[reg_ptr] <= shift;
                            sda_oe <= 1'b1;   // ACK
                        end
                        if (scl_rise) begin
                            sda_oe  <= 1'b0;
                            bit_cnt <= 3'd7;
                            state   <= S_IDLE;   // single-byte write
                        end
                    end

                    // ---------------------------------------------------------
                    S_READ_DATA: begin
                        // Load register on first bit
                        if (bit_cnt == 3'd7 && scl_fall)
                            rd_shift <= regfile[reg_ptr];
                        if (scl_fall) begin
                            sda_oe  <= ~rd_shift[7];   // MSB first (open-drain: 0 → drive)
                            rd_shift<= rd_shift << 1;
                            if (bit_cnt == 3'd0)
                                state <= S_READ_ACK;
                            else
                                bit_cnt <= bit_cnt - 1'b1;
                        end
                    end

                    S_READ_ACK: begin
                        if (scl_fall) sda_oe <= 1'b0;   // release for master ACK/NACK
                        if (scl_rise) state <= S_IDLE;
                    end

                    default: state <= S_IDLE;
                endcase
            end
        end
    end

endmodule
