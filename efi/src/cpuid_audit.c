/**
 * cpuid_audit.c — EFI Application: Read-Only CPUID Audit
 *
 * Status     : [Inference] — typed EFI protocol access pattern; not yet compiled
 *              or tested against Apple EFI on iMac12,2
 * Credibility: [Inference]
 *
 * Purpose:
 *   Reads and reports CPUID leaves from the boot CPU and all APs (application
 *   processors) via the EFI MP Services Protocol. Outputs results to the EFI
 *   serial debug port and, optionally, a file on the EFI System Partition.
 *
 *   This is a READ-ONLY audit tool. It does not modify CPUID, MSRs, or any
 *   platform state. It is the first EFI deliverable for Stage 0.
 *
 * What this is NOT:
 *   - Not a CPUID spoofer or masker (that is Stage 2+ work, separate file)
 *   - Not a replacement for haswell_e_cpuid.c (that file is rejected)
 *   - Not dependent on hard-coded protocol function pointer offsets
 *
 * Protocol access:
 *   All protocols are obtained via gBS->LocateProtocol() with typed GUIDs.
 *   No hand-rolled offset arithmetic. No cast-from-void-pointer protocol access.
 *
 * Build requirements:
 *   EDK II build environment. Add to a module's INF file:
 *     [LibraryClasses]
 *       UefiLib
 *       UefiApplicationEntryPoint
 *       SerialPortLib (or DebugLib with UART backend)
 *     [Protocols]
 *       gEfiMpServiceProtocolGuid
 *
 * Tested on: [Placeholder — not yet compiled or tested]
 * Target EFI: Apple EFI on iMac12,2 [Placeholder — compatibility unknown]
 */

#include <Uefi.h>
#include <Library/UefiLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/DebugLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Library/BaseMemoryLib.h>
#include <Protocol/MpService.h>

/* -------------------------------------------------------------------------
 * CPUID leaf collection
 * ------------------------------------------------------------------------- */

typedef struct {
    UINT32  Eax;
    UINT32  Ebx;
    UINT32  Ecx;
    UINT32  Edx;
} CPUID_REGS;

typedef struct {
    UINTN       ProcessorIndex;
    CPUID_REGS  Leaves[64];   /* Up to 64 leaves per processor */
    UINTN       LeafCount;
    BOOLEAN     Valid;
} PROCESSOR_CPUID_DATA;

/*
 * Leaves to capture. Sandy Bridge supports up to 0xD (with sub-leaves).
 * Extended leaves start at 0x80000000.
 * This list covers the minimum set needed for Sandy Bridge vs. Ivy Bridge
 * comparison. Add leaves as needed.
 */
static UINT32 StandardLeaves[] = {
    0x00000000,   /* Max standard leaf + vendor string */
    0x00000001,   /* Family / Model / Stepping + Feature flags */
    0x00000002,   /* Cache/TLB descriptors */
    0x00000003,   /* Processor serial (deprecated; Sandy Bridge: reserved) */
    0x00000004,   /* Cache topology (use ECX=0..N) */
    0x00000006,   /* Thermal / power management features */
    0x00000007,   /* Structured extended features (ECX=0) */
    0x0000000A,   /* Architectural PMU */
    0x0000000B,   /* Extended topology enumeration */
    0x0000000D,   /* XSAVE features (ECX=0) */
    /* Extended */
    0x80000000,   /* Max extended leaf */
    0x80000001,   /* Extended features */
    0x80000002,   /* Brand string part 1 */
    0x80000003,   /* Brand string part 2 */
    0x80000004,   /* Brand string part 3 */
    0x80000006,   /* L2 cache info */
    0x80000007,   /* Advanced power management */
    0x80000008,   /* Address size info */
};
#define STANDARD_LEAF_COUNT (sizeof(StandardLeaves) / sizeof(StandardLeaves[0]))

/**
 * CpuidExWrapper — inline CPUID with both EAX and ECX inputs.
 * Avoids using compiler-specific intrinsics for portability across EDK II.
 */
STATIC VOID
CpuidEx (
    IN  UINT32       Leaf,
    IN  UINT32       SubLeaf,
    OUT CPUID_REGS  *Regs
)
{
    AsmCpuidEx (Leaf, SubLeaf, &Regs->Eax, &Regs->Ebx, &Regs->Ecx, &Regs->Edx);
}

/**
 * CollectCpuidLeaves — called on each processor via MP services.
 * Buffer parameter points to PROCESSOR_CPUID_DATA for this processor.
 */
STATIC VOID
EFIAPI
CollectCpuidLeaves (
    IN OUT VOID  *Buffer
)
{
    PROCESSOR_CPUID_DATA  *Data = (PROCESSOR_CPUID_DATA *)Buffer;
    UINTN                  i;

    if (Data == NULL) {
        return;
    }

    Data->LeafCount = 0;
    Data->Valid     = FALSE;

    for (i = 0; i < STANDARD_LEAF_COUNT && Data->LeafCount < 64; i++) {
        CpuidEx (StandardLeaves[i], 0, &Data->Leaves[Data->LeafCount]);
        Data->LeafCount++;
    }

    Data->Valid = TRUE;
}

/* -------------------------------------------------------------------------
 * Output formatting
 * ------------------------------------------------------------------------- */

STATIC VOID
PrintCpuidData (
    IN PROCESSOR_CPUID_DATA  *Data
)
{
    UINTN   i;

    if (!Data->Valid) {
        Print (L"  [ERROR: data not valid for processor %llu]\n",
               (UINT64)Data->ProcessorIndex);
        return;
    }

    Print (L"  Processor %llu CPUID:\n", (UINT64)Data->ProcessorIndex);
    for (i = 0; i < Data->LeafCount; i++) {
        Print (
            L"    Leaf 0x%08X: EAX=0x%08X EBX=0x%08X ECX=0x%08X EDX=0x%08X\n",
            StandardLeaves[i],
            Data->Leaves[i].Eax,
            Data->Leaves[i].Ebx,
            Data->Leaves[i].Ecx,
            Data->Leaves[i].Edx
        );
    }

    /* Decode Family/Model/Stepping from leaf 0x01 EAX for quick reference */
    {
        UINT32  Eax      = Data->Leaves[1].Eax; /* Leaf index 1 = leaf 0x00000001 */
        UINT32  Stepping = Eax & 0xF;
        UINT32  Model    = (Eax >> 4) & 0xF;
        UINT32  Family   = (Eax >> 8) & 0xF;
        UINT32  ExtModel = (Eax >> 16) & 0xF;
        UINT32  ExtFamily= (Eax >> 20) & 0xFF;
        UINT32  DispModel, DispFamily;

        /* Intel display model / family calculation per SDM Vol.2 CPUID */
        DispFamily = (Family == 0xF) ? (Family + ExtFamily) : Family;
        DispModel  = (Family == 0x6 || Family == 0xF)
                       ? ((ExtModel << 4) | Model)
                       : Model;

        Print (
            L"    --> DisplayFamily=0x%02X DisplayModel=0x%02X Stepping=0x%01X\n",
            DispFamily, DispModel, Stepping
        );

        /* Known models on this platform [Inference] */
        if (DispFamily == 0x06 && DispModel == 0x2A)
            Print (L"    --> IDENTIFIED AS: Sandy Bridge (expected on iMac12,2 stock)\n");
        else if (DispFamily == 0x06 && DispModel == 0x3A)
            Print (L"    --> IDENTIFIED AS: Ivy Bridge\n");
        else
            Print (L"    --> UNRECOGNIZED MODEL for this platform\n");
    }
}

/* -------------------------------------------------------------------------
 * EFI Application Entry Point
 * ------------------------------------------------------------------------- */

EFI_STATUS
EFIAPI
CpuidAuditMain (
    IN EFI_HANDLE        ImageHandle,
    IN EFI_SYSTEM_TABLE  *SystemTable
)
{
    EFI_STATUS                Status;
    EFI_MP_SERVICES_PROTOCOL *MpServices;
    EFI_GUID                  MpServicesGuid = EFI_MP_SERVICES_PROTOCOL_GUID;
    UINTN                     NumberOfProcessors;
    UINTN                     NumberOfEnabledProcessors;
    UINTN                     i;
    PROCESSOR_CPUID_DATA     *CpuidData;

    Print (L"\n=== CPUID Audit Tool — Stage 0 Data Collection ===\n");
    Print (L"Platform: iMac12,2 / Z68 / LGA1155 [expected]\n");
    Print (L"NOTE: This tool is read-only. It does not modify any platform state.\n\n");

    /*
     * Collect BSP CPUID first (always accessible without MP services)
     */
    PROCESSOR_CPUID_DATA BspData;
    ZeroMem (&BspData, sizeof BspData);
    BspData.ProcessorIndex = 0;
    CollectCpuidLeaves (&BspData);

    Print (L"[BSP]\n");
    PrintCpuidData (&BspData);

    /*
     * Attempt to locate MP Services Protocol for AP enumeration.
     * If unavailable (e.g., single-processor, or Apple EFI does not expose it),
     * log a note but do not fail.
     */
    Status = gBS->LocateProtocol (
                    &MpServicesGuid,
                    NULL,
                    (VOID **)&MpServices
                 );
    if (EFI_ERROR (Status)) {
        Print (
            L"[NOTE] EFI_MP_SERVICES_PROTOCOL not available (Status=0x%llX).\n"
            L"       AP CPUID collection skipped. BSP data only.\n",
            (UINT64)Status
        );
        Print (L"\n=== Audit complete (BSP only) ===\n");
        return EFI_SUCCESS;
    }

    Status = MpServices->GetNumberOfProcessors (
                            MpServices,
                            &NumberOfProcessors,
                            &NumberOfEnabledProcessors
                         );
    if (EFI_ERROR (Status)) {
        Print (L"[ERROR] GetNumberOfProcessors failed: 0x%llX\n", (UINT64)Status);
        return Status;
    }

    Print (
        L"Processors total=%llu enabled=%llu\n",
        (UINT64)NumberOfProcessors,
        (UINT64)NumberOfEnabledProcessors
    );

    /* Allocate per-processor data buffers */
    CpuidData = AllocateZeroPool (NumberOfProcessors * sizeof (PROCESSOR_CPUID_DATA));
    if (CpuidData == NULL) {
        Print (L"[ERROR] AllocateZeroPool failed\n");
        return EFI_OUT_OF_RESOURCES;
    }

    for (i = 0; i < NumberOfProcessors; i++) {
        CpuidData[i].ProcessorIndex = i;
    }

    /*
     * Dispatch collection to each AP sequentially.
     * We use StartupThisAP rather than StartupAllAPs to keep error handling simple.
     */
    for (i = 1; i < NumberOfProcessors; i++) {
        Status = MpServices->StartupThisAP (
                                MpServices,
                                CollectCpuidLeaves,
                                i,
                                NULL,   /* no WaitEvent — blocking */
                                0,      /* no timeout */
                                (VOID *)&CpuidData[i],
                                NULL
                             );
        if (EFI_ERROR (Status)) {
            Print (L"[WARNING] StartupThisAP for processor %llu failed: 0x%llX\n",
                   (UINT64)i, (UINT64)Status);
            CpuidData[i].Valid = FALSE;
        }
    }

    /* Print all AP results */
    for (i = 1; i < NumberOfProcessors; i++) {
        Print (L"\n[AP %llu]\n", (UINT64)i);
        PrintCpuidData (&CpuidData[i]);
    }

    FreePool (CpuidData);

    Print (L"\n=== Audit complete ===\n");
    Print (L"Save this output to data/cpuid/ for Stage 0 baseline.\n");

    return EFI_SUCCESS;
}
