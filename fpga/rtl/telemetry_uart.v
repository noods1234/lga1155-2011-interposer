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
//
// Frame format:
//   [START=0][D0..D7][STOP=1] — 10 bit periods, LSB first
//
// Bug fixed (BUG-06):
//   Previous version used a free-running baud counter in a separate always
//   block. When tx_valid_i fired, the start bit was driven but the first
//   data bit could appear as few as 1 clock cycle later (if a baud tick was
//   imminent), producing a start bit shorter than one baud period and causing
//   guaranteed UART framing errors on back-to-back bytes.
//
//   Fix: baud counter and TX state machine are merged into one always block.
//   When tx_valid_i is detected, uart_tx_o is immediately driven low (start
//   bit) AND baud_cnt is reset to 0, ensuring the first data bit (D0) appears
//   exactly BAUD_DIV clock cycles later — giving the start bit a full period.

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
    output reg        uart_tx_o     // to USB-UART bridge RXD pin (idle HIGH)
);

    // -------------------------------------------------------------------------
    // Baud rate
    // -------------------------------------------------------------------------
    localparam integer BAUD_DIV = CLK_HZ / BAUD_RATE;
    // For 50 MHz / 115200 = 434. Baud error = 0.06/434 ≈ 0.008% per bit,
    // accumulating to 0.08% over 10 bits — well within ±2% UART tolerance.
    // If using non-default parameters, verify that the resulting error is < 2%.

    localparam ST_IDLE = 1'b0;
    localparam ST_SEND = 1'b1;

    // tx_shift: 9 bits = {stop=1, d7..d0}
    // The start bit is driven directly (uart_tx_o <= 0) when tx_valid_i fires;
    // these 9 bits are the remaining bits sent on successive baud ticks.
    reg [$clog2(BAUD_DIV)-1:0] baud_cnt;
    reg [8:0]                   tx_shift;
    reg [3:0]                   tx_bits;   // bits remaining after start bit
    reg                         tx_state;

    // -------------------------------------------------------------------------
    // Combined baud counter + TX state machine
    //
    // The baud counter and TX state machine share one always block so that
    // baud_cnt can be reset atomically with the start-bit assertion, preventing
    // a variable-length start bit.
    // -------------------------------------------------------------------------
    always @(posedge clk_i) begin
        if (rst_i) begin
            baud_cnt   <= 0;
            tx_shift   <= 9'h1FF;   // all ones — idle state
            tx_bits    <= 4'd0;
            tx_state   <= ST_IDLE;
            tx_ready_o <= 1'b1;
            uart_tx_o  <= 1'b1;     // UART idle = HIGH (mark state)
        end else begin
            case (tx_state)
                ST_IDLE: begin
                    uart_tx_o  <= 1'b1;
                    tx_ready_o <= 1'b1;
                    if (tx_valid_i) begin
                        // Drive start bit immediately. Reset baud counter so
                        // D0 appears exactly BAUD_DIV cycles from this edge,
                        // giving the start bit a guaranteed full baud period.
                        uart_tx_o  <= 1'b0;
                        baud_cnt   <= 0;
                        tx_shift   <= {1'b1, tx_data_i};  // [8]=stop, [7:0]=data
                        tx_bits    <= 4'd9;                // 9 bits after start
                        tx_state   <= ST_SEND;
                        tx_ready_o <= 1'b0;
                    end else begin
                        // Free-run counter while idle.
                        if (baud_cnt == BAUD_DIV - 1)
                            baud_cnt <= 0;
                        else
                            baud_cnt <= baud_cnt + 1;
                    end
                end

                ST_SEND: begin
                    if (baud_cnt == BAUD_DIV - 1) begin
                        baud_cnt  <= 0;
                        uart_tx_o <= tx_shift[0];             // LSB first
                        tx_shift  <= {1'b1, tx_shift[8:1]};  // shift right, fill 1
                        if (tx_bits == 4'd1) begin
                            // Stop bit just scheduled; return to idle next cycle
                            tx_state   <= ST_IDLE;
                            tx_ready_o <= 1'b1;
                            tx_bits    <= 4'd0;
                        end else begin
                            tx_bits <= tx_bits - 4'd1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                default: begin
                    tx_state <= ST_IDLE;
                    baud_cnt <= 0;
                end
            endcase
        end
    end

endmodule
`default_nettype wire
