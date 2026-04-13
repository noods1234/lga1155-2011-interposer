# Risk Register

**Format**: ID | Title | Category | Likelihood (1–5) | Impact (1–5) | Score | Status | Mitigation | Owner  
**Scoring**: Score = Likelihood × Impact. Score ≥ 15 = Critical, 8–14 = High, 4–7 = Medium, 1–3 = Low  
**Status**: Open / Mitigated / Accepted / Closed

---

## Critical Risks (Score ≥ 15)

### R-001: Interposer PCB Z-height infeasible

| Field | Value |
|-------|-------|
| Category | Physical / Mechanical |
| Likelihood | 4 |
| Impact | 5 |
| Score | 20 — CRITICAL |
| Status | Open |
| Owner | — |
| Description | The LGA 1155 socket has a defined CPU package seating height. Any interposer PCB plus two sets of contact pads must fit within the socket's designed Z-tolerance (estimated < 0.5 mm total PCB stack). Standard PCB fabrication minimum thickness is 0.4 mm (0.2 mm achievable at premium cost). A two-PCB stack (interposer body + re-routing layer) may exceed available clearance, causing CPU lid or IHS contact failure. |
| Truth label | [Hypothesis] — risk magnitude unconfirmed until caliper measurement taken |
| Current evidence | No measurement. Stage 0 T0.6 caliper measurement not yet performed. Three-tier gate defined in experiments/stage0-native-sniff/README.md: ≥0.5 mm (standard FR4 viable), 0.3–0.5 mm (thin PCB path), <0.3 mm (R-001 BLOCKING). |
| Unknowns | Actual socket Z-clearance on this specific iMac unit; whether thin-PCB suppliers (0.1–0.15 mm) can maintain controlled impedance; whether flex-PCB approach is electrically viable for SMBus signal integrity. |
| Validation method | Stage 0 T0.6: caliper measurement at three socket corners. Record in hardware/measurements/socket-z-clearance.md with photo. |
| Exit criteria | Measurement ≥ 0.3 mm with documented caliper reading → R-001 downgraded to High; PCB path selected based on tier. Measurement < 0.3 mm → R-001 remains BLOCKING until flex or wire-wrap pivot is evaluated. |
| Mitigation | 1. Measure actual LGA socket Z-clearance with calipers before designing PCB. 2. Investigate ultra-thin PCB fabricators (0.1–0.15 mm). 3. Consider flex-PCB interposer. 4. If infeasible, pivot to socket-level signal tap (wire-wrap on socket pins) for passive observation only. |
| Gate | Must be resolved before any PCB fabrication order. |

---

### R-002: DDR3 signal integrity destroyed by interposer

| Field | Value |
|-------|-------|
| Category | Electrical / Signal Integrity |
| Likelihood | 4 |
| Impact | 5 |
| Score | 20 — CRITICAL |
| Status | Open |
| Owner | — |
| Description | DDR3-1333 operates at 667 MHz data rate. Every millimeter of trace added by the interposer changes propagation delay and may introduce impedance discontinuities. DDR3 uses source-synchronous clocking with tight timing margins (~100–200 ps). An interposer with uncalibrated trace lengths will almost certainly cause DDR3 training failure. |
| Truth label | [Inference] — DDR3 timing margins documented in spec; interposer trace impact is estimated, not simulated |
| Current evidence | DDR3-1333 tCK = 1500 ps; PCB trace propagation ≈ 6 ps/mm at FR4 (Dk ≈ 4.2). Stage 0 T0.7 will measure SMBus edge rates; Stage 1 will remeasure with passive tap in place. DDR3 path not entered until Stage 3+. |
| Unknowns | Required trace routing distance through final interposer design; PCB Dk at 667 MHz; whether passive monitoring (SMBus only) requires any DDR3 routing at all; whether active re-timing via FPGA is feasible at DDR3 data rates. |
| Validation method | For SMBus path (Stages 0–2): oscilloscope edge rate comparison before and after passive tap insertion. For DDR3 path (Stage 3+): SI simulation (IBIS-AMI or equivalent) before PCB fabrication. |
| Exit criteria | Stage 1 SMBus edge rate degradation < 10% vs. Stage 0 baseline → R-002 downgraded for SMBus path. DDR3 path requires: controlled-impedance PCB spec, simulation showing < 20 ps added skew, and explicit Stage 3 gate review. |
| Mitigation | 1. Stage 0–1 experiments avoid DDR3 signal routing entirely. 2. If DDR3 interposition is required, use controlled-impedance PCB (50 Ω stripline), match trace lengths to within 5 mm, and plan for BIOS MRC re-training. 3. Consider that DDR3 interposition may require FPGA-based re-driving (active re-timing), which is a major additional complexity. |
| Gate | Do not route DDR3 signals through interposer without controlled-impedance PCB and DDR3 simulation. |

---

### R-003: MRC failure renders system unbootable

| Field | Value |
|-------|-------|
| Category | Firmware / Boot |
| Likelihood | 4 |
| Impact | 5 |
| Score | 20 — CRITICAL |
| Status | Open |
| Owner | — |
| Description | Memory Reference Code (MRC) is closed-source firmware embedded in the platform BIOS. It trains DDR3 channels, sets up the memory controller, and must complete before any DRAM is usable. Any modification to SPD data, DDR3 timing, or CPU identity that MRC does not expect will result in training failure. Failure modes range from silent hang to DRAM bus contention, which could damage hardware. |
| Truth label | [Verified] for failure mode class; [Hypothesis] for Apple iMac12,2 MRC-specific behavior |
| Current evidence | MRC failure on Sandy Bridge is well-documented in coreboot/Libreboot community. iMac12,2 MRC is closed-source; no behavioral data captured yet. Stage 0 T0.1 SMBus capture will reveal which SPD byte addresses MRC reads and in what order during POST. |
| Unknowns | Whether Apple MRC enforces strict SPD CRC; which SPD bytes MRC actually reads vs. ignores; whether MRC fingerprints SPD manufacturer bytes; recovery behavior if MRC fails (does it retry, hang, or fall back to safe mode?). |
| Validation method | Stage 0 T0.1: annotate SMBus capture to identify all MRC SPD reads. Stage 0 T0.3: acpidump to get EFI volume for static analysis of MRC entry point. Cross-reference with Intel MRC documentation. |
| Exit criteria | Stage 0 SMBus capture committed with MRC SPD access sequence annotated. Every byte address that MRC reads must be identified before any SPD injection experiment is approved. |
| Mitigation | 1. Never use `--profile mrc-nop-hypothesis` as a default. It is a diagnostic experiment only and must be gated behind a physical jumper or explicit experiment flag. 2. Before injecting synthetic SPD, validate that the synthetic SPD is accepted by MRC in an isolated test (e.g., via SPD EEPROM swap, not interposer). 3. Have a recovery path: CMOS clear, known-good DIMM. |
| Gate | MRC behavior must be characterized in Stage 0 before any SPD injection experiment. |

---

## High Risks (Score 8–14)

### R-004: FPGA timing constraints not met at DDR3 clock speeds

| Field | Value |
|-------|-------|
| Category | FPGA / Digital Design |
| Likelihood | 3 |
| Impact | 5 |
| Score | 15 — CRITICAL (borderline) |
| Status | Open |
| Description | Monitoring DDR3 signals in real-time requires the FPGA to sample at DDR3 clock edge rate (≥667 MHz). Most low-cost FPGAs (e.g., Lattice iCE40, Xilinx Spartan-6) cannot close timing at these rates without careful pipelining and I/O register placement. The DDR3 capture path, if implemented, will require careful constraint-driven synthesis. |
| Evidence | [Inference] from FPGA data sheet typical I/O specifications. |
| Mitigation | 1. Stages 0–2 only require SMBus monitoring (≤400 kHz). Use cheap FPGA with generous timing margin. 2. DDR3 capture is Stage 3+. Re-evaluate FPGA choice when Stage 3 begins. 3. Consider dedicated DDR3 capture ASIC or SERDES-capable FPGA for Stage 3. |
| Gate | FPGA selection for Stages 0–2 may proceed. DDR3 capture FPGA selection is deferred. |

---

### R-005: Apple EFI performs silicon validation beyond CPUID

| Field | Value |
|-------|-------|
| Category | Firmware / Compatibility |
| Likelihood | 3 |
| Impact | 4 |
| Score | 12 — High |
| Status | Open |
| Description | Apple's EFI (not standard UEFI) may perform additional platform validation checks including MSR reads, CPUID extended leaves, power management capability checks, or TDP comparisons. If any check fails, EFI may halt with an undefined error or silently disable features. The full set of Apple EFI platform checks is unknown. |
| Evidence | [Hypothesis] based on Apple's history of tight platform locking and known issues with iMac CPU upgrades. |
| Mitigation | 1. Capture a full CPUID dump from the stock Sandy Bridge CPU before any experiment (tools/efi-audit). 2. Compare against Ivy Bridge CPUID dump from a known-good Ivy Bridge system. 3. If Apple EFI checks specific MSR values, those must be identified via EFI binary analysis. 4. OpenCore CPUID masking is a software mitigation only; it does not help at the hardware bring-up stage. |
| Gate | CPUID capture is a Stage 0 deliverable. |

---

### R-006: Interposer PCB mechanical damage to LGA socket

| Field | Value |
|-------|-------|
| Category | Physical / Hardware Damage |
| Likelihood | 3 |
| Impact | 4 |
| Score | 12 — High |
| Status | Open |
| Description | LGA 1155 socket pins are delicate spring contacts. Inserting a non-standard PCB interposer risks bending or breaking socket pins. The iMac motherboard is non-replaceable in practice (not commonly available as spare part). |
| Evidence | [Verified] — LGA socket pin damage is a known risk in any LGA socket work. |
| Mitigation | 1. Practice interposer insertion on a sacrificial LGA 1155 socket before touching the iMac. 2. Design interposer with chamfered edges and smooth contact pads. 3. Never force the interposer; if it requires more than finger pressure, stop and investigate. 4. Maintain a working iMac backup or spare motherboard. |
| Gate | Insertion practice required before any live system experiment. |

---

### R-007: SMBus bus contention from FPGA tap

| Field | Value |
|-------|-------|
| Category | Electrical |
| Likelihood | 3 |
| Impact | 3 |
| Score | 9 — High |
| Status | Open |
| Description | Adding a passive FPGA SMBus tap introduces capacitive load on the SMBus. SMBus specifies maximum bus capacitance. Exceeding it causes slow edge rates and transaction errors. If the FPGA input impedance is insufficient or the tap trace is too long, it will interfere with SPD reads and may cause POST hangs. |
| Evidence | [Inference] from SMBus specification (max 400 pF bus capacitance). |
| Mitigation | 1. Keep tap trace short (< 10 mm). 2. Use high-impedance FPGA input with no bus driving in monitor-only mode. 3. Measure SMBus edge rates with oscilloscope on stock system before interposer; measure again after passive tap insertion to confirm no degradation. |
| Gate | Must verify non-degradation of SMBus edge rates after passive tap. |

---

## Medium Risks (Score 4–7)

### R-008: Synthetic SPD data causes DIMM training instability

| Field | Value |
|-------|-------|
| Category | Firmware / Stability |
| Likelihood | 3 |
| Impact | 2 |
| Score | 6 — Medium |
| Status | Open |
| Description | Even if MRC accepts synthetic SPD, the resulting timing parameters may cause intermittent DRAM errors under load. This is hard to detect without a memory stress test. |
| Mitigation | 1. Use SPD values from a validated DDR3 module as the baseline. 2. Run memtest86+ after any SPD injection experiment. 3. Never modify SPD timing values in a speculative direction; only use values confirmed by JEDEC spec for the installed DRAM. |

---

### R-009: FPGA configuration loss on power cycle

| Field | Value |
|-------|-------|
| Category | FPGA / Infrastructure |
| Likelihood | 2 |
| Impact | 3 |
| Score | 6 — Medium |
| Status | Open |
| Description | SRAM-based FPGAs (most low-cost parts) lose their configuration on power removal. If the interposer FPGA is not configured before the host system powers its SMBus, the FPGA will briefly present undefined states on SMBus, potentially corrupting SPD reads. |
| Mitigation | 1. Add a dedicated SPI flash for FPGA configuration. 2. Power-sequence the FPGA before the SMBus is pulled up by the PCH. 3. Design the interposer to pass SMBus through transparently until FPGA is fully configured (pass-through default via hardware mux). |

---

### R-010: Legacy code from old branch introduces incorrect hardware assumptions

| Field | Value |
|-------|-------|
| Category | Software / Process |
| Likelihood | 4 |
| Impact | 2 |
| Score | 8 — High |
| Status | Open |
| Description | The old branch (apple-set-os fork) contained code and documentation derived from non-hardware sources. Some files encoded assumptions about pin assignments, CPUID values, or boot behavior that were speculative or incorrect. Carrying over this code without review would propagate wrong assumptions. |
| Evidence | [Verified] — Salvage audit performed; see docs/salvage-audit.md. |
| Mitigation | All inherited files reviewed and classified. No file carried over without explicit keep/rewrite decision. All Placeholder values marked INVALID inline. |
| Status | Mitigated by salvage audit. Monitor for new instances. |

---

## Risk Summary Table

| ID | Title | Score | Status |
|----|-------|-------|--------|
| R-001 | Interposer Z-height infeasible | 20 | Open |
| R-002 | DDR3 SI destroyed by interposer | 20 | Open |
| R-003 | MRC failure / unbootable | 20 | Open |
| R-004 | FPGA timing at DDR3 speeds | 15 | Open |
| R-005 | Apple EFI extra silicon checks | 12 | Open |
| R-006 | LGA socket pin damage | 12 | Open |
| R-007 | SMBus bus contention | 9 | Open |
| R-008 | Synthetic SPD instability | 6 | Open |
| R-009 | FPGA config loss on power cycle | 6 | Open |
| R-010 | Legacy code wrong assumptions | 8 | Mitigated |

---

*This register must be reviewed and updated at the start of each experimental stage.*
