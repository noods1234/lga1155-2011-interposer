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
| Owner | — |
| Description | Monitoring DDR3 signals in real-time requires the FPGA to sample at DDR3 clock edge rate (≥667 MHz). Most low-cost FPGAs (e.g., Lattice iCE40, Xilinx Spartan-6) cannot close timing at these rates without careful pipelining and I/O register placement. The DDR3 capture path, if implemented, will require careful constraint-driven synthesis. |
| Truth label | [Inference] — based on FPGA datasheet I/O specs; no synthesis attempted yet |
| Current evidence | Stages 0–2 need only SMBus monitoring at ≤400 kHz — well within any modern FPGA I/O capability. DDR3 capture is Stage 3+. No FPGA selected for Stage 3 yet. fpga/rtl modules are currently targeting a generic Xilinx/Lattice device with 50 MHz system clock. |
| Unknowns | Whether DDR3 passive monitoring is needed at all (SMBus-only interposer may suffice); target FPGA for Stage 3; whether SERDES-based sampling is feasible or if a dedicated logic analyzer IC is a better approach. |
| Validation method | Stage 2: synthesize SMBus logic and verify timing closure. Stage 3 FPGA study: evaluate SERDES-capable parts (Xilinx Artix-7, Lattice ECP5) against DDR3 sample-rate requirements when Stage 2 is complete. |
| Exit criteria | Stage 2: synthesis timing report shows all paths closed at ≥ 50 MHz. Stage 3: FPGA chosen and I/O timing simulation shows DDR3 sample window ≥ 100 ps. |
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
| Owner | — |
| Description | Apple's EFI (not standard UEFI) may perform additional platform validation checks including MSR reads, CPUID extended leaves, power management capability checks, or TDP comparisons. If any check fails, EFI may halt with an undefined error or silently disable features. The full set of Apple EFI platform checks is unknown. |
| Truth label | [Hypothesis] — inferred from Apple platform history; no iMac12,2 EFI binary analysis performed |
| Current evidence | efi/src/cpuid_audit.c and msr_audit.c written (20 MSRs, Sandy Bridge filter). Not compiled on target. Apple EFI binary not yet obtained — requires Stage 0 T0.3 acpidump. tools/efi-audit/analyze.py implemented and ready to scan CPUID instruction references once binary is available. |
| Unknowns | Whether EFI_MP_SERVICES_PROTOCOL is available in Apple EFI; which MSRs Apple EFI reads; whether Apple EFI uses CPUID leaf 0x11 (topology) or extended leaves that differ between Sandy Bridge and Ivy Bridge; TDP register checks. |
| Validation method | Stage 0 T0.2: run CpuidAudit.efi and MsrAudit.efi on iMac12,2. T0.3: acpidump to extract EFI volume. Run tools/efi-audit/analyze.py to enumerate CPUID instruction references with offsets. |
| Exit criteria | cpuid_audit.json and msr_audit.txt committed with credibility: Verified. EFI binary analyzed; CPUID reference table committed to data/. Baseline established before any CPU swap experiment. |
| Mitigation | 1. Capture a full CPUID dump from the stock Sandy Bridge CPU before any experiment. 2. Compare against Ivy Bridge CPUID dump from a known-good Ivy Bridge system. 3. If Apple EFI checks specific MSR values, those must be identified via EFI binary analysis. 4. OpenCore CPUID masking is a software mitigation only; it does not help at the hardware bring-up stage. |
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
| Owner | — |
| Description | LGA 1155 socket pins are delicate spring contacts. Inserting a non-standard PCB interposer risks bending or breaking socket pins. The iMac motherboard is non-replaceable in practice (not commonly available as spare part). |
| Truth label | [Verified] — LGA socket pin fragility is general knowledge; iMac motherboard spares availability is [Hypothesis] |
| Current evidence | No interposer insertion practice performed. No spare socket or motherboard confirmed available. Stage 0 Z-clearance measurement (T0.6) pending — result directly informs interposer edge geometry. |
| Unknowns | Availability and cost of iMac12,2 spare logic boards; whether chamfered edge geometry is sufficient or if a guide frame is needed; how many practice insertions are required to establish consistent technique. |
| Validation method | Acquire a sacrificial LGA1155 socket or donor board. Perform ≥5 insertion/extraction cycles with a dummy PCB of the same outer dimensions as the planned interposer. Document insertion force and pin condition after each cycle. |
| Exit criteria | ≥5 successful insertions on sacrificial socket with no bent pins. Spare motherboard or socket identified and sourced before any live iMac insertion attempt. |
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
| Owner | — |
| Description | Adding a passive FPGA SMBus tap introduces capacitive load on the SMBus. SMBus specifies maximum bus capacitance. Exceeding it causes slow edge rates and transaction errors. If the FPGA input impedance is insufficient or the tap trace is too long, it will interfere with SPD reads and may cause POST hangs. |
| Truth label | [Inference] — SMBus capacitance spec is documented; actual impact depends on iMac PCH pull-up values (unknown) |
| Current evidence | SMBus spec: max 400 pF bus capacitance, pull-up typically 2.2–10 kΩ. Stage 0 T0.7 will establish baseline edge rates (SCL/SDA 10–90% rise/fall). Stage 1 T1.2 will remeasure with passive tap installed. Degradation gate: <10% increase in rise/fall time. |
| Unknowns | Actual iMac12,2 SMBus pull-up resistor values; FPGA GPIO input capacitance for the chosen part; tap trace length in the final interposer layout. |
| Validation method | Oscilloscope comparison: stock system edge rates (Stage 0 T0.7) vs. passive tap installed (Stage 1). Measure SCL and SDA 10–90% rise time and fall time. Gate: degradation must be <10%. |
| Exit criteria | Stage 1 smbus edge rates artifact committed with measured rise/fall times ≤ 110% of Stage 0 baseline. No new transaction errors in boot log. |
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
| Owner | — |
| Description | Even if MRC accepts synthetic SPD, the resulting timing parameters may cause intermittent DRAM errors under load. This is hard to detect without a memory stress test. |
| Truth label | [Inference] — known failure mode for incorrect SPD timing; iMac12,2 MRC tolerance is [Hypothesis] |
| Current evidence | validate_spd.py now treats all-zero timing bytes as a hard error (fixed in adversarial review). generate_spd.py correctly encodes CL9/DDR3-1333 tAAmin as 0x6C. Remaining timing bytes (17-29) are still zeroed in default config and require Stage 0 capture to populate. |
| Unknowns | Whether Apple MRC is more or less tolerant of timing margining than standard Intel MRC; whether iMac12,2 uses any non-standard DDR3 timing profiles; exact timing requirements for the installed DIMM model. |
| Validation method | After any SPD injection: memtest86+ (or equivalent) ≥ 2 full passes. Cross-check generated SPD byte-for-byte against Stage 0 captured SPD from the same DIMM. |
| Exit criteria | memtest86+ passes 2 full passes with 0 errors after any SPD injection experiment. Generated SPD timing fields match or are more conservative than the captured DIMM SPD. |
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
| Owner | — |
| Description | SRAM-based FPGAs (most low-cost parts) lose their configuration on power removal. If the interposer FPGA is not configured before the host system powers its SMBus, the FPGA will briefly present undefined states on SMBus, potentially corrupting SPD reads. |
| Truth label | [Inference] — SRAM FPGA behavior is well-known; iMac PCH SMBus enable timing relative to 3.3V standby is [Hypothesis] |
| Current evidence | No interposer PCB designed yet. iMac12,2 PCH (Cougar Point Z68) SMBus is enabled during S5 standby for WOL and wake events — timing to first SMBus access at power-on is unknown. Stage 0 T0.1 SMBus capture may reveal when the first PCH SMBus transaction occurs after AC power-on. |
| Unknowns | Exact timing from AC power-on to first PCH SMBus transaction; whether 3.3V standby powers the SMBus pull-ups before main power rails; FPGA configuration time from SPI flash (typically 10–100 ms depending on bitstream size). |
| Validation method | Scope 3.3V standby rail and SMBus SCL simultaneously during iMac power-on. Measure time from 3.3VSB stable to first SMBus clock edge. Compare against FPGA SPI configuration time for chosen part. |
| Exit criteria | Interposer schematic includes SPI flash for auto-boot configuration and hardware pass-through mux (FPGA drives mux control; default = pass-through). Confirmed in simulation or bench test that FPGA completes configuration before first SMBus access. |
| Mitigation | 1. Add a dedicated SPI flash for FPGA configuration. 2. Power-sequence the FPGA before the SMBus is pulled up by the PCH. 3. Design the interposer to pass SMBus through transparently until FPGA is fully configured (pass-through default via hardware mux). |

---

### R-010: Legacy code from old branch introduces incorrect hardware assumptions

| Field | Value |
|-------|-------|
| Category | Software / Process |
| Likelihood | 4 |
| Impact | 2 |
| Score | 8 — High |
| Status | Mitigated |
| Owner | — |
| Description | The old branch (apple-set-os fork) contained code and documentation derived from non-hardware sources. Some files encoded assumptions about pin assignments, CPUID values, or boot behavior that were speculative or incorrect. Carrying over this code without review would propagate wrong assumptions. |
| Truth label | [Verified] — salvage audit performed and documented |
| Current evidence | Salvage audit complete (docs/salvage-audit.md, ledger v2). 16 bugs found and fixed in adversarial review pass (BUG-01–BUG-09, PY-2–PY-12). All 6 inherited file families classified: 2 rewrite-complete, 1 rewrite-partial, 1 keep-with-review, 2 reject, 1 quarantine. All Placeholder values are marked inline. |
| Unknowns | Whether ACPI reference fragment (SSDT-PMC-z68-reference.dsl) has additional issues not visible without real DSDT. Whether any unreviewed assumptions remain in EFI tool patterns. |
| Validation method | At each stage gate: re-run adversarial review on any files added or modified since last review. Monitor for new files from old branch lineage. Update salvage-audit.md when any artifact changes status. |
| Exit criteria | Salvage audit ledger shows no Reject/Unknown rows and no open BUG entries. All files have explicit, current credibility labels. Status: Mitigated — remains open for monitoring. |
| Mitigation | All inherited files reviewed and classified. No file carried over without explicit keep/rewrite decision. All Placeholder values marked inline. Adversarial review conducted; 16 bugs fixed. |

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
