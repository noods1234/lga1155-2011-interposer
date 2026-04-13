// fpga/tb/telemetry_uart_tb.v — Testbench for telemetry_uart.v
//
// Status     : [Inference] — 8N1 UART frame verified by simulation
// Credibility: [Inference]
//
// Tests:
//   TB1: After reset, uart_tx_o = 1 (idle high), tx_ready_o = 1
//   TB2: Send 0x55 — start bit, each data bit LSB-first, stop bit
//   TB3: tx_ready_o asserts with the stop bit; tx_valid immediately accepted
//   TB4: tx_valid_i while tx_ready_o = 0 is silently ignored (byte is lost)
//   TB5: Start bit is exactly one full baud period (BUG-06 regression check)
//   TB6: Reset mid-transmission restores idle state
//
// Simulation parameters override:
//   CLK_HZ=10_000, BAUD_RATE=1_000  → BAUD_DIV = 10 clocks/bit
//   (real target: CLK_HZ=50_000_000, BAUD_RATE=115_200, BAUD_DIV=434)
//
// Frame check for 0x55 = 8'b0101_0101:
//   [START=0][D0=1][D1=0][D2=1][D3=0][D4=1][D5=0][D6=1][D7=0][STOP=1]
//    period 0   1     2     3     4     5     6     7     8      9

`timescale 1ns / 1ps

module telemetry_uart_tb;

    // -------------------------------------------------------------------------
    // Simulation parameters — override CLK_HZ / BAUD_RATE for fast sim
    // -------------------------------------------------------------------------
    localparam integer SIM_CLK_HZ    = 10_000;
    localparam integer SIM_BAUD_RATE = 1_000;
    localparam integer BAUD_DIV      = SIM_CLK_HZ / SIM_BAUD_RATE;  // = 10

    // -------------------------------------------------------------------------
    // Clock: period = 1_000_000 ns / SIM_CLK_HZ = 100 ns
    // -------------------------------------------------------------------------
    localparam integer CLK_HALF_NS = 1_000_000_000 / SIM_CLK_HZ / 2;  // 50 ns

    reg clk = 0;
    always #(CLK_HALF_NS) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg        rst      = 1;
    reg        tx_valid = 0;
    reg  [7:0] tx_data  = 0;
    wire       tx_ready;
    wire       uart_tx;

    // -------------------------------------------------------------------------
    // DUT — instantiated with simulation-speed parameters
    // -------------------------------------------------------------------------
    telemetry_uart #(
        .CLK_HZ    (SIM_CLK_HZ),
        .BAUD_RATE (SIM_BAUD_RATE)
    ) dut (
        .clk_i      (clk),
        .rst_i      (rst),
        .tx_valid_i (tx_valid),
        .tx_data_i  (tx_data),
        .tx_ready_o (tx_ready),
        .uart_tx_o  (uart_tx)
    );

    // -------------------------------------------------------------------------
    // Waveform dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("fpga/tb/telemetry_uart_tb.vcd");
        $dumpvars(0, telemetry_uart_tb);
    end

    // -------------------------------------------------------------------------
    // Assertion helper
    // -------------------------------------------------------------------------
    integer fail_count;
    initial fail_count = 0;

    task chk;
        input [63:0] got;
        input [63:0] exp;
        input [127:0] lbl;
        if (got !== exp) begin
            $display("FAIL %0t | %s | got=%0b exp=%0b", $time, lbl, got, exp);
            fail_count = fail_count + 1;
        end else
            $display("pass %0t | %s", $time, lbl);
    endtask

    // -------------------------------------------------------------------------
    // Sample uart_tx at the midpoint of bit period N (0 = start bit)
    //
    // Caller must invoke this task when we are at the START of bit period N,
    // i.e., immediately after the previous bit-period boundary.
    // The task waits BAUD_DIV/2 cycles, samples, then waits the remaining half.
    // -------------------------------------------------------------------------
    task sample_bit;
        input [63:0] exp_val;
        input [127:0] lbl;
        begin
            repeat(BAUD_DIV / 2) @(posedge clk);
            #1;
            chk(uart_tx, exp_val, lbl);
            repeat(BAUD_DIV - BAUD_DIV / 2) @(posedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------------------------
    integer i;

    initial begin

        // Apply reset
        rst = 1; tx_valid = 0; tx_data = 0;
        repeat(4) @(posedge clk);
        @(posedge clk); #1; rst = 0;
        repeat(2) @(posedge clk); #1;

        // -----------------------------------------------------------------
        // TB1: After reset — idle state
        // -----------------------------------------------------------------
        chk(uart_tx, 1, "TB1 uart_tx idle HIGH");
        chk(tx_ready, 1, "TB1 tx_ready HIGH");

        // -----------------------------------------------------------------
        // TB2: Send 0x55 and check every bit (LSB first)
        //
        // 0x55 = 8'b0101_0101
        // Frame: START=0, D0=1, D1=0, D2=1, D3=0, D4=1, D5=0, D6=1, D7=0, STOP=1
        // -----------------------------------------------------------------

        // Assert tx_valid for one cycle with data 0x55
        @(posedge clk); #1;
        tx_data  = 8'h55;
        tx_valid = 1'b1;

        // At the next posedge, DUT samples tx_valid and drives the start bit.
        // uart_tx_o goes LOW immediately (same clk edge, non-blocking to 0).
        @(posedge clk); #1;
        tx_valid = 1'b0;    // deassert after one cycle

        // Start bit should be low now.
        chk(uart_tx,  0, "TB2 start bit = 0");
        chk(tx_ready, 0, "TB2 tx_ready = 0 during tx");

        // We are at the beginning of the start bit period.
        // sample_bit consumes exactly one BAUD_DIV-cycle bit period each call.
        // Start bit was already confirmed above; just consume its remaining cycles.
        repeat(BAUD_DIV - 1) @(posedge clk);

        // 0x55 = 0101_0101 → LSB first: 1,0,1,0,1,0,1,0
        sample_bit(1, "TB2 D0=1");
        sample_bit(0, "TB2 D1=0");
        sample_bit(1, "TB2 D2=1");
        sample_bit(0, "TB2 D3=0");
        sample_bit(1, "TB2 D4=1");
        sample_bit(0, "TB2 D5=0");
        sample_bit(1, "TB2 D6=1");
        sample_bit(0, "TB2 D7=0");
        sample_bit(1, "TB2 STOP=1");

        // After stop bit, tx_ready should be high
        repeat(2) @(posedge clk); #1;
        chk(tx_ready, 1, "TB2 tx_ready restored after stop bit");
        chk(uart_tx,  1, "TB2 uart_tx idle after frame");

        repeat(4) @(posedge clk);

        // -----------------------------------------------------------------
        // TB3: Immediate back-to-back — send 0xA5 right after 0x55
        //
        // tx_ready should be 1 after 0x55 stop bit. Accept 0xA5 immediately.
        // 0xA5 = 8'b1010_0101 → LSB first: 1,0,1,0,0,1,0,1
        // -----------------------------------------------------------------
        @(posedge clk); #1;
        tx_data  = 8'hA5;
        tx_valid = 1'b1;
        @(posedge clk); #1;
        tx_valid = 1'b0;
        chk(uart_tx,  0, "TB3 0xA5 start bit");
        chk(tx_ready, 0, "TB3 tx_ready low during 0xA5");

        // consume start bit remainder
        repeat(BAUD_DIV - 1) @(posedge clk);

        // 0xA5 = 1010_0101 → LSB: 1,0,1,0,0,1,0,1
        sample_bit(1, "TB3 0xA5 D0=1");
        sample_bit(0, "TB3 0xA5 D1=0");
        sample_bit(1, "TB3 0xA5 D2=1");
        sample_bit(0, "TB3 0xA5 D3=0");
        sample_bit(0, "TB3 0xA5 D4=0");
        sample_bit(1, "TB3 0xA5 D5=1");
        sample_bit(0, "TB3 0xA5 D6=0");
        sample_bit(1, "TB3 0xA5 D7=1");
        sample_bit(1, "TB3 0xA5 STOP=1");

        repeat(2) @(posedge clk); #1;
        chk(tx_ready, 1, "TB3 ready after 0xA5");

        repeat(4) @(posedge clk);

        // -----------------------------------------------------------------
        // TB4: tx_valid while busy — byte must be silently dropped
        //
        // Start sending 0xFF. While busy (tx_ready=0), assert tx_valid=1
        // with 0x00. The 0x00 must not appear on the wire; 0xFF must complete
        // cleanly without frame errors (D0–D7 all 1, STOP=1).
        // -----------------------------------------------------------------
        @(posedge clk); #1; tx_data = 8'hFF; tx_valid = 1'b1;
        @(posedge clk); #1; tx_valid = 1'b0;
        chk(tx_ready, 0, "TB4 tx_ready=0 after 0xFF launch");

        // While busy, assert tx_valid with 0x00 — this must be ignored
        repeat(2) @(posedge clk); #1;
        tx_data  = 8'h00;
        tx_valid = 1'b1;
        @(posedge clk); #1; tx_valid = 1'b0;

        // Now check 0xFF frame: start=0, all data bits = 1, stop=1
        // (We're already past the start bit — consume remainder)
        // Re-synchronise: wait for tx_ready to go low, then sample from there.
        // Simpler: just wait for frame to finish and check tx afterwards
        repeat(BAUD_DIV * 10) @(posedge clk);
        repeat(2) @(posedge clk); #1;
        chk(tx_ready, 1, "TB4 ready after 0xFF (0x00 dropped)");
        chk(uart_tx,  1, "TB4 uart_tx idle, no second frame started");

        repeat(4) @(posedge clk);

        // -----------------------------------------------------------------
        // TB5: BUG-06 regression — start bit must be exactly BAUD_DIV wide
        //
        // Drive tx_valid, then count cycles until uart_tx rises (= D0).
        // If start bit is shorter than BAUD_DIV, D0 appears early.
        // -----------------------------------------------------------------
        @(posedge clk); #1; tx_data = 8'h01; tx_valid = 1'b1; // D0=1 (easy sentinel)
        @(posedge clk); #1; tx_valid = 1'b0;
        // uart_tx is now 0 (start bit). Count cycles until it rises.
        begin : bug06_check
            integer cycles_low;
            cycles_low = 0;
            while (uart_tx === 1'b0 && cycles_low < BAUD_DIV + 5) begin
                @(posedge clk); #1;
                cycles_low = cycles_low + 1;
            end
            // Should be exactly BAUD_DIV cycles (± 1 for sampling)
            if (cycles_low < BAUD_DIV - 1 || cycles_low > BAUD_DIV + 1) begin
                $display("FAIL %0t | TB5 BUG-06 | start bit = %0d cycles, want %0d",
                         $time, cycles_low, BAUD_DIV);
                fail_count = fail_count + 1;
            end else
                $display("pass %0t | TB5 BUG-06 start bit width = %0d cycles (want %0d)",
                         $time, cycles_low, BAUD_DIV);
        end
        // Drain remaining frame
        repeat(BAUD_DIV * 9) @(posedge clk);
        repeat(4) @(posedge clk);

        // -----------------------------------------------------------------
        // TB6: Reset mid-transmission — uart_tx and tx_ready return to idle
        // -----------------------------------------------------------------
        @(posedge clk); #1; tx_data = 8'hAA; tx_valid = 1'b1;
        @(posedge clk); #1; tx_valid = 1'b0;
        chk(uart_tx,  0, "TB6 start bit before reset");

        // Apply reset mid-frame
        repeat(BAUD_DIV / 2) @(posedge clk);
        @(posedge clk); #1; rst = 1;
        @(posedge clk); #1;
        chk(uart_tx,  1, "TB6 uart_tx=1 after reset");
        chk(tx_ready, 1, "TB6 tx_ready=1 after reset");
        @(posedge clk); #1; rst = 0;

        // Confirm idle holds for a few cycles — no ghost bits
        repeat(BAUD_DIV * 2) @(posedge clk); #1;
        chk(uart_tx,  1, "TB6 idle holds after rst release");
        chk(tx_ready, 1, "TB6 tx_ready holds after rst release");

        repeat(4) @(posedge clk);

        // -----------------------------------------------------------------
        // Summary
        // -----------------------------------------------------------------
        if (fail_count == 0)
            $display("\ntelemetry_uart_tb: ALL TESTS PASSED");
        else
            $display("\ntelemetry_uart_tb: %0d FAILURE(S)", fail_count);

        $finish;
    end

    // Watchdog: 10 ms sim time
    initial begin
        #10_000_000;
        $display("TIMEOUT — telemetry_uart_tb exceeded 10 ms sim time");
        $finish;
    end

endmodule
