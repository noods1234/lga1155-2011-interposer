# Hardware

**Status**: [Placeholder] — no PCB design started  
**Gate condition**: Stage 0 Z-clearance measurement complete (R-001 resolved)

This directory will contain:

```
hardware/
  measurements/          ← Physical measurements from Stage 0
    socket-z-clearance.md
  interposer-v0.1/       ← First passive interposer PCB (Stage 1)
    schematic.pdf
    layout.kicad_pcb
    bom.csv
    test-results.md
  power/                 ← Power supply routing and decoupling design
  clock-reset/           ← Reset and clock signal routing
  smbus-pmbus/           ← SMBus tap and isolation circuit
  debug/                 ← Debug headers, test points
```

## Design Constraints (Preliminary)

All values marked [Placeholder] until measured.

| Constraint | Value | Credibility |
|-----------|-------|-------------|
| Max interposer PCB thickness | [Placeholder] mm | Placeholder |
| LGA socket pitch | 1.0 mm | [Verified] |
| SMBus pull-up voltage | 3.3 V | [Inference] |
| SMBus max bus capacitance | 400 pF | [Verified — SMBus spec] |
| DDR3 trace impedance target | 40 Ω (single-ended) | [Inference] |
| DDR3 trace length matching tolerance | ±5 mm | [Inference] |

## PCB Fabrication Requirements (Stage 1 Passive Interposer)

- Controlled impedance: not required for Stage 1 (DDR3 signals pass through unmodified)
- Minimum trace/space: 0.1/0.1 mm preferred (dense pin field)
- Stackup: 2-layer minimum; 4-layer if Z-height permits
- Surface finish: ENIG (protects LGA contact pads)
- **Do not order until T0.6 (Z-clearance measurement) confirms feasibility**
