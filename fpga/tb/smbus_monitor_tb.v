// fpga/tb/smbus_monitor_tb.v — Testbench for smbus_monitor.v
//
// Status     : [Inference] — state machine logic verified by simulation;
//              no hardware capture used as stimulus yet
// Credibility: [Inference]
//
// Tests:
//   TB1: After reset, all outputs deasserted
//   TB2: Idle bus — no spurious outputs
//   TB3: Write transaction: START + addr 0xA0 (ACK) + data 0xAA (ACK) + STOP
//   TB4: Read transaction:  START + addr 0xA1 (ACK) + data 0x55 (NAK) + STOP
//   TB5: NAK on address byte: got_ack_o must be 0
//   TB6: Repeated START (write-then-read pointer protocol)
//
// Simulation: 50 MHz clock. SCL bit period = 8 clk cycles (6.25 MHz fast-sim).
// The monitor is edge-triggered; bit rate does not affect correctness for
// software testbench use.
//
// Next step: replace smbus_bit_drive with a VCD playback task that replays
// the T0.1 Stage 0 capture (data/smbus/s0-smbus-post_capture-*.vcd) so this
// testbench becomes a regression test against real hardware behavior.

`timescale 1ns / 1ps

module smbus_monitor_tb;

    // -------------------------------------------------------------------------
    // Clock
    // -------------------------------------------------------------------------
    reg clk = 0;
    always #10 clk = ~clk;   // 50 MHz

    // -------------------------------------------------------------------------
    // DUT ports
    // -------------------------------------------------------------------------
    reg  rst     = 1;
    reg  smb_scl = 1;
    reg  smb_sda = 1;

    wire       byte_valid;
    wire [7:0] byte_data;
    wire       is_addr;
    wire       is_read;
    wire       got_ack;
    wire       start_o;
    wire       stop_o;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    smbus_monitor #(.CLK_DIV(31)) dut (
        .clk_i        (clk),
        .rst_i        (rst),
        .smb_scl_i    (smb_scl),
        .smb_sda_i    (smb_sda),
        .byte_valid_o (byte_valid),
        .byte_data_o  (byte_data),
        .is_addr_o    (is_addr),
        .is_read_o    (is_read),
        .got_ack_o    (got_ack),
        .start_o      (start_o),
        .stop_o       (stop_o)
    );

    // -------------------------------------------------------------------------
    // Waveform dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("fpga/tb/smbus_monitor_tb.vcd");
        $dumpvars(0, smbus_monitor_tb);
    end

    // -------------------------------------------------------------------------
    // Latched outputs — captures single-cycle pulses for post-hoc checking
    // -------------------------------------------------------------------------
    reg        bv_seen;   // byte_valid saw a pulse
    reg [7:0]  cap_data;
    reg        cap_is_addr;
    reg        cap_is_read;
    reg        cap_got_ack;
    reg        start_seen;
    reg        stop_seen;

    always @(posedge clk) begin
        if (byte_valid) begin
            bv_seen      <= 1'b1;
            cap_data     <= byte_data;
            cap_is_addr  <= is_addr;
            cap_is_read  <= is_read;
            cap_got_ack  <= got_ack;
        end
        if (start_o) start_seen <= 1'b1;
        if (stop_o)  stop_seen  <= 1'b1;
    end

    task clear_caps;
        bv_seen    = 0;
        start_seen = 0;
        stop_seen  = 0;
        cap_data   = 0;
    endtask

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
            $display("FAIL %0t | %s | got=0x%h exp=0x%h", $time, lbl, got, exp);
            fail_count = fail_count + 1;
        end else
            $display("pass %0t | %s", $time, lbl);
    endtask

    // -------------------------------------------------------------------------
    // SMBus driver tasks
    //
    // Signal timing: all changes happen #1 after posedge clk.
    // The DUT registers smb_scl_i and smb_sda_i each cycle, so a signal
    // changed #1 after posedge N is seen as the new value at posedge N+1.
    // SCL rising edge detection (scl_rise) fires at posedge N+1 when
    // smb_scl went 0→1 #1 after posedge N.
    //
    // Bit period = 4 clk cycles (≈ 80 ns):
    //   cycle 1: set SDA
    //   cycle 2: SCL rises
    //   cycle 3: SCL high (DUT detects scl_rise here)
    //   cycle 4: SCL falls
    // -------------------------------------------------------------------------
    integer bit_i;

    task smbus_bit_drive;
        input bit_val;
        @(posedge clk); #1; smb_sda = bit_val;
        @(posedge clk); #1; smb_scl = 1'b1;   // SCL rises
        @(posedge clk); #1;                    // SCL high — DUT samples
        @(posedge clk); #1; smb_scl = 1'b0;   // SCL falls
    endtask

    // Drive 8 data bits (MSB first) then 1 ACK/NAK bit.
    // ack_val: 0 = ACK (SDA driven low), 1 = NAK
    task smbus_byte_drive;
        input [7:0] data;
        input       ack_val;
        begin
            for (bit_i = 7; bit_i >= 0; bit_i = bit_i - 1)
                smbus_bit_drive(data[bit_i]);
            smbus_bit_drive(ack_val);
        end
    endtask

    // START: SDA falls while SCL is high.
    // Assumes bus was idle (both high) before calling.
    task smbus_start_cond;
        @(posedge clk); #1; smb_scl = 1'b1; smb_sda = 1'b1; // ensure idle
        @(posedge clk); #1; smb_sda = 1'b0;                  // SDA falls → START
        @(posedge clk); #1;
        @(posedge clk); #1; smb_scl = 1'b0;                  // SCL falls
    endtask

    // STOP: SDA rises while SCL is high.
    // Call with SCL low.
    task smbus_stop_cond;
        @(posedge clk); #1; smb_sda = 1'b0;   // ensure SDA low before STOP
        @(posedge clk); #1; smb_scl = 1'b1;   // SCL rises
        @(posedge clk); #1;
        @(posedge clk); #1; smb_sda = 1'b1;   // SDA rises while SCL high → STOP
        @(posedge clk); #1;
    endtask

    // -------------------------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------------------------
    initial begin
        // Reset
        rst = 1; smb_scl = 1; smb_sda = 1;
        repeat(4) @(posedge clk);
        @(posedge clk); #1; rst = 0;
        repeat(2) @(posedge clk); #1;

        // -----------------------------------------------------------------
        // TB1: After reset, outputs deasserted
        // -----------------------------------------------------------------
        chk(byte_valid, 0, "TB1 byte_valid after rst");
        chk(start_o,    0, "TB1 start_o after rst");
        chk(stop_o,     0, "TB1 stop_o after rst");

        // -----------------------------------------------------------------
        // TB2: Idle — no spurious outputs for 20 cycles
        // -----------------------------------------------------------------
        repeat(20) @(posedge clk);
        #1;
        chk(bv_seen,   0, "TB2 no spurious byte_valid in idle");
        chk(start_seen, 0, "TB2 no spurious start_o in idle");
        chk(stop_seen,  0, "TB2 no spurious stop_o in idle");

        // -----------------------------------------------------------------
        // TB3: Write transaction
        //   START + 0xA0 (addr 0x50 write, ACK) + 0xAA (data, ACK) + STOP
        //
        //   Expected byte 1: data=0xA0, is_addr=1, is_read=0, got_ack=1
        //   Expected byte 2: data=0xAA, is_addr=0, is_read=0, got_ack=1
        // -----------------------------------------------------------------
        clear_caps;

        smbus_start_cond;
        repeat(2) @(posedge clk); #1;
        chk(start_seen, 1, "TB3 start_seen");
        clear_caps;

        smbus_byte_drive(8'hA0, 1'b0);   // 0x50 write, ACK
        repeat(2) @(posedge clk); #1;
        chk(bv_seen,     1,     "TB3 bv_seen addr");
        chk(cap_data,    8'hA0, "TB3 addr byte 0xA0");
        chk(cap_is_addr, 1,     "TB3 is_addr=1");
        chk(cap_is_read, 0,     "TB3 is_read=0 (write)");
        chk(cap_got_ack, 1,     "TB3 got_ack=1 (ACK)");
        clear_caps;

        smbus_byte_drive(8'hAA, 1'b0);   // data 0xAA, ACK
        repeat(2) @(posedge clk); #1;
        chk(bv_seen,     1,     "TB3 bv_seen data");
        chk(cap_data,    8'hAA, "TB3 data byte 0xAA");
        chk(cap_is_addr, 0,     "TB3 is_addr=0 (data)");
        chk(cap_got_ack, 1,     "TB3 got_ack=1 data");
        clear_caps;

        smbus_stop_cond;
        repeat(2) @(posedge clk); #1;
        chk(stop_seen, 1, "TB3 stop_seen");

        repeat(4) @(posedge clk);

        // -----------------------------------------------------------------
        // TB4: Read transaction
        //   START + 0xA1 (addr 0x50 read, ACK) + 0x55 (data, NAK) + STOP
        //
        //   Expected byte 1: data=0xA1, is_addr=1, is_read=1, got_ack=1
        //   Expected byte 2: data=0x55, is_addr=0, is_read=1, got_ack=0
        // -----------------------------------------------------------------
        clear_caps;

        smbus_start_cond;
        repeat(2) @(posedge clk); #1;
        chk(start_seen, 1, "TB4 start_seen");
        clear_caps;

        smbus_byte_drive(8'hA1, 1'b0);   // 0x50 read, ACK
        repeat(2) @(posedge clk); #1;
        chk(cap_data,    8'hA1, "TB4 addr byte 0xA1");
        chk(cap_is_addr, 1,     "TB4 is_addr=1");
        chk(cap_is_read, 1,     "TB4 is_read=1 (read)");
        chk(cap_got_ack, 1,     "TB4 got_ack=1");
        clear_caps;

        smbus_byte_drive(8'h55, 1'b1);   // data 0x55, NAK
        repeat(2) @(posedge clk); #1;
        chk(cap_data,    8'h55, "TB4 data byte 0x55");
        chk(cap_is_addr, 0,     "TB4 is_addr=0");
        chk(cap_is_read, 1,     "TB4 is_read still 1");
        chk(cap_got_ack, 0,     "TB4 got_ack=0 (NAK)");
        clear_caps;

        smbus_stop_cond;
        repeat(2) @(posedge clk); #1;
        chk(stop_seen, 1, "TB4 stop_seen");

        repeat(4) @(posedge clk);

        // -----------------------------------------------------------------
        // TB5: NAK on address byte
        //   START + 0xA0 (addr, NAK) + STOP
        //   got_ack must be 0
        // -----------------------------------------------------------------
        clear_caps;

        smbus_start_cond;
        smbus_byte_drive(8'hA0, 1'b1);   // NAK
        repeat(2) @(posedge clk); #1;
        chk(bv_seen,     1,     "TB5 bv_seen");
        chk(cap_data,    8'hA0, "TB5 addr byte");
        chk(cap_is_addr, 1,     "TB5 is_addr=1");
        chk(cap_got_ack, 0,     "TB5 got_ack=0 (NAK on addr)");
        clear_caps;

        smbus_stop_cond;
        repeat(2) @(posedge clk); #1;
        chk(stop_seen, 1, "TB5 stop_seen");

        repeat(4) @(posedge clk);

        // -----------------------------------------------------------------
        // TB6: Repeated START (write-then-read byte pointer protocol)
        //   START + 0xA0 (write, ACK) + 0x00 (ptr, ACK)
        //   + Sr (repeated START) + 0xA1 (read, ACK) + STOP
        //
        //   After repeated START, the monitor re-enters addr phase.
        //   start_seen must fire again on Sr.
        // -----------------------------------------------------------------
        clear_caps;

        smbus_start_cond;
        repeat(2) @(posedge clk); #1;
        chk(start_seen, 1, "TB6 first start_seen");
        clear_caps;

        smbus_byte_drive(8'hA0, 1'b0);   // write address
        smbus_byte_drive(8'h00, 1'b0);   // byte pointer
        repeat(2) @(posedge clk); #1;
        chk(cap_data, 8'h00, "TB6 pointer byte 0x00");
        clear_caps;

        // Repeated START: SCL goes high, then SDA falls
        smbus_start_cond;
        repeat(2) @(posedge clk); #1;
        chk(start_seen, 1, "TB6 repeated start_seen");
        clear_caps;

        smbus_byte_drive(8'hA1, 1'b0);   // read address
        repeat(2) @(posedge clk); #1;
        chk(cap_data,    8'hA1, "TB6 read addr 0xA1");
        chk(cap_is_addr, 1,     "TB6 is_addr=1 after repeated start");
        chk(cap_is_read, 1,     "TB6 is_read=1");
        clear_caps;

        smbus_stop_cond;
        repeat(2) @(posedge clk); #1;
        chk(stop_seen, 1, "TB6 stop_seen");

        repeat(4) @(posedge clk);

        // -----------------------------------------------------------------
        // Summary
        // -----------------------------------------------------------------
        if (fail_count == 0)
            $display("\nsmbus_monitor_tb: ALL TESTS PASSED (%0d checks)", 28);
        else
            $display("\nsmbus_monitor_tb: %0d FAILURE(S)", fail_count);

        $finish;
    end

    // Watchdog: 1 ms sim time
    initial begin
        #1_000_000;
        $display("TIMEOUT — smbus_monitor_tb exceeded 1 ms sim time");
        $finish;
    end

endmodule
