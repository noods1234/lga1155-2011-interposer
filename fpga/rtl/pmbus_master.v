// pmbus_master.v — PMBus / SVID Observer Stub
//
// Status     : NON_FUNCTIONAL — PLACEHOLDER MODULE
// Credibility: [Hypothesis] — PMBus monitoring concept; zero implementation
//
// ============================================================================
// THIS MODULE IS NOT IMPLEMENTED.
// ============================================================================
//
// It exists as a structural placeholder so the top-level entity can be
// synthesized and the module boundary is reserved.
//
// What PMBus / SVID monitoring would require (future work):
//   - SVID (Serial Voltage Identification) is a proprietary Intel protocol
//     used between the CPU and the Voltage Regulator Module (VRM).
//   - It operates at a higher speed than SMBus (up to 40 MHz for Intel SVID2).
//   - Monitoring SVID would reveal real-time CPU voltage requests and power
//     throttling events.
//   - SVID uses a different physical layer from SMBus (differential, SVID2).
//   - Passively tapping SVID without disrupting VRM regulation is non-trivial.
//
// Risks:
//   - Any disturbance on SVID during CPU operation can cause VRM malfunction,
//     CPU undervolt, or system crash.
//   - Do NOT connect this module to any live signal until a full design review
//     is completed and the SVID protocol specification is obtained.
//
// Gate condition for implementation:
//   - SVID protocol specification (Intel VR12/VR13/IMVP8) obtained
//   - Stage 1 complete
//   - Separate risk register entry for SVID tap reviewed and accepted
//
// Until then, this module outputs a fixed inactive state.

`default_nettype none
`timescale 1ns / 1ps

module pmbus_master (
    input  wire clk_i,
    input  wire rst_i,

    // PMBus / SVID tap inputs — DO NOT CONNECT to live signals
    input  wire svid_clk_i,    // INVALID — NOT CONNECTED
    input  wire svid_data_i,   // INVALID — NOT CONNECTED

    // Telemetry output — always outputs 0 (no data)
    output wire tel_byte_valid_o,
    output wire [7:0] tel_byte_data_o
);

    // All outputs are tied off — this module does nothing
    assign tel_byte_valid_o = 1'b0;
    assign tel_byte_data_o  = 8'h00;

    // Inputs are intentionally unused — synthesis warning expected and acceptable
    // synthesis off
    // Suppress "input unused" warnings for placeholder ports:
    wire _unused = clk_i | rst_i | svid_clk_i | svid_data_i;
    // synthesis on

endmodule
`default_nettype wire
