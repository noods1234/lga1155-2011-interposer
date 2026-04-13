# FPGA Module Specifications

**Status**: [Inference] — interfaces defined from design; not yet tested on hardware
**RTL location**: `fpga/rtl/`
**Testbench location**: `fpga/tb/` (not yet written — see testbench plans below)

This document is the contract between modules. Any port change in RTL must be
reflected here first and reviewed before synthesis. Any parameter change that
affects timing must update the assumptions section of all dependent modules.

---

## Integration Map

```
                    ┌──────────────────────────────────────┐
                    │           FPGA Top-Level              │
   SMBus bus ──────>│  smbus_monitor ───────────────────>  │──> telemetry_uart ──> UART TX
  (SCL, SDA)        │       │ byte stream                   │
                    │       ▼                               │
                    │  spd_responder ──> inject_sda/en ──> │
                    │                                       │
   SMBus master <──>│  smbus_arbiter <────────────────────  │
   (PCH side)       │       │                              │
   SMBus slave <────│       │                              │
   (DIMM side)      └──────────────────────────────────────┘

   pmbus_master: tied off, no connections (out of scope until Stage 3)
```

Signal path in monitoring mode (Stage 0–1):
- smbus_monitor observes SCL/SDA passively
- byte stream feeds spd_responder (address detection only; SDA injection disabled)
- byte stream also serialised by top-level logic to telemetry_uart
- smbus_arbiter in pass-through (gate_en_i=0); FPGA does not drive the bus

Signal path in emulation mode (Stage 2+, after SS_SEND_BYTE is implemented):
- smbus_arbiter gate_en_i=1
- spd_responder active_o gates inject_en_o
- inject_sda_o drives ms_sda_o toward PCH master

---

## Module 1: smbus_monitor

**File**: `fpga/rtl/smbus_monitor.v`
**Status**: Structural implementation complete. Not yet simulated. Not yet tested on hardware.
**Credibility**: [Inference]

### Purpose

Passive, read-only observer of the SMBus (I2C) bus. Reconstructs the byte
stream — address bytes, data bytes, ACK/NAK bits, START/STOP conditions —
from raw SCL/SDA signals. Outputs one byte at a time to downstream modules.
Never drives the bus under any condition.

### Ports

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk_i` | in | 1 | System clock. Must be ≥ 16× SMBus max frequency |
| `rst_i` | in | 1 | Synchronous reset, active high |
| `smb_scl_i` | in | 1 | SCL — must be 2-FF synchronized before this module |
| `smb_sda_i` | in | 1 | SDA — must be 2-FF synchronized before this module |
| `byte_valid_o` | out | 1 | Pulses high one cycle when `byte_data_o` is valid |
| `byte_data_o` | out | 8 | Captured byte; address byte has R/W in bit 0 |
| `is_addr_o` | out | 1 | High when byte is the address byte of a new transaction |
| `is_read_o` | out | 1 | High when transaction direction is master-read |
| `got_ack_o` | out | 1 | High when SDA was low during the ACK bit. On write transactions: slave ACK. On read transactions (master receives data): master ACK/NAK. spd_responder uses this to detect master NAK and end a read. |
| `start_o` | out | 1 | Pulses high on START condition |
| `stop_o` | out | 1 | Pulses high on STOP condition |

### Parameter

| Parameter | Default | Description |
|-----------|---------|-------------|
| `CLK_DIV` | 31 | clk_i cycles per SMBus bit period ÷ 4. At 50 MHz / 400 kHz ≈ 31. At 50 MHz / 100 kHz = 125. Override to match actual clock and bus speed. |

### Assumptions

- SCL and SDA are pre-synchronized (2-FF) to clk_i. No synchronizers inside this module.
- clk_i ≥ 16× SMBus clock frequency (minimum 6.4 MHz for 400 kHz bus; recommend 50 MHz).
- Bus follows standard I2C open-drain protocol: active-low drive, logic high = released.
- Repeated START is treated as a new START event (correct per SMBus spec section 3.1.4).

### Non-Goals

- Does not drive SCL or SDA under any condition.
- Does not handle SMBus PEC (CRC) verification.
- Does not detect clock stretching as a protocol error.
- Does not reassemble multi-byte register values — that is spd_responder's job.
- Does not buffer more than one byte — caller must consume byte_valid_o within one cycle.

### Failure Modes

| Symptom | Likely cause |
|---------|-------------|
| `byte_valid_o` never pulses | SCL/SDA not reaching FPGA input; or 2-FF sync missing |
| Address bytes captured but data missing | CLK_DIV too large — sampling rate too slow for bus speed |
| Spurious START/STOP pulses | SDA glitching on edges; check probe ground return path |
| Wrong bit values | CLK_DIV mismatch with actual bus speed; re-measure bus frequency first |

### Testbench Plan

**File**: `fpga/tb/smbus_monitor_tb.v` — **Stage 1 gate requirement; must exist before any live bus tap**

Minimum test cases:
1. Single-byte write to 0x50: assert byte_valid, is_addr, is_read=0, got_ack=1
2. Single-byte read from 0x50: assert is_read=1, correct data byte
3. Multi-byte read (3 bytes): three byte_valid pulses, auto-advancing data, NAK on last
4. START → immediate STOP (no data): start_o then stop_o; no byte_valid
5. Repeated START mid-transaction: second start_o pulse resets state; new address byte captured

**Replay-driven test**: After Stage 0 T0.1 produces
`data/smbus/s0-smbus-post_capture-YYYYMMDD-01.vcd`, use it as testbench
stimulus. The module's byte_valid/byte_data output sequence must match the
decoded transaction log from the logic analyzer exactly. This makes the
simulation a regression test against real hardware behavior.

---

## Module 2: smbus_arbiter

**File**: `fpga/rtl/smbus_arbiter.v`
**Status**: Pass-through logic implemented. Clock stretching is a labeled stub — not implemented. Not yet simulated.
**Credibility**: [Inference]

### Purpose

Sits in the SMBus signal path between the PCH master and DIMM slave side.
In pass-through mode: transparent wire. In gate mode: allows SDA injection
toward the master (used by spd_responder to respond with emulated SPD bytes).
Asserts `arb_ready_o` after reset to signal the external hardware mux that
the FPGA is initialized and safe to connect.

### Ports

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk_i` | in | 1 | System clock |
| `rst_i` | in | 1 | Synchronous reset, active high |
| `gate_en_i` | in | 1 | 0 = pass-through, 1 = arbiter active |
| `ms_scl_i` | in | 1 | SCL from master (PCH) — pre-synchronized |
| `ms_sda_i` | in | 1 | SDA from master — pre-synchronized |
| `sl_sda_i` | in | 1 | SDA from slave (DIMM) — pre-synchronized |
| `ms_sda_o` | out | 1 | SDA toward master (open-drain drive signal) |
| `sl_scl_o` | out | 1 | SCL toward slave (open-drain drive signal) |
| `sl_sda_o` | out | 1 | SDA toward slave (open-drain drive signal) |
| `inject_sda_i` | in | 1 | SDA bit to inject toward master when arbiter active |
| `inject_en_i` | in | 1 | 1 = use inject_sda_i instead of sl_sda_i |
| `arb_ready_o` | out | 1 | 1 = module initialized, safe to connect to bus |
| `scl_held_o` | out | 1 | 1 = SCL held low (always 0 — stretch not implemented) |

**Open-drain convention**: output = 0 means "pull low"; output = 1 means "release
(let pull-up resistor win)". External open-drain buffers and pull-ups are required.
The FPGA itself must not source current onto the SMBus.

### Assumptions

- External hardware mux defaults to direct pass-through until `arb_ready_o` asserts.
  FPGA driving the bus before arb_ready_o risks undefined logic levels during
  SMBus transactions — see risk R-009.
- All inputs are pre-synchronized to clk_i domain.
- gate_en_i is only asserted after arb_ready_o is high.
- Only one inject source active at a time; no multi-master arbitration.

### Non-Goals

- Clock stretching (SCL hold) is not implemented. Labeled `PLACEHOLDER` in the RTL (smbus_arbiter.v line ~131).
- Does not detect SMBus timeout violations (25 ms maximum for clock stretching).
- Does not arbitrate between multiple FPGA modules injecting simultaneously.

### Failure Modes

| Symptom | Likely cause |
|---------|-------------|
| System hangs during POST | FPGA driving bus before arb_ready_o; check hardware mux default |
| Injected SDA not reaching master | inject_en_i or gate_en_i not asserted |
| Bus contention / slow edges | Open-drain buffer not matching spec; check pull-up value |
| `scl_held_o` always 0 | Expected — clock stretch not implemented |

### Testbench Plan

**File**: `fpga/tb/smbus_arbiter_tb.v` — required before connecting to live bus

Minimum test cases:
1. gate_en_i=0: verify sl_scl_o mirrors ms_scl_i; ms_sda_o mirrors sl_sda_i
2. gate_en_i=1, inject_en_i=0: SDA pass-through unchanged
3. gate_en_i=1, inject_en_i=1: ms_sda_o follows inject_sda_i, not sl_sda_i
4. Reset: arb_ready_o deasserted for exactly 16 cycles post-rst_i, then asserts
5. gate_en_i transition: no glitch on outputs at 0→1 and 1→0 edges

---

## Module 3: spd_responder

**File**: `fpga/rtl/spd_responder.v`
**Status**: Address detection and byte-pointer state machine implemented. `SS_SEND_BYTE` SDA output is NON_FUNCTIONAL — stub only. Not yet simulated.
**Credibility**: [Inference] for address/pointer logic; [Placeholder] for SDA bit output

### Purpose

Emulates a DDR3 SPD EEPROM (AT24C02) on the SMBus. Receives the byte stream
from smbus_monitor, detects its own I2C address, then drives `inject_en_o` and
`inject_sda_o` toward smbus_arbiter to respond with ROM data. ROM is loaded
from an external hex file at synthesis via `$readmemh` — never hard-coded.

### Ports

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk_i` | in | 1 | System clock |
| `rst_i` | in | 1 | Synchronous reset, active high |
| `mon_byte_valid_i` | in | 1 | From smbus_monitor: `byte_valid_o` |
| `mon_byte_data_i` | in | 8 | From smbus_monitor: `byte_data_o` |
| `mon_is_addr_i` | in | 1 | From smbus_monitor: `is_addr_o` |
| `mon_is_read_i` | in | 1 | From smbus_monitor: `is_read_o` |
| `mon_got_ack_i` | in | 1 | From smbus_monitor: `got_ack_o` |
| `mon_start_i` | in | 1 | From smbus_monitor: `start_o` |
| `mon_stop_i` | in | 1 | From smbus_monitor: `stop_o` |
| `smb_scl_i` | in | 1 | Raw SCL — reserved for bit-level timing when implemented |
| `inject_en_o` | out | 1 | To smbus_arbiter: `inject_en_i` |
| `inject_sda_o` | out | 1 | To smbus_arbiter: `inject_sda_i` |
| `active_o` | out | 1 | 1 = this instance is the currently addressed slave |

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DEVICE_ADDR` | `3'b000` | Slot select: 0=A1(wire byte 0xA0/0xA1), 1=A2(0xA2/0xA3), 2=B1(0xA4/0xA5), 3=B2(0xA6/0xA7). Note: the 7-bit I2C address is {4'b1010, DEVICE_ADDR[2:0]}; wire byte includes R/W in bit 0. |
| `SPD_HEX_FILE` | `"INVALID_NOT_SET.hex"` | Hex file path. **Must be overridden.** Synthesis will produce a zero ROM if left at default. |

### Address Match Logic

DDR3 SPD EEPROM I2C address per JEDEC 21C / AT24C02:
```
7-bit address = {4'b1010, DEVICE_ADDR[2:0]}
Address byte  = {4'b1010, DEVICE_ADDR[2:0], R/W}

Match condition:
    mon_byte_data_i[7:4] == 4'b1010
    mon_byte_data_i[3:1] == DEVICE_ADDR[2:0]
```
DEVICE_ADDR=0 → matches 0xA0 (write) or 0xA1 (read).
DEVICE_ADDR=1 → matches 0xA2 / 0xA3. Etc.

### Assumptions

- smbus_monitor byte stream is correct. Bad monitor output → bad responder behavior.
- `SPD_HEX_FILE` generated by `tools/spd-gen/generate_spd.py` and validated by
  `tools/spd-gen/validate_spd.py` before synthesis. Unvalidated hex is undefined behavior.
- MRC does not write SPD EEPROM during normal training. Read-only emulation is correct.
- ROM is synchronously accessible within one clk_i cycle — at 50 MHz and 400 kHz SMBus,
  there are ≥ 125 clk cycles per bit period. One-cycle ROM latency is safe.

### Non-Goals

- Does not emulate thermal sensor I2C address (0x18 | DEVICE_ADDR). Out of scope.
- Does not support EEPROM write operations.
- Does not implement WP pin.
- Bit-level SDA timing (`SS_SEND_BYTE`) is not implemented — see Known Gap below.

### Known Gap: SS_SEND_BYTE is NON_FUNCTIONAL

The current `SS_SEND_BYTE` state sets `inject_sda_o <= tx_byte[7]` — a static
value, not timed to SCL edges. A correct I2C slave implementation requires:

1. On each falling SCL edge: drive SDA with the current bit
2. Hold SDA stable during SCL high period
3. Advance to next bit on next SCL falling edge
4. On the 9th SCL falling edge: release SDA (wait for master ACK)

This requires a sub-byte SCL-tracking FSM driven by `smb_scl_i`. It is not
implemented. **Do not assert `inject_en_o` on a live bus until this is
implemented and passes simulation.** Current behavior would produce a static
SDA level during a read transaction — bus contention with the real DIMM.

### Failure Modes

| Symptom | Likely cause |
|---------|-------------|
| `active_o` never asserts | DEVICE_ADDR mismatch; or smbus_monitor not producing byte_valid |
| `active_o` asserts but no SDA output | Expected — SS_SEND_BYTE not implemented |
| ROM all zeros | SPD_HEX_FILE path wrong at synthesis; check `$readmemh` warning in build log |
| Bus contention during SPD read phase | inject_en_o enabled before SS_SEND_BYTE is implemented |

### Testbench Plan

**File**: `fpga/tb/spd_responder_tb.v` — **blocked until SS_SEND_BYTE is implemented**

Minimum test cases:
1. Write transaction to 0xA0 (DEVICE_ADDR=0): active_o asserts, byte_ptr latched from next byte
2. Read transaction to 0xA1: inject_en_o asserts; inject_sda_o outputs ROM byte bit-by-bit, timed to SCL
3. Sequential read, 4 bytes: byte_ptr auto-increments on each master ACK
4. Master NAK: inject_en_o deasserts; returns to idle; byte_ptr retained
5. STOP mid-read: clean return to idle

**Replay test**: use captured T0.1 VCD and T0.5 SPD binary together.
Feed VCD transactions to smbus_monitor model, pipe byte stream to spd_responder
(loaded with actual SPD hex from captured DIMM), verify that inject_sda sequence
matches the known SPD bytes byte-for-byte. This is the integration acceptance test.

---

## Module 4: pmbus_master

**File**: `fpga/rtl/pmbus_master.v`
**Status**: NON_FUNCTIONAL PLACEHOLDER. All outputs tied to 0. All inputs ignored.
**Credibility**: [Placeholder]

### Purpose

Placeholder for a future PMBus master that would communicate with the iMac12,2
voltage regulator controllers (ISL6392 or equivalent). Required for Stage 3+ if
active VID control or power rail telemetry is needed.

### Current State

No logic implemented. Interface not yet defined — the iMac12,2 VRM topology and
PMBus register map must be confirmed from Stage 0 hardware inspection before any
implementation begins.

Do not instantiate in any synthesis build targeting Stages 0–2.

### Testbench Plan

None until Stage 3 scope is confirmed and VRM specification is obtained.

---

## Module 5: telemetry_uart

**File**: `fpga/rtl/telemetry_uart.v`
**Status**: Implementation complete. Standard 8N1 UART TX — well-established pattern.
**Credibility**: [Verified design pattern] — not yet tested on this specific hardware

### Purpose

Streams bytes from the FPGA to a USB-UART adapter on the interposer PCB.
Used for real-time observation of SMBus transactions and FPGA state on a
host PC during Stage 0–2 experiments.

### Ports

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk_i` | in | 1 | System clock |
| `rst_i` | in | 1 | Synchronous reset, active high |
| `tx_valid_i` | in | 1 | Strobe: latch `tx_data_i` and start transmission (one cycle) |
| `tx_data_i` | in | 8 | Byte to transmit |
| `tx_ready_o` | out | 1 | 1 = idle and ready; 0 = busy |
| `uart_tx_o` | out | 1 | To USB-UART bridge RXD pin. 3.3 V TTL. Idle = high. |

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `CLK_HZ` | `50_000_000` | System clock frequency in Hz |
| `BAUD_RATE` | `115_200` | UART baud rate |

Baud divisor = CLK_HZ / BAUD_RATE. At defaults: 434. Accuracy ≈ 0.08% (within ±2% UART spec).
Frame format: [START=0][D0..D7][STOP=1] — 10 bits total, LSB first.

### Assumptions

- Caller checks `tx_ready_o` before asserting `tx_valid_i`. Bytes presented while busy are silently dropped.
- `tx_valid_i` is held high for exactly one `clk_i` cycle per byte.
- USB-UART bridge shares ground with FPGA. uart_tx_o → bridge RXD (not TX).

### Non-Goals

- No RX path. Telemetry is one-way outbound only.
- No flow control (CTS/RTS). Caller manages throughput via `tx_ready_o`.
- No parity bit. 8N1 only.

### Failure Modes

| Symptom | Likely cause |
|---------|-------------|
| No output on host | Ground not shared; or TX/RX wired backward at connector |
| Garbled output | `CLK_HZ` or `BAUD_RATE` parameter does not match actual values |
| Bytes dropped at high throughput | `tx_valid_i` asserted while `tx_ready_o=0`; add flow control in caller |
| Frame errors on host | Baud rate mismatch > ±2%; check `BAUD_DIV` in synthesis report |

### Testbench Plan

**File**: `fpga/tb/telemetry_uart_tb.v` — **Stage 1 gate requirement**

Minimum test cases:
1. Single byte: verify uart_tx_o shows correct 10-bit frame (start, D0–D7 LSB-first, stop)
2. Back-to-back bytes: tx_ready_o timing between frames; no gap in output
3. Busy rejection: assert tx_valid_i while tx_ready_o=0; verify no frame corruption
4. Baud accuracy: measure start-bit period on uart_tx_o; confirm within 1% of 1/BAUD_RATE

---

## Testbench Priority

For Stage 1 gate, all of the following must exist and pass simulation before
any module is connected to a live bus:

| Priority | Testbench | Status | Gate |
|----------|-----------|--------|------|
| 1 | `fpga/tb/smbus_monitor_tb.v` | Not written | Stage 1 |
| 2 | `fpga/tb/telemetry_uart_tb.v` | Not written | Stage 1 |
| 3 | `fpga/tb/smbus_arbiter_tb.v` | Not written | Before live bus connect |
| 4 | `fpga/tb/spd_responder_tb.v` | Blocked — SS_SEND_BYTE not implemented | Stage 2 |

pmbus_master: no testbench requirement until Stage 3.
