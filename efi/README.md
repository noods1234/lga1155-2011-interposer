# EFI

**Status**: Stage 0 audit tool implemented; not yet compiled or tested  
**Credibility**: [Inference]

This directory contains EFI applications and protocol wrappers for platform analysis.

## Contents

| File | Purpose | Status |
|------|---------|--------|
| `src/cpuid_audit.c` | Read-only CPUID leaf dump via MP Services Protocol | Not compiled; not tested on target |

## Design Rules for All EFI Code in This Directory

1. **Typed protocol access only.** All EFI protocol instances must be obtained via `gBS->LocateProtocol()` with a typed GUID. No raw pointer casting. No hardcoded function pointer offsets.
2. **No platform state modification** in audit tools. `cpuid_audit.c` is read-only.
3. **Phase logging.** Each major step must print a status line so failure points are visible on screen or serial.
4. **Explicit abort conditions.** If a required protocol is unavailable, log the failure and return `EFI_UNSUPPORTED` — do not silently continue.
5. **CPUID spoofing is Stage 2+ only**, in a separate file, with an explicit experiment gate. It does not belong in `cpuid_audit.c`.

## Building

Build target: `CpuidAudit.efi` (UEFI application).

Requires EDK II. Add to a package DSC/INF:
```
[Components]
  lga1155-2011-interposer/efi/CpuidAudit/CpuidAudit.inf
```

The `.inf` file is not yet written. This is a Stage 0 task.

## Deployment

Copy `CpuidAudit.efi` to a FAT32 USB drive as `EFI/BOOT/BOOTX64.EFI`.  
Boot iMac from USB. Output appears on screen. Capture with camera or serial.

Output goes to `data/cpuid/sandy-bridge-stock.json` after manual transcription or serial capture.
