// smbus_arbiter.v — SMBus Pass-Through Gate / Arbiter
//
// Status     : [Hypothesis — logic designed; not yet tested on target hardware]
// Credibility: [Inference] — I2C/SMBus clock stretching and bus isolation pattern
//
// Purpose:
//   Sits in the SMBus signal path between the PCH (master side) and the DIMM
//   SPD EEPROMs (slave side). In pass-through mode it behaves as a transparent
//   wire. In gate mode it can hold SCL low to pause a transaction (clock
//   stretching), allowing the FPGA to inspect or substitute a response.
//
// WARNING — HARDWARE RISK:
//   This module drives sl_scl_o, sl_sda_o, and ms_sda_o. Connecting it to a live SMBus
//   while FPGA configuration is incomplete will place undefined logic levels on
//   the bus. This MUST be protected by an upstream hardware mux that defaults
//   to direct pass-through until the FPGA is fully configured and this module
//   asserts arb_ready_o.
//
//   See risk register R-007 and R-009 before any live system use.
//
// Operating modes:
//   gate_en_i = 0  →  transparent pass-through; FPGA does not drive the bus
//   gate_en_i = 1  →  arbiter active; may hold SCL low or substitute SDA
//
// Ports:
//   Master side (from PCH / SMBus master):
//     ms_scl_i, ms_sda_i      — inputs from master
//     ms_sda_o                — SDA output toward master (slave ACK / injected data)
//     NOTE: There is no ms_scl_o. SCL is master-driven; the FPGA does not
//     drive SCL back toward the master. Clock stretching (pulling SCL low
//     toward the slave) is a future capability via sl_scl_o.
//   Slave side (toward DIMM SPD EEPROMs):
//     sl_scl_o, sl_sda_o      — outputs toward slave
//     sl_sda_i                — SDA input from slave (slave response)
//
// I2C bus note:
//   SCL and SDA are open-drain. In pass-through mode this module must NOT drive
//   them high; it must release them (tri-state or drive 1 through open-drain).
//   The outputs here are active-low drive signals for open-drain buffers.
//   External hardware is responsible for pull-up resistors and open-drain drivers.
//   out = 0 means "drive low"; out = 1 means "release (let pull-up win)".

`default_nettype none
`timescale 1ns / 1ps

module smbus_arbiter (
    input  wire clk_i,        // system clock
    input  wire rst_i,        // synchronous reset, active high
    input  wire gate_en_i,    // 0 = pass-through, 1 = arbiter active

    // Master-side signals (synchronized externally with 2-FF sync)
    input  wire ms_scl_i,
    input  wire ms_sda_i,

    // Slave-side SDA input (synchronized externally)
    input  wire sl_sda_i,

    // Outputs — open-drain drive signals (0 = pull low, 1 = release)
    output reg  ms_sda_o,     // toward master (to report slave ACK/data)
    output reg  sl_scl_o,     // toward slave SCL
    output reg  sl_sda_o,     // toward slave SDA

    // Internal inject interface (from spd_responder or test logic)
    input  wire inject_sda_i, // SDA value to inject toward master when arb is active
    input  wire inject_en_i,  // 1 = use inject_sda_i instead of sl_sda_i

    // Status
    output reg  arb_ready_o,  // 1 = module initialized and safe to connect to bus
    output reg  scl_held_o    // 1 = we are holding SCL low (clock stretching)
);

    // -------------------------------------------------------------------------
    // Initialization guard: arb_ready_o is deasserted until the module has been
    // through at least one full reset sequence. External mux must default to
    // direct pass-through until arb_ready_o is asserted.
    // -------------------------------------------------------------------------
    reg [3:0] init_cnt;

    always @(posedge clk_i) begin
        if (rst_i) begin
            init_cnt    <= 4'd0;
            arb_ready_o <= 1'b0;
        end else if (!arb_ready_o) begin
            if (init_cnt == 4'd15)
                arb_ready_o <= 1'b1;
            else
                init_cnt <= init_cnt + 4'd1;
        end
    end

    // -------------------------------------------------------------------------
    // Pass-through logic
    // -------------------------------------------------------------------------
    // When gate is disabled or not ready: transparent wire.
    // When gate is enabled: SCL pass-through, SDA injected if inject_en is set.
    //
    // NOTE: Clock stretching (holding SCL low) is intentionally NOT implemented
    // in this initial version. It is listed here as a future capability stub.
    // The current implementation only selects between slave SDA and injected SDA.
    // Full SCL stretching requires careful timing to avoid SMBus timeout (25 ms).

    always @(posedge clk_i) begin
        if (rst_i) begin
            sl_scl_o    <= 1'b1;   // release
            sl_sda_o    <= 1'b1;   // release
            ms_sda_o    <= 1'b1;   // release
            scl_held_o  <= 1'b0;
        end else if (!arb_ready_o || !gate_en_i) begin
            // Pass-through: mirror master SCL to slave, slave SDA to master
            sl_scl_o   <= ms_scl_i;
            sl_sda_o   <= ms_sda_i;
            ms_sda_o   <= sl_sda_i;
            scl_held_o <= 1'b0;
        end else begin
            // Gate active: SCL always passes through (stretch not yet implemented)
            sl_scl_o   <= ms_scl_i;
            sl_sda_o   <= ms_sda_i;
            scl_held_o <= 1'b0;

            // SDA toward master: use injected or real slave response
            if (inject_en_i)
                ms_sda_o <= inject_sda_i;
            else
                ms_sda_o <= sl_sda_i;
        end
    end

    // -------------------------------------------------------------------------
    // FUTURE CAPABILITY STUB: Clock stretching
    // When implemented, this block will hold sl_scl_o low after a falling SCL
    // edge, giving the FPGA time to inject a response before SCL rises again.
    // NOT YET IMPLEMENTED. Tracked in bringup-plan.md Stage 1 task list.
    // -------------------------------------------------------------------------
    // [PLACEHOLDER — clock stretch logic goes here]

endmodule
`default_nettype wire
