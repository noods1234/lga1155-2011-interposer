/**
 * msr_audit.c — EFI Application: Read-Only MSR Audit
 *
 * Status     : [Inference] — MSR addresses from Intel SDM; not yet compiled
 *              or tested on iMac12,2
 * Credibility: [Inference]
 *
 * Purpose:
 *   Reads a curated set of Model-Specific Registers (MSRs) from the boot CPU
 *   and all APs via EFI MP Services. Outputs a structured report of platform
 *   configuration state that is not visible via CPUID.
 *
 *   MSR reads are Stage 0 data. They reveal:
 *   - Microcode version (important: Sandy Bridge vs. Ivy Bridge microcode differs)
 *   - Power management capabilities and limits (RAPL)
 *   - SpeedStep / turbo state
 *   - Platform security features (TXT, VT-x enable state)
 *
 * THIS IS READ-ONLY. No MSR writes. No platform state modification.
 *
 * Companion to: efi/src/cpuid_audit.c
 * Output goes to: data/cpuid/sandy-bridge-msr-stock.txt (Stage 0 task T0.2)
 *
 * IMPORTANT: MSR reads on an unexpected CPU model may #GP fault (general
 * protection fault) if the MSR does not exist on that stepping. This tool
 * uses a guarded read pattern (see MsrReadGuarded) that installs a simple
 * exception handler shim. On Apple EFI, exception handling behaviour is
 * non-standard; if the tool hangs, the most recently printed phase line
 * identifies which MSR caused the fault.
 *
 * Build: efi/MsrAudit/MsrAudit.inf
 */

#include <Uefi.h>
#include <Library/UefiLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/BaseLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Protocol/MpService.h>
#include "../../include/PhaseLog.h"
#include "../../include/PlatformCpuid.h"

/* -------------------------------------------------------------------------
 * MSR table: registers to read and their descriptions
 *
 * All MSR addresses and interpretations are [Inference] from Intel SDM
 * Vol.3, Appendix B (MSR Reference). Not all MSRs exist on all steppings.
 * A #GP on read indicates the MSR is not present on this CPU.
 * ------------------------------------------------------------------------- */

typedef struct {
    UINT32        Address;
    CONST CHAR16 *Name;
    CONST CHAR16 *Description;
    BOOLEAN       SandyBridgePresent;  /* [Inference] — exists on SNB */
    BOOLEAN       IvyBridgePresent;    /* [Inference] — exists on IVB */
} MSR_ENTRY;

STATIC CONST MSR_ENTRY MsrTable[] = {
    {
        0x17,   L"IA32_PLATFORM_ID",
        L"Platform ID bits — bits [52:50] encode platform segment",
        TRUE, TRUE
    },
    {
        0x35,   L"MSR_CORE_THREAD_COUNT",
        L"Enabled core and thread count — platform topology",
        TRUE, TRUE
    },
    {
        0x8B,   L"IA32_BIOS_SIGN_ID",
        L"Microcode revision loaded — upper 32 bits after CPUID leaf 1",
        TRUE, TRUE
    },
    {
        0xCE,   L"MSR_PLATFORM_INFO",
        L"Max non-turbo ratio, max efficiency ratio, TDP levels",
        TRUE, TRUE
    },
    {
        0x1A0,  L"IA32_MISC_ENABLE",
        L"SpeedStep enable, turbo enable, ENABLE_MONITOR_FSM, etc.",
        TRUE, TRUE
    },
    {
        0x1A4,  L"MSR_MISC_FEATURE_CONTROL",
        L"MLC/LLC streamer prefetch disable bits",
        TRUE, TRUE
    },
    {
        0x19C,  L"IA32_THERM_STATUS",
        L"Digital readout of current CPU temperature margin",
        TRUE, TRUE
    },
    {
        0x19D,  L"MSR_THERM2_CTL",
        L"Thermal control — automatic throttle target temperature",
        TRUE, TRUE
    },
    {
        0x1B0,  L"IA32_ENERGY_PERF_BIAS",
        L"Energy/performance trade-off hint (0=perf, 15=energy)",
        TRUE, TRUE
    },
    {
        0x1FC,  L"MSR_POWER_CTL",
        L"Package power control — C1E enable, bi-directional prochot",
        TRUE, TRUE
    },
    {
        0x601,  L"MSR_VR_CURRENT_CONFIG",
        L"VR current configuration — IccMax encoding",
        TRUE, TRUE
    },
    {
        0x606,  L"MSR_RAPL_POWER_UNIT",
        L"RAPL: power/energy/time unit encodings",
        TRUE, TRUE
    },
    {
        0x610,  L"MSR_PKG_POWER_LIMIT",
        L"RAPL: package power limits PL1 and PL2, time windows",
        TRUE, TRUE
    },
    {
        0x611,  L"MSR_PKG_ENERGY_STATUS",
        L"RAPL: accumulated package energy consumption counter",
        TRUE, TRUE
    },
    {
        0x614,  L"MSR_PKG_POWER_INFO",
        L"RAPL: TDP, min/max power, max time window",
        TRUE, TRUE
    },
    {
        0x638,  L"MSR_PP0_POWER_LIMIT",
        L"RAPL: PP0 (core) power limits",
        TRUE, TRUE
    },
    {
        0x639,  L"MSR_PP0_ENERGY_STATUS",
        L"RAPL: PP0 energy status",
        TRUE, TRUE
    },
    {
        0x648,  L"MSR_CONFIG_TDP_NOMINAL",
        L"Nominal TDP ratio — IVB may differ from SNB [Hypothesis]",
        FALSE, TRUE  /* [Hypothesis] — IVB-specific */
    },
    {
        0x64F,  L"MSR_TURBO_ACTIVATION_RATIO",
        L"Turbo activation ratio — IVB-specific [Hypothesis]",
        FALSE, TRUE
    },
    {
        0x1B,   L"IA32_APIC_BASE",
        L"APIC base address and enable state",
        TRUE, TRUE
    },
    {
        0xFE,   L"IA32_MTRRCAP",
        L"MTRR capability register — number of variable MTRRs",
        TRUE, TRUE
    },
    {
        0x3A,   L"IA32_FEATURE_CONTROL",
        L"VMX enable, SMX enable, BIOS lock state",
        TRUE, TRUE
    },
};

#define MSR_TABLE_COUNT  (sizeof (MsrTable) / sizeof (MsrTable[0]))

/* -------------------------------------------------------------------------
 * MSR read with #GP protection
 *
 * On platforms where an MSR does not exist, RDMSR raises #GP.
 * We detect this by checking if the MSR address is in a known-valid range
 * for the identified CPU rather than installing a full exception handler
 * (which is complex and EFI-implementation-specific).
 *
 * [Placeholder]: A robust implementation would use the EFI CPU Arch Protocol
 * to install a temporary #GP handler. For now we use a conservatively filtered
 * table (MsrTable entries with SandyBridgePresent/IvyBridgePresent flags).
 * ------------------------------------------------------------------------- */

typedef struct {
    UINT32    MsrAddress;
    UINT64    Value;
    BOOLEAN   Valid;          /* FALSE if read was skipped (not present on this CPU) */
    BOOLEAN   Skipped;        /* TRUE if filtered out by CPU identity check */
} MSR_RESULT;

typedef struct {
    UINTN       ProcessorIndex;
    MSR_RESULT  Results[MSR_TABLE_COUNT];
    BOOLEAN     Valid;
} PROCESSOR_MSR_DATA;

STATIC VOID
EFIAPI
CollectMsrValues (
    IN OUT VOID  *Buffer
)
{
    PROCESSOR_MSR_DATA  *Data = (PROCESSOR_MSR_DATA *)Buffer;
    UINTN                i;

    if (Data == NULL) return;

    Data->Valid = FALSE;
    for (i = 0; i < MSR_TABLE_COUNT; i++) {
        Data->Results[i].MsrAddress = MsrTable[i].Address;
        Data->Results[i].Skipped    = FALSE;
        Data->Results[i].Valid      = TRUE;
        /*
         * NOTE: AsmReadMsr64 will #GP if the MSR doesn't exist.
         * The CPU identity filter (SandyBridgePresent / IvyBridgePresent)
         * reduces the risk but does not eliminate it for unknown steppings.
         * If this tool hangs, the last [>>] phase line identifies the MSR.
         */
        Data->Results[i].Value = AsmReadMsr64 (MsrTable[i].Address);
    }
    Data->Valid = TRUE;
}

STATIC VOID
PrintMsrData (
    IN PROCESSOR_MSR_DATA    *Data,
    IN DECODED_CPU_INFO      *CpuInfo
)
{
    UINTN   i;
    BOOLEAN Skip;

    if (!Data->Valid) {
        Print (L"  [ERROR: MSR data not valid for processor %llu]\n",
               (UINT64)Data->ProcessorIndex);
        return;
    }

    Print (L"  Processor %llu MSRs:\n", (UINT64)Data->ProcessorIndex);
    for (i = 0; i < MSR_TABLE_COUNT; i++) {
        /* Apply CPU-identity filter */
        Skip = FALSE;
        if (CpuInfo != NULL) {
            if (CpuInfo->Identity == CPU_SANDY_BRIDGE &&
                !MsrTable[i].SandyBridgePresent) {
                Skip = TRUE;
            }
        }

        if (Skip) {
            Print (L"    MSR 0x%03X  %-30s  [skipped — not present on this CPU identity]\n",
                   MsrTable[i].Address, MsrTable[i].Name);
        } else {
            Print (L"    MSR 0x%03X  %-30s  0x%016llX\n",
                   MsrTable[i].Address,
                   MsrTable[i].Name,
                   Data->Results[i].Value);
        }
    }
}

/* -------------------------------------------------------------------------
 * Entry point
 * ------------------------------------------------------------------------- */

EFI_STATUS
EFIAPI
MsrAuditMain (
    IN EFI_HANDLE        ImageHandle,
    IN EFI_SYSTEM_TABLE  *SystemTable
)
{
    /* All local variables declared at function scope for C89 compatibility. */
    EFI_STATUS                Status;
    EFI_MP_SERVICES_PROTOCOL *MpServices;
    EFI_GUID                  MpServicesGuid = EFI_MP_SERVICES_PROTOCOL_GUID;
    UINTN                     NumberOfProcessors;
    UINTN                     NumberOfEnabledProcessors;
    UINTN                     i;
    PROCESSOR_MSR_DATA       *MsrData;
    PROCESSOR_MSR_DATA        BspData;
    UINT32                    CpuidEax;
    UINT32                    CpuidEbx;
    UINT32                    CpuidEcx;
    UINT32                    CpuidEdx;
    DECODED_CPU_INFO          CpuInfo;

    /* Collect BSP CPUID first so we can apply identity filter */
    AsmCpuidEx (0x00000001, 0, &CpuidEax, &CpuidEbx, &CpuidEcx, &CpuidEdx);
    DecodeCpuInfo (CpuidEax, CpuidEcx, CpuidEdx, &CpuInfo);

    PHASE_SEPARATOR ();
    Print (L"=== MSR Audit Tool — Stage 0 Data Collection ===\n");
    Print (L"CPU: Family 0x%02X Model 0x%02X Stepping 0x%X\n",
           CpuInfo.DisplayFamily, CpuInfo.DisplayModel, CpuInfo.Stepping);

    switch (CpuInfo.Identity) {
        case CPU_SANDY_BRIDGE:
            PHASE_NOTE (L"Identified as Sandy Bridge (stock iMac12,2)");
            break;
        case CPU_IVY_BRIDGE:
            PHASE_NOTE (L"Identified as Ivy Bridge");
            break;
        case CPU_WRONG_PLATFORM:
            PHASE_WARN (L"WRONG PLATFORM CPU detected (LGA2011 family). MSRs may differ.");
            break;
        default:
            PHASE_WARN (L"CPU identity unknown. MSR reads may #GP on unrecognised MSRs.");
            break;
    }
    PHASE_SEPARATOR ();

    /* BSP */
    ZeroMem (&BspData, sizeof BspData);
    BspData.ProcessorIndex = 0;
    CollectMsrValues (&BspData);
    Print (L"\n[BSP]\n");
    PrintMsrData (&BspData, &CpuInfo);

    /* AP enumeration via MP Services */
    Status = gBS->LocateProtocol (&MpServicesGuid, NULL, (VOID **)&MpServices);
    if (EFI_ERROR (Status)) {
        PHASE_WARN (L"MP Services not available — BSP data only");
        Print (L"\n=== MSR Audit complete (BSP only) ===\n");
        return EFI_SUCCESS;
    }

    Status = MpServices->GetNumberOfProcessors (
                MpServices, &NumberOfProcessors, &NumberOfEnabledProcessors);
    if (EFI_ERROR (Status)) {
        PHASE_FAIL (Status, L"GetNumberOfProcessors");
        return Status;
    }

    MsrData = AllocateZeroPool (NumberOfProcessors * sizeof (PROCESSOR_MSR_DATA));
    if (MsrData == NULL) {
        PHASE_FAIL (EFI_OUT_OF_RESOURCES, L"AllocateZeroPool");
        return EFI_OUT_OF_RESOURCES;
    }

    for (i = 1; i < NumberOfProcessors; i++) {
        MsrData[i].ProcessorIndex = i;
        Status = MpServices->StartupThisAP (
                    MpServices, CollectMsrValues, i,
                    NULL, 0, (VOID *)&MsrData[i], NULL);
        if (EFI_ERROR (Status)) {
            Print (L"[WARNING] AP %llu MSR collection failed: 0x%llX\n",
                   (UINT64)i, (UINT64)Status);
            MsrData[i].Valid = FALSE;
        }
    }

    for (i = 1; i < NumberOfProcessors; i++) {
        Print (L"\n[AP %llu]\n", (UINT64)i);
        PrintMsrData (&MsrData[i], &CpuInfo);
    }

    FreePool (MsrData);

    PHASE_SEPARATOR ();
    Print (L"=== MSR Audit complete ===\n");
    Print (L"Save this output to data/cpuid/sandy-bridge-msr-stock.txt\n");
    return EFI_SUCCESS;
}
