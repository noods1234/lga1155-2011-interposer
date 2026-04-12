# LGA 1155 / Z68 Active Interposer Research Platform

**Status**: Pre-silicon / Instrumentation phase  
**Platform**: 2011 iMac (iMac12,2), Intel Z68 PCH, Sandy Bridge LGA 1155  
**Objective**: Research and characterize an active CPU interposer / carrier for LGA 1155 that enables controlled silicon experiments on a real production system.

---

## WARNING: Experimental Research Repository

This repository documents an **active hardware research project**. Nothing here is a finished product. Every subsystem is explicitly tagged with its credibility level:

| Tag | Meaning |
|-----|---------|
| `[Verified]` | Confirmed by measurement, oscilloscope capture, or documented third-party source |
| `[Inference]` | Derived from verified data by logical or electrical reasoning |
| `[Hypothesis]` | Technically plausible but unconfirmed |
| `[Placeholder]` | Structural slot only; no real data; **must not be used in any live experiment** |

**Placeholders are labeled `INVALID` or `PLACEHOLDER` inline. Do not use them as defaults.**

---

## What This Is

An active interposer (also called a CPU carrier or socket riser) is a PCB that:

1. Inserts between the CPU package and the LGA 1155 socket on the motherboard
2. Provides a second LGA 1155 socket on its top surface to receive the CPU
3. Routes every CPU signal through an intermediate layer where an FPGA can observe, hold, or (selectively and carefully) modify signals before they reach the motherboard

This is **not** a product, BIOS patch, or OpenCore configuration. It is a hardware instrumentation and experimentation platform. OS-level or EFI-level hacks are strictly secondary to hardware bring-up truth.

---

## Scope Limitations (Hard Constraints)

- Memory initialization (`MRC`) is **not solved** and is not assumed to be trivially solvable. Any experiment that depends on RAM being initialized must explicitly account for this.
- `--nop-mrc` (or any equivalent MRC bypass) is **an experiment parameter only**, never a default or production mode.
- Sandy Bridge ↔ Ivy Bridge coercion is a **Stage 2+ hypothesis**. It is not the starting point.
- No OpenCore or OS-level claim supersedes a hardware measurement.

---

## Repository Structure

```
lga1155-2011-interposer/
├── README.md                        ← This file
├── docs/
│   ├── architecture/
│   │   └── system-overview.md       ← Platform and interposer architecture
│   ├── risk-register.md             ← Living risk register
│   ├── salvage-audit.md             ← Audit of inherited / legacy code
│   └── bringup-plan.md              ← Staged bring-up roadmap
├── hardware/                        ← Schematics, layout, mechanical constraints
├── fpga/
│   ├── rtl/                         ← Verilog RTL, one module per file
│   │   ├── smbus_monitor.v
│   │   ├── smbus_arbiter.v
│   │   ├── spd_responder.v
│   │   ├── pmbus_master.v
│   │   └── telemetry_uart.v
│   ├── constraints/                 ← Timing and pin constraints
│   ├── sim/                         ← Simulation scripts
│   └── tb/                          ← Testbenches
├── firmware/                        ← Microcontroller firmware (if MCU present)
├── efi/                             ← EFI / UEFI driver stubs
├── opencore/                        ← OpenCore config; strictly secondary
│   └── ACPI/
├── os/                              ← OS-level instrumentation scripts
├── tools/
│   ├── spd-gen/                     ← SPD byte generation pipeline
│   ├── efi-audit/                   ← EFI binary analysis
│   └── pin-analyzer/                ← Pin signal classification tools
├── data/
│   ├── pinout/                      ← LGA 1155 pin maps and classifications
│   ├── rails/                       ← Power rail and sequencing data
│   ├── spd/                         ← SPD templates and captured data
│   └── cpuid/                       ← CPUID leaves from real hardware
└── experiments/
    └── stage0-native-sniff/         ← Stage 0: passive Sandy Bridge observation
```

---

## Experimental Stages

| Stage | Name | Gate Condition |
|-------|------|----------------|
| 0 | Native Sandy Bridge instrumentation | No interposer; oscilloscope + logic analyzer only |
| 1 | Strap / reset / power-good perturbation | Stage 0 baseline captured; interposer PCB fabricated and validated passively |
| 2 | Ivy Bridge coercion experiments | Stage 1 perturbation understood; CPUID/strap analysis complete |
| 3 | External memory / policy experiments | Stage 2 stable; MRC interaction characterized |
| 4 | Active carrier proof-of-concept | All prior stages gated; FPGA bridge validated in loopback |

**No stage may begin before its gate condition is met.**

---

## Contributing / Using This Work

- Label all new findings with a credibility tag
- Do not commit placeholder values in critical paths without `INVALID` or `PLACEHOLDER` markers
- Run the SPD generation pipeline for any new SPD data; never hand-edit SPD bytes
- All FPGA RTL changes require a corresponding testbench update
- The risk register (`docs/risk-register.md`) must be updated when new risks are identified

---

## References

- Intel Sandy Bridge Platform Memory Controller Hub (Z68) External Design Specification — *[Hypothesis: publicly available version may be incomplete]*
- JEDEC Standard No. 21C — Serial Presence Detect (SPD)
- JEDEC Standard No. 79-3 — DDR3 SDRAM
- Intel 64 and IA-32 Architectures Software Developer's Manual — CPUID leaves
- LGA 1155 mechanical / electrical specification — *[Placeholder: not yet located; cross-reference Intel ARK and board schematics]*
