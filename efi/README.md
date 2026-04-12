# EFI

**Status**: Stage 0 tools implemented; not yet compiled or tested on target  
**Credibility**: [Inference]

---

## Directory Layout

```
efi/
  CpuidAudit/
    CpuidAudit.inf        ← EDK II module definition
  MsrAudit/
    MsrAudit.inf          ← EDK II module definition
  src/
    cpuid_audit.c         ← Read-only CPUID leaf dump
    msr_audit.c           ← Read-only MSR audit (RAPL, SpeedStep, microcode rev)
  include/
    PhaseLog.h            ← Phase logging macros (PHASE_BEGIN/OK/FAIL/NOTE)
    PlatformCpuid.h       ← Typed CPUID bitfield structs for SNB/IVB
```

---

## Tools

### CpuidAudit (Stage 0)

Dumps all CPUID leaves from BSP and all APs via `EFI_MP_SERVICES_PROTOCOL`.  
Decodes and identifies Sandy Bridge (0x2A) vs. Ivy Bridge (0x3A) using typed structures from `PlatformCpuid.h`.  
Reports F16C / RDRAND / FMA feature bits — the key leaf-0x01 differentiators between Sandy Bridge and Ivy Bridge.

Output: `data/cpuid/sandy-bridge-stock.json` (Stage 0 deliverable T0.2)

### MsrAudit (Stage 0)

Reads MSRs that are not visible via CPUID:
- **MSR 0x8B** — Loaded microcode revision (critical: SNB and IVB use different microcode)
- **MSR 0xCE** — Max non-turbo ratio, TDP levels
- **MSR 0x610 / 0x611** — RAPL package power limit and energy counter
- **MSR 0x1A0** — SpeedStep / turbo enable state
- **MSR 0x3A** — VMX / TXT / BIOS lock state

Uses CPU identity filter: MSRs marked `SandyBridgePresent = FALSE` are skipped on a Sandy Bridge to avoid #GP faults.

Output: `data/cpuid/sandy-bridge-msr-stock.txt` (Stage 0 deliverable T0.2)

---

## Shared Headers

### `include/PhaseLog.h`

Macros: `PHASE_BEGIN`, `PHASE_OK`, `PHASE_FAIL`, `PHASE_NOTE`, `PHASE_WARN`, `PHASE_VALUE`, `PHASE_CHECK_RETURN`.

Every EFI tool in this project must use these macros for status output. If the tool hangs on Apple EFI, the last printed `[>>]` line is the failure point.

### `include/PlatformCpuid.h`

Typed `CPUID_VERSION_INFO_EAX` bitfield union, `DECODED_CPU_INFO` struct, `PLATFORM_CPU_IDENTITY` enum, and `DecodeCpuInfo()` inline function. Avoids inline bit-masking arithmetic throughout the codebase.

Known-model reference:
| Model | Identity | Notes |
|-------|----------|-------|
| 0x2A | Sandy Bridge | Expected: iMac12,2 stock |
| 0x3A | Ivy Bridge | Upgrade hypothesis target |
| 0x3F | Haswell-E | **Wrong platform** (LGA2011-3) |

---

## Design Rules

1. **Typed protocol access only.** All EFI protocols via `gBS->LocateProtocol()`. No raw pointer casting. No hardcoded function-pointer offsets. (This was the bug in the rejected `haswell_e_cpuid.c`.)
2. **Phase logging on every major step.** Use `PhaseLog.h` macros throughout.
3. **No platform state modification** in audit tools. `cpuid_audit.c` and `msr_audit.c` are read-only.
4. **Explicit abort conditions.** Missing protocols log a warning and degrade gracefully, not silently.
5. **CPUID/MSR spoofing is Stage 2+**, in a separate file, with an explicit experiment gate.

---

## Building

Requires EDK II. Add both modules to a package DSC:

```ini
[Components]
  lga1155-2011-interposer/efi/CpuidAudit/CpuidAudit.inf
  lga1155-2011-interposer/efi/MsrAudit/MsrAudit.inf
```

The include path for `PhaseLog.h` and `PlatformCpuid.h` must be added to the package DSC or each module INF `[Includes]` section.

---

## Deployment

1. Build → `CpuidAudit.efi`, `MsrAudit.efi`
2. Copy each to a FAT32 USB drive as `EFI/BOOT/BOOTX64.EFI`, one at a time
3. Boot iMac12,2 from USB; capture screen output
4. Store results in `data/cpuid/`

---

## Known Gaps

- `.inf` files reference `../src/*.c` — EDK II may require sources in the same directory; test with actual build and adjust path if needed
- No `[Includes]` directive in the `.inf` for the `efi/include/` path — add if compiler does not find headers automatically via package paths
- `MsrAudit` uses `AsmReadMsr64` without a #GP guard — on Apple EFI with an unknown MSR this will fault; if it hangs, the last `[>>]` line is the offending MSR
