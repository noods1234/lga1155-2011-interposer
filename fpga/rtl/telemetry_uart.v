// telemetry_uart.v — UART Transmitter for Telemetry Output
//
// Status     : [Verified design pattern; unverified on target hardware]
// Credibility: [Verified] — standard 8N1 UART TX; well-known design
//
// Purpose:
//   Outputs a byte stream from the FPGA to a USB-UART bridge on the interposer
//   for real-time observation of SMBus transactions and FPGA state on a host PC.
//
// Format: 8N1 (8 data bits, no parity, 1 stop bit)
// Baud rate: set by CLK_HZ and BAUD_RATE parameters
//
// Usage:
//   Assert tx_valid_i for one clk_i cycle with tx_data_i set to the byte to send.
//   tx_ready_o is high when the UART is idle and can accept a new byte.
//   If tx_valid_i is asserted while tx_ready_o is low, the byte is lost.
//   Caller is responsible for checking tx_ready_o before asserting tx_valid_i.
//
// Parameters:
//   CLK_HZ    : System clock frequency in Hz (default 50 MHz)
//   BAUD_RATE : UART baud rate (default 115200)

`default_nettype none
`timescale 1ns / 1ps

module telemetry_uart #(
    parameter integer CLK_HZ    = 50_000_000,
    parameter integer BAUD_RATE = 115_200
) (
    input  wire       clk_i,
    input  wire       rst_i,

    // TX interface
    input  wire       tx_valid_i,   // strobe: latch tx_data_i and start transmission
    input  wire [7:0] tx_data_i,    // byte to transmit
    output reg        tx_ready_o,   // 1 = idle, ready to accept new byte

    // UART physical output
    output reg        uart_tx_o     // to USB-UART bridge RXD pin
);

    // -------------------------------------------------------------------------
    // Baud rate generator
    // -------------------------------------------------------------------------
    localparam integer BAUD_DIV = CLK_HZ / BAUD_RATE;
    // Verify at synthesis: BAUD_DIV must be an integer (no fractional part matters
    // for accuracy < 2%). For 50 MHz / 115200: BAUD_DIV = 434. Error ≈ 0.08%.

    reg [$clog2(BAUD_DIV)-1:0] baud_cnt;
    reg                         baud_tick;  // one clk_i pulse per baud period

    always @(posedge clk_i) begin
        if (rst_i) begin
            baud_cnt  <= 0;
            baud_tick <= 1'b0;
        end else if (baud_cnt == BAUD_DIV - 1) begin
            baud_cnt  <= 0;
            baud_tick <= 1'b1;
        end else begin
            baud_cnt  <= baud_cnt + 1;
            baud_tick <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Transmit shift register
    // -------------------------------------------------------------------------
    // Frame: [START=0] [D0..D7] [STOP=1]  = 10 bits total
    reg [9:0] tx_shift;   // {stop, d7..d0, start}
    reg [3:0] tx_bits;    // number of bits remaining to send

    localparam ST_IDLE = 1'b0;
    localparam ST_SEND = 1'b1;
    reg tx_state;

    always @(posedge clk_i) begin
        if (rst_i) begin
            tx_shift   <= 10'h3FF;  // all ones = idle (STOP/mark)
            tx_bits    <= 4'd0;
            tx_state   <= ST_IDLE;
            tx_ready_o <= 1'b1;
            uart_tx_o  <= 1'b1;    // UART idle = HIGH
        end else begin
            case (tx_state)
                ST_IDLE: begin
                    uart_tx_o  <= 1'b1;
                    tx_ready_o <= 1'b1;
                    if (tx_valid_i) begin
                        // Load frame: start bit, 8 data bits, stop bit
                        tx_shift   <= {1'b1, tx_data_i, 1'b0}; // [9]=stop [8:1]=data [0]=start
                        tx_bits    <= 4'd10;
                        tx_state   <= ST_SEND;
                        tx_ready_o <= 1'b0;
                    end
                end

                ST_SEND: begin
                    if (baud_tick) begin
                        uart_tx_o <= tx_shift[0];     // LSB first
                        tx_shift  <= {1'b1, tx_shift[9:1]}; // shift right, fill with 1
                        if (tx_bits == 4'd1) begin
                            tx_state   <= ST_IDLE;
                            tx_ready_o <= 1'b1;
                            tx_bits    <= 4'd0;
                        end else begin
                            tx_bits <= tx_bits - 4'd1;
                        end
                    end
                end

                default: tx_state <= ST_IDLE;
            endcase
        end
    end

endmodule
`default_nettype wire
