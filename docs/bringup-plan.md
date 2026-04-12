# Staged Bring-Up Plan

**Philosophy**: No stage begins until the previous stage's gate condition is met and documented. Gate conditions are not advisory; they are hard requirements. If a gate condition cannot be met, the project stops and the risk register is updated.

---

## Stage 0: Native Sandy Bridge Instrumentation

**Goal**: Establish a complete, measured baseline of the real platform before any modification.  
**Hardware**: Stock iMac12,2 with original Sandy Bridge CPU. No interposer. No modifications.  
**Tools**: Oscilloscope, logic analyzer, `acpidump`, `dmidecode`, custom CPUID tool.

### Deliverables

| Deliverable | Output Path | Credibility Required |
|-------------|-------------|---------------------|
| SMBus transaction capture during POST | `data/smbus/stage0-post-smbus.vcd` | [Verified] — must be oscilloscope/LA capture |
| Full CPUID leaf dump (Sandy Bridge) | `data/cpuid/sandy-bridge-stock.json` | [Verified] — from actual hardware |
| Power rail timing measurements | `data/rails/stage0-rail-timing.csv` | [Verified] — from oscilloscope |
| PWRGOOD / RESET_N timing | `data/rails/stage0-power-good-timing.csv` | [Verified] — from oscilloscope |
| Full ACPI DSDT/SSDT dump | `data/acpi/stage0-dsdt.dsl` (decompiled) | [Verified] — from `acpidump` on target |
| LGA 1155 socket Z-clearance measurement | `hardware/measurements/socket-z-clearance.md` | [Verified] — from calipers |
| SMBus edge rate measurement (baseline) | `data/smbus/stage0-edge-rates.md` | [Verified] — from oscilloscope |
| SPD data from installed DIMMs | `data/spd/stage0-installed-dimm-spd.bin` | [Verified] — from `decode-dimms` or `i2cdump` |

### Tasks

1. **T0.1** — Set up oscilloscope probes on SMBus CLK and DAT lines (test points to be identified on iMac board). Capture a full POST SMBus transaction sequence.
2. **T0.2** — Run CPUID capture tool on stock Sandy Bridge CPU. Capture all standard and extended leaves. Store in `data/cpuid/`.
3. **T0.3** — Use `acpidump` + `iasl` to dump and decompile DSDT and all SSDTs. Store in `data/acpi/`.
4. **T0.4** — Measure power rail sequencing from S5 to S0 with oscilloscope. Document PWRGOOD assertion time, RESET_N deassertion time.
5. **T0.5** — Read SPD data from all installed DIMMs via `i2cdump` at SMBus addresses 0x50–0x53.
6. **T0.6** — Physically measure LGA socket Z-clearance with calibrated calipers. Document in `hardware/measurements/`.
7. **T0.7** — Review Z68 and Sandy Bridge platform documentation. Tag all extracted claims with credibility.

### Gate Condition for Stage 1

All eight deliverables above must be present, committed, and marked [Verified]. The LGA socket Z-clearance measurement (T0.6) must show ≥ 0.3 mm available for an interposer (if less, R-001 escalates to project-stopping and the approach must be reconsidered).

---

## Stage 1: Strap / Reset / Power-Good Perturbation

**Goal**: Understand what happens when reset, power-good, and configuration straps are varied. Validate the passive interposer PCB.  
**Hardware**: Interposer PCB (passive — no active FPGA in the signal path yet). Interposer has: passive feed-through for all signals, SMBus tap with high-impedance buffer, test points on strap/reset/PG signals.  
**Prerequisite**: Stage 0 gate condition met. Interposer PCB fabricated and verified against electrical continuity test on bench (no live system).

### Deliverables

| Deliverable | Output Path | Credibility Required |
|-------------|-------------|---------------------|
| Interposer PCB schematic | `hardware/interposer-v0.1/schematic.pdf` | [Verified] — reviewed against LGA 1155 pinout |
| Interposer continuity test results | `hardware/interposer-v0.1/test-results.md` | [Verified] — from bench meter |
| SMBus edge rates with passive interposer | `data/smbus/stage1-edge-rates-passive.md` | [Verified] — must show no degradation vs. Stage 0 baseline |
| Boot success rate with passive interposer | `experiments/stage1-passive/boot-log.md` | [Verified] — minimum 10 boot attempts |
| PWRGOOD perturbation response | `experiments/stage1-pwrgood/results.md` | [Verified] — from oscilloscope |
| Strap state reading (if accessible) | `data/straps/stage1-strap-states.md` | [Verified or Inference] |

### Tasks

1. **T1.1** — Design passive interposer PCB. Route all signals 1:1. Add SMBus tap with 10 kΩ series resistor to FPGA header (DNP initially).
2. **T1.2** — Fabricate and perform continuity / shorts check on bare PCB.
3. **T1.3** — Insert passive interposer. Boot system 10× and record success/failure. Compare boot timing to Stage 0 baseline.
4. **T1.4** — Monitor SMBus with passive tap. Compare captured traces to Stage 0. Verify no degradation.
5. **T1.5** — Carefully toggle PWRGOOD and RESET_N via test points. Record platform response.
6. **T1.6** — If strap pins are accessible, read their logic states. Document.

### Gate Condition for Stage 2

Passive interposer achieves ≥ 10 consecutive clean boots. SMBus edge rates are not degraded by more than 10% from baseline. R-001 confirmed not a blocker (physical fit verified). At least one strap signal characterized.

---

## Stage 2: Ivy Bridge Coercion Experiments

**Goal**: Determine whether a Z68 platform can be made to accept an Ivy Bridge CPU, and what signals or configuration changes are required.  
**Hardware**: Interposer with FPGA populated. FPGA programmed with `smbus_monitor` and `telemetry_uart` modules only (observe, do not modify).  
**Prerequisite**: Stage 1 gate condition met.

**[Hypothesis]**: This stage is highly speculative. The primary question is whether Z68 BIOS microcode and MRC will accept an Ivy Bridge CPU. Some Z68 boards support Ivy Bridge via BIOS update; Apple's iMac may or may not have received such an update. The first experiment is to simply insert an Ivy Bridge CPU with no interposer intervention and observe what happens.

### Tasks

2.1 — Insert Ivy Bridge CPU (no interposer modification). Observe boot. Does it POST?  
2.2 — If POST: capture CPUID, compare to Sandy Bridge baseline.  
2.3 — If no POST: analyze failure point. Is it before MRC, during MRC, or during EFI?  
2.4 — Enable FPGA SMBus monitor. Observe SPD read sequence with Ivy Bridge installed. Any changes vs. Sandy Bridge?  
2.5 — Review Apple EFI binary for CPUID checks (tools/efi-audit).  
2.6 — If Apple EFI blocks Ivy Bridge: design OpenCore CPUID mask targeting correct values (0x3A → 0x2A mask). This is a software experiment only.

### Gate Condition for Stage 3

Ivy Bridge either POSTs cleanly OR the exact failure mechanism is identified and documented. CPUID mask (software) experiments have been run and their limits are understood. SMBus behavior with Ivy Bridge is characterized.

---

## Stage 3: External Memory / Policy Experiments

**Goal**: Control SPD data presented to MRC via FPGA `spd_responder`. Understand MRC reaction to modified SPD.  
**Hardware**: Interposer with FPGA `spd_responder` active. SPD EEPROM isolation circuit (bus switch to remove real EEPROM from bus).  
**Prerequisite**: Stage 2 gate condition met. SPD generation pipeline validated. MRC behavior characterized.

**[Hypothesis]**: Injecting synthetic SPD data may allow the platform to train memory at different timings. This is risky (R-003, R-008). The first experiment uses SPD data identical to the real DIMM — a pass-through emulation — to validate the SPD responder before introducing any changes.

### Tasks

3.1 — Implement `spd_responder.v` with pass-through mode (emulates real DIMM SPD exactly).  
3.2 — Enable pass-through SPD responder. Verify system still boots cleanly.  
3.3 — Generate alternate SPD profile via `tools/spd-gen/` pipeline.  
3.4 — Inject alternate SPD for one slot. Observe MRC behavior.  
3.5 — Run memtest86+ after any successful boot with synthetic SPD.

### Gate Condition for Stage 4

Pass-through SPD emulation works reliably (≥ 20 clean boots). At least one synthetic SPD variant has been accepted by MRC and the system has passed memtest86+.

---

## Stage 4: Active Carrier Proof-of-Concept

**Goal**: Demonstrate that the FPGA can actively modify a platform-relevant signal path and produce a predictable, recoverable outcome.  
**Hardware**: Full interposer with all FPGA modules validated.  
**Prerequisite**: Stage 3 gate condition met. All prior stage data documented and committed.

This stage is intentionally underspecified. What "active carrier" means depends entirely on what was learned in Stages 0–3. If Stage 2 shows that Ivy Bridge works without interposer assistance, Stage 4 pivots to a different capability (e.g., controlled power management modification, multi-CPU hypothetical research, or platform monitoring). If Stage 2 shows that CPUID or MRC changes are needed, Stage 4 implements the minimum necessary active modification.

**Do not pre-design Stage 4 in detail. Design it based on evidence.**

---

## Cross-Stage Dependencies

```
Stage 0 ──[Gate 0]──► Stage 1 ──[Gate 1]──► Stage 2 ──[Gate 2]──► Stage 3 ──[Gate 3]──► Stage 4
   │                     │                     │                     │
   ▼                     ▼                     ▼                     ▼
data/cpuid/        hardware/pcb/        experiments/           data/spd/
data/smbus/        fpga/ (passive)      stage2-ivy/            tools/spd-gen/
data/rails/
data/acpi/
```

No arrows go backwards. No stage is revisited without creating a new sub-experiment directory.
