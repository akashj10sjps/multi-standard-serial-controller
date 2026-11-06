// =============================================================================
// Module  : i2c_master.v
// Project : Multi-Standard Serial Communication Controller
// Author  : akashj10sjps
// Date    : 2026-11-06
//
// Description:
//   I2C Master controller (100 kHz / 400 kHz selectable via DIVISOR).
//   Implements the full I2C state machine:
//     START → Address+R/W → ACK → Data byte(s) → ACK/NACK → STOP
//
//   The SCL and SDA lines are open-drain; pull-ups are assumed externally.
//   i2c_sda_oe drives the SDA output-enable of an IOBUF primitive:
//     when i2c_sda_oe = 1 → drive SDA low  (open-drain 0)
//     when i2c_sda_oe = 0 → release SDA     (pull-up → 1)
//
// Signals:
//   start_xfer   – pulse to initiate a transfer
//   rw           – 0 = write, 1 = read
//   dev_addr     – 7-bit slave address
//   reg_addr     – 8-bit internal register address sent after dev_addr
//   tx_data      – byte to write (write transaction)
//   rx_data      – byte received (read transaction)
//   rx_valid     – pulsed when rx_data is valid
//   ack_error    – asserted if slave NACKs
//   busy         – high during transaction
// =============================================================================

`timescale 1ns/1ps

module i2c_master #(
    parameter CLK_DIV = 250   // SCL half-period in clk cycles  (100 MHz / 400 kHz / 2 = 125)
)(
    input  wire        clk,
    input  wire        rst_n,

    // User interface
    input  wire        start_xfer,
    input  wire        rw,
    input  wire [6:0]  dev_addr,
    input  wire [7:0]  reg_addr,
    input  wire [7:0]  tx_data,
    output reg  [7:0]  rx_data,
    output reg         rx_valid,
    output reg         ack_error,
    output reg         busy,

    // I2C bus (open-drain)
    output reg         i2c_scl,
    inout  wire        i2c_sda
);

    // -------------------------------------------------------------------------
    // SDA open-drain control
    // -------------------------------------------------------------------------
    reg sda_oe;      // 1 = drive low, 0 = release (pull-up = 1)
    reg sda_out;

    assign i2c_sda = (sda_oe) ? 1'b0 : 1'bz;
    wire   sda_in  = i2c_sda;   // read-back (may be pulled low by slave)

    // -------------------------------------------------------------------------
    // State machine encoding
    // -------------------------------------------------------------------------
    localparam [4:0]
        S_IDLE        = 5'd0,
        S_START       = 5'd1,
        S_ADDR        = 5'd2,     // 7-bit dev addr + RW
        S_ADDR_ACK    = 5'd3,
        S_REG         = 5'd4,     // 8-bit reg addr
        S_REG_ACK     = 5'd5,
        S_WRITE       = 5'd6,
        S_WRITE_ACK   = 5'd7,
        S_RESTART     = 5'd8,     // repeated START for read
        S_RADDR       = 5'd9,     // re-send dev_addr with R=1
        S_RADDR_ACK   = 5'd10,
        S_READ        = 5'd11,
        S_READ_NACK   = 5'd12,    // master NACKs last byte
        S_STOP        = 5'd13;

    reg [4:0]  state;
    reg [7:0]  shift;             // shift register
    reg [2:0]  bit_cnt;           // counts 7 downto 0
    reg [8:0]  clk_cnt;           // half-period counter
    reg        scl_en;            // SCL high phase enable

    // -------------------------------------------------------------------------
    // SCL generation helper
    // -------------------------------------------------------------------------
    // scl_rise / scl_fall are single-cycle pulses aligned to CLK_DIV boundaries
    reg scl_phase;   // 0 = SCL low half, 1 = SCL high half
    wire scl_toggle;
    assign scl_toggle = (clk_cnt == CLK_DIV - 1);

    always @(posedge clk) begin
        if (!rst_n) begin
            clk_cnt   <= 9'd0;
            scl_phase <= 1'b0;
            i2c_scl   <= 1'b1;
        end else if (busy) begin
            if (clk_cnt == CLK_DIV - 1) begin
                clk_cnt   <= 9'd0;
                scl_phase <= ~scl_phase;
                if (scl_en)
                    i2c_scl <= scl_phase;   // toggle on boundary
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
            end
        end else begin
            clk_cnt   <= 9'd0;
            scl_phase <= 1'b0;
            i2c_scl   <= 1'b1;
        end
    end

    wire scl_rise = scl_toggle & ~scl_phase;   // rising edge of SCL
    wire scl_fall = scl_toggle &  scl_phase;   // falling edge of SCL

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            sda_oe    <= 1'b0;
            scl_en    <= 1'b0;
            busy      <= 1'b0;
            ack_error <= 1'b0;
            rx_valid  <= 1'b0;
            rx_data   <= 8'h00;
            shift     <= 8'h00;
            bit_cnt   <= 3'd7;
        end else begin
            rx_valid  <= 1'b0;
            ack_error <= 1'b0;

            case (state)
                // ---------------------------------------------------------
                S_IDLE: begin
                    sda_oe <= 1'b0;
                    scl_en <= 1'b0;
                    busy   <= 1'b0;
                    if (start_xfer) begin
                        busy   <= 1'b1;
                        scl_en <= 1'b1;
                        state  <= S_START;
                    end
                end

                // ---------------------------------------------------------
                // START: SDA falls while SCL is high
                S_START: begin
                    if (scl_rise) begin
                        sda_oe <= 1'b1;   // pull SDA low = START
                    end
                    if (scl_fall) begin
                        // SCL goes low; prepare address byte
                        shift   <= {dev_addr, rw};
                        bit_cnt <= 3'd7;
                        state   <= S_ADDR;
                    end
                end

                // ---------------------------------------------------------
                S_ADDR: begin
                    if (scl_fall) begin
                        sda_oe  <= ~shift[7];   // MSB first
                        shift   <= shift << 1;
                        if (bit_cnt == 3'd0)
                            state <= S_ADDR_ACK;
                        else
                            bit_cnt <= bit_cnt - 1'b1;
                    end
                end

                S_ADDR_ACK: begin
                    if (scl_fall) sda_oe <= 1'b0;   // release SDA for ACK
                    if (scl_rise) begin
                        if (sda_in) ack_error <= 1'b1;   // NACK
                        // Always proceed (simplification; real impl would retry/STOP)
                        shift   <= reg_addr;
                        bit_cnt <= 3'd7;
                        state   <= S_REG;
                    end
                end

                // ---------------------------------------------------------
                S_REG: begin
                    if (scl_fall) begin
                        sda_oe  <= ~shift[7];
                        shift   <= shift << 1;
                        if (bit_cnt == 3'd0)
                            state <= S_REG_ACK;
                        else
                            bit_cnt <= bit_cnt - 1'b1;
                    end
                end

                S_REG_ACK: begin
                    if (scl_fall) sda_oe <= 1'b0;
                    if (scl_rise) begin
                        if (sda_in) ack_error <= 1'b1;
                        if (rw == 1'b0) begin
                            shift   <= tx_data;
                            bit_cnt <= 3'd7;
                            state   <= S_WRITE;
                        end else begin
                            state <= S_RESTART;
                        end
                    end
                end

                // ---------------------------------------------------------
                S_WRITE: begin
                    if (scl_fall) begin
                        sda_oe  <= ~shift[7];
                        shift   <= shift << 1;
                        if (bit_cnt == 3'd0)
                            state <= S_WRITE_ACK;
                        else
                            bit_cnt <= bit_cnt - 1'b1;
                    end
                end

                S_WRITE_ACK: begin
                    if (scl_fall) sda_oe <= 1'b0;
                    if (scl_rise) begin
                        if (sda_in) ack_error <= 1'b1;
                        state <= S_STOP;
                    end
                end

                // ---------------------------------------------------------
                // Repeated START for read
                S_RESTART: begin
                    if (scl_rise) sda_oe <= 1'b0;   // SDA high before repeat START
                    if (scl_fall) begin
                        sda_oe  <= 1'b1;              // SDA falls = repeated START
                        shift   <= {dev_addr, 1'b1};  // R/W = 1
                        bit_cnt <= 3'd7;
                        state   <= S_RADDR;
                    end
                end

                S_RADDR: begin
                    if (scl_fall) begin
                        sda_oe  <= ~shift[7];
                        shift   <= shift << 1;
                        if (bit_cnt == 3'd0)
                            state <= S_RADDR_ACK;
                        else
                            bit_cnt <= bit_cnt - 1'b1;
                    end
                end

                S_RADDR_ACK: begin
                    if (scl_fall) sda_oe <= 1'b0;
                    if (scl_rise) begin
                        if (sda_in) ack_error <= 1'b1;
                        bit_cnt <= 3'd7;
                        state   <= S_READ;
                    end
                end

                // ---------------------------------------------------------
                S_READ: begin
                    if (scl_rise) begin
                        shift <= {shift[6:0], sda_in};   // sample MISO
                    end
                    if (scl_fall & bit_cnt == 3'd0) begin
                        rx_data  <= {shift[6:0], sda_in};
                        rx_valid <= 1'b1;
                        state    <= S_READ_NACK;
                    end else if (scl_fall) begin
                        bit_cnt <= bit_cnt - 1'b1;
                    end
                end

                S_READ_NACK: begin
                    if (scl_fall) sda_oe <= 1'b1;   // master NACKs (SDA high = no ACK)
                    if (scl_rise)
                        state <= S_STOP;
                end

                // ---------------------------------------------------------
                S_STOP: begin
                    if (scl_fall) sda_oe <= 1'b1;   // SDA low before STOP
                    if (scl_rise) begin
                        sda_oe <= 1'b0;              // SDA rises while SCL high = STOP
                        scl_en <= 1'b0;
                        busy   <= 1'b0;
                        state  <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
