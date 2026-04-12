// smbus_monitor.v — Passive SMBus / I2C Transaction Monitor
//
// Status     : [Verified design; unverified on target hardware]
// Credibility: [Inference] — standard SMBus state machine; not yet tested on iMac12,2 Z68 bus
//
// Purpose:
//   Observes SMBus (SCL + SDA) transactions without driving the bus.
//   Reconstructs byte-by-byte transaction log including address phase, R/W bit,
//   ACK/NAK, and data bytes. Outputs to telemetry_uart or internal FIFO.
//
// Constraints:
//   - MUST be high-impedance on smb_scl_i and smb_sda_i at all times.
//   - smb_scl_i and smb_sda_i are inputs only. This module never drives them.
//   - System clock (clk_i) must be >= 16× the maximum SMBus clock frequency.
//     SMBus max: 400 kHz. Minimum clk_i: 6.4 MHz. Recommended: 50 MHz.
//   - SDA and SCL inputs must be synchronized to clk_i domain before this module.
//     Use a 2-FF synchronizer upstream. This module does NOT include synchronizers.
//
// Outputs:
//   byte_valid_o  : pulses high for one clk_i cycle when byte_data_o is valid
//   byte_data_o   : captured byte (address or data)
//   is_addr_o     : high when the byte is the address byte of a new transaction
//   is_read_o     : high when the address phase indicates a read transaction
//   got_ack_o     : high when the master received ACK from slave for this byte
//   start_o       : pulses on START condition detection
//   stop_o        : pulses on STOP condition detection
//
// Limitations:
//   - Does not handle SMBus block reads / PEC CRC verification.
//   - Does not detect clock stretching (SCL held low by slave) as an error.
//   - Repeated START is treated as a new START event.

`default_nettype none
`timescale 1ns / 1ps

module smbus_monitor #(
    parameter CLK_DIV = 125   // clk_i cycles per SMBus bit period / 4 for edge detection
                              // At 50 MHz clk and 400 kHz SMBus: 50e6 / 400e3 / 4 = 31.25 → 31
                              // Default 125 assumes 50 MHz clk / 100 kHz SMBus / 4
) (
    input  wire clk_i,        // system clock (synchronized; see constraints)
    input  wire rst_i,        // synchronous reset, active high

    // SMBus inputs — MUST be 2-FF synchronized before connecting here
    input  wire smb_scl_i,
    input  wire smb_sda_i,

    // Transaction outputs
    output reg        byte_valid_o,
    output reg  [7:0] byte_data_o,
    output reg        is_addr_o,
    output reg        is_read_o,
    output reg        got_ack_o,

    // Condition flags
    output reg        start_o,
    output reg        stop_o
);

    // -------------------------------------------------------------------------
    // Edge detection: detect SCL rising/falling, SDA changes
    // -------------------------------------------------------------------------
    reg scl_d, sda_d;

    always @(posedge clk_i) begin
        if (rst_i) begin
            scl_d <= 1'b1;
            sda_d <= 1'b1;
        end else begin
            scl_d <= smb_scl_i;
            sda_d <= smb_sda_i;
        end
    end

    wire scl_rise = smb_scl_i & ~scl_d;
    wire scl_fall = ~smb_scl_i & scl_d;
    wire sda_rise = smb_sda_i & ~sda_d;
    wire sda_fall = ~smb_sda_i & sda_d;

    // START: SDA falls while SCL is high
    wire start_cond = sda_fall & smb_scl_i;
    // STOP:  SDA rises while SCL is high
    wire stop_cond  = sda_rise & smb_scl_i;

    // -------------------------------------------------------------------------
    // State machine
    // -------------------------------------------------------------------------
    localparam ST_IDLE      = 3'd0;  // waiting for START
    localparam ST_ADDR      = 3'd1;  // receiving address + R/W bit (8 bits total)
    localparam ST_ADDR_ACK  = 3'd2;  // waiting for address ACK bit
    localparam ST_DATA      = 3'd3;  // receiving data byte
    localparam ST_DATA_ACK  = 3'd4;  // waiting for data ACK/NAK bit

    reg [2:0] state;
    reg [2:0] bit_cnt;    // counts bits received in current byte (0–7)
    reg [7:0] shift_reg;  // shift register for current byte
    reg       in_addr;    // 1 if currently receiving address byte
    reg       rd_flag;    // latched R/W bit from address byte

    always @(posedge clk_i) begin
        if (rst_i) begin
            state       <= ST_IDLE;
            bit_cnt     <= 3'd0;
            shift_reg   <= 8'h00;
            in_addr     <= 1'b0;
            rd_flag     <= 1'b0;
            byte_valid_o <= 1'b0;
            byte_data_o  <= 8'h00;
            is_addr_o    <= 1'b0;
            is_read_o    <= 1'b0;
            got_ack_o    <= 1'b0;
            start_o      <= 1'b0;
            stop_o       <= 1'b0;
        end else begin
            // Default pulse outputs to 0 each cycle
            byte_valid_o <= 1'b0;
            start_o      <= 1'b0;
            stop_o       <= 1'b0;

            // START and STOP are detectable in any state
            if (start_cond) begin
                state    <= ST_ADDR;
                bit_cnt  <= 3'd0;
                in_addr  <= 1'b1;
                start_o  <= 1'b1;
            end else if (stop_cond) begin
                state   <= ST_IDLE;
                stop_o  <= 1'b1;
            end else begin
                case (state)
                    ST_IDLE: begin
                        // Nothing to do; waiting for START
                    end

                    ST_ADDR, ST_DATA: begin
                        // Sample SDA on SCL rising edge
                        if (scl_rise) begin
                            shift_reg <= {shift_reg[6:0], smb_sda_i};
                            if (bit_cnt == 3'd7) begin
                                // Full byte received
                                bit_cnt <= 3'd0;
                                if (state == ST_ADDR) begin
                                    // shift_reg[0] is the R/W bit
                                    rd_flag <= smb_sda_i; // last bit shifted in = R/W
                                    state   <= ST_ADDR_ACK;
                                end else begin
                                    state <= ST_DATA_ACK;
                                end
                            end else begin
                                bit_cnt <= bit_cnt + 3'd1;
                            end
                        end
                    end

                    ST_ADDR_ACK: begin
                        // Sample ACK on SCL rising edge; ACK = SDA low
                        if (scl_rise) begin
                            byte_valid_o <= 1'b1;
                            // Address byte: bits [7:1] = 7-bit address, bit [0] = R/W
                            byte_data_o  <= shift_reg;
                            is_addr_o    <= 1'b1;
                            is_read_o    <= shift_reg[0];
                            got_ack_o    <= ~smb_sda_i; // ACK = SDA pulled low
                            state        <= ST_DATA;
                            in_addr      <= 1'b0;
                        end
                    end

                    ST_DATA_ACK: begin
                        if (scl_rise) begin
                            byte_valid_o <= 1'b1;
                            byte_data_o  <= shift_reg;
                            is_addr_o    <= 1'b0;
                            is_read_o    <= rd_flag;
                            got_ack_o    <= ~smb_sda_i;
                            state        <= ST_DATA;
                        end
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
`default_nettype wire
