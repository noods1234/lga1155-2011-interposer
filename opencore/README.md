# OpenCore

**Status**: Reference fragments only — no working OpenCore configuration  
**Credibility**: Mixed — see per-file notes  
**Priority**: Secondary to hardware bring-up

OpenCore integration is **not** the primary success criterion for this project. A working OpenCore configuration that masks CPUID does not prove that the hardware interposer works. These are separate concerns.

OpenCore configurations live here for reference and eventual use in Stage 2+ software experiments, after hardware bring-up is validated.

## Contents

```
opencore/
  ACPI/
    reference/
      SSDT-PMC-z68-reference.dsl   ← Z68/Cougar Point SBUS fragment (reference only)
  config/                          ← [Placeholder — not yet created]
```

## Rules for OpenCore Work

1. No OpenCore config is applied to the iMac before Stage 0 baseline data is captured. Applying OpenCore changes before baseline measurement would contaminate the baseline.
2. The ACPI reference fragments must be verified against the real DSDT (Stage 0 task T0.3) before any use.
3. OpenCore CPUID masking is a software experiment. It does not substitute for hardware characterization.
4. All OpenCore configs must be tagged with the macOS version and OpenCore version they target.
