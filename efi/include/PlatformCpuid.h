/**
 * PlatformCpuid.h — Typed CPUID Structures for Z68 / LGA1155 Platform
 *
 * Status     : [Inference] — field definitions from Intel SDM Vol.2 CPUID;
 *              Sandy Bridge / Ivy Bridge specifics cross-referenced with
 *              Intel 2nd and 3rd Gen Core datasheet. Not validated by
 *              running against the actual iMac12,2 hardware.
 * Credibility: [Inference]
 *
 * Purpose:
 *   Provides typed bitfield structures for the CPUID leaves relevant to
 *   Sandy Bridge (model 0x2A) and Ivy Bridge (model 0x3A) comparison on
 *   the Z68 platform.
 *
 *   These structures are used by CpuidAudit and any future EFI tools that
 *   need to decode CPUID data without inline bit-masking arithmetic.
 *
 *   IMPORTANT: All struct field names ending in _RESERVED must be ignored
 *   and never written back to hardware. They exist to maintain correct
 *   bit positioning only.
 *
 * Reference: Intel 64 and IA-32 Architectures Software Developer's Manual
 *            Volume 2, Chapter 3: CPUID
 */

#ifndef PLATFORM_CPUID_H_
#define PLATFORM_CPUID_H_

#include <Uefi.h>

/* =========================================================================
 * Known model numbers relevant to this project [Inference — Intel SDM]
 * ========================================================================= */

#define CPUID_FAMILY_6              0x06  /* Intel Core family */

#define CPUID_MODEL_SANDY_BRIDGE    0x2A  /* Core 2nd gen, mobile/desktop */
#define CPUID_MODEL_SANDY_BRIDGE_E  0x2D  /* Core 2nd gen, LGA2011 — wrong platform */
#define CPUID_MODEL_IVY_BRIDGE      0x3A  /* Core 3rd gen, mobile/desktop */
#define CPUID_MODEL_IVY_BRIDGE_E    0x3E  /* Core 3rd gen, LGA2011 — wrong platform */
#define CPUID_MODEL_HASWELL         0x3C  /* Core 4th gen */
#define CPUID_MODEL_HASWELL_E       0x3F  /* Core 4th gen, LGA2011-3 — wrong platform */

/* =========================================================================
 * CPUID Leaf 0x00000001 — Version Information
 * EAX: Family, Model, Stepping
 * EBX: Brand index, CLFLUSH size, max addressable logical CPUs, initial APIC ID
 * ECX: Feature flags (part 1)
 * EDX: Feature flags (part 2)
 * ========================================================================= */

/* EAX bitfield */
typedef union {
    struct {
        UINT32  Stepping        : 4;   /* [3:0]   Stepping ID */
        UINT32  Model           : 4;   /* [7:4]   Model (base) */
        UINT32  FamilyId        : 4;   /* [11:8]  Family ID (base) */
        UINT32  ProcessorType   : 2;   /* [13:12] Processor type */
        UINT32  Reserved1       : 2;   /* [15:14] */
        UINT32  ExtendedModelId : 4;   /* [19:16] Extended model */
        UINT32  ExtendedFamilyId: 8;   /* [27:20] Extended family */
        UINT32  Reserved2       : 4;   /* [31:28] */
    } Bits;
    UINT32  Uint32;
} CPUID_VERSION_INFO_EAX;

/* ECX feature flags (leaf 0x01) — relevant subset for this platform */
typedef union {
    struct {
        UINT32  SSE3            : 1;   /* [0]  */
        UINT32  PCLMULQDQ       : 1;   /* [1]  */
        UINT32  DTES64          : 1;   /* [2]  */
        UINT32  MONITOR         : 1;   /* [3]  */
        UINT32  DS_CPL          : 1;   /* [4]  */
        UINT32  VMX             : 1;   /* [5]  Hardware virtualisation */
        UINT32  SMX             : 1;   /* [6]  */
        UINT32  EIST            : 1;   /* [7]  Enhanced SpeedStep */
        UINT32  TM2             : 1;   /* [8]  Thermal Monitor 2 */
        UINT32  SSSE3           : 1;   /* [9]  */
        UINT32  CNXT_ID         : 1;   /* [10] */
        UINT32  SDBG            : 1;   /* [11] */
        UINT32  FMA             : 1;   /* [12] Fused multiply-add — IVB has this; SNB does not */
        UINT32  CMPXCHG16B      : 1;   /* [13] */
        UINT32  xTPR            : 1;   /* [14] */
        UINT32  PDCM            : 1;   /* [15] */
        UINT32  Reserved1       : 1;   /* [16] */
        UINT32  PCID            : 1;   /* [17] */
        UINT32  DCA             : 1;   /* [18] */
        UINT32  SSE4_1          : 1;   /* [19] */
        UINT32  SSE4_2          : 1;   /* [20] */
        UINT32  x2APIC          : 1;   /* [21] */
        UINT32  MOVBE           : 1;   /* [22] */
        UINT32  POPCNT          : 1;   /* [23] */
        UINT32  TSC_Deadline    : 1;   /* [24] */
        UINT32  AESNI           : 1;   /* [25] */
        UINT32  XSAVE           : 1;   /* [26] */
        UINT32  OSXSAVE         : 1;   /* [27] */
        UINT32  AVX             : 1;   /* [28] */
        UINT32  F16C            : 1;   /* [29] IVB has this; SNB does not */
        UINT32  RDRAND          : 1;   /* [30] IVB has this; SNB does not */
        UINT32  NotUsed         : 1;   /* [31] Hypervisor present (convention) */
    } Bits;
    UINT32  Uint32;
} CPUID_VERSION_INFO_ECX;

/* =========================================================================
 * Decoded CPU identification for this platform
 * ========================================================================= */

typedef enum {
    CPU_UNKNOWN        = 0,
    CPU_SANDY_BRIDGE   = 1,   /* Expected: iMac12,2 stock */
    CPU_IVY_BRIDGE     = 2,   /* Upgrade hypothesis target */
    CPU_OTHER_LGA1155  = 3,   /* Celeron/Pentium on LGA1155 — not expected */
    CPU_WRONG_PLATFORM = 4,   /* LGA2011 or other — cannot work on this board */
} PLATFORM_CPU_IDENTITY;

typedef struct {
    UINT32               DisplayFamily;    /* Computed: family + extended family */
    UINT32               DisplayModel;     /* Computed: (ext_model << 4) | model */
    UINT32               Stepping;
    PLATFORM_CPU_IDENTITY Identity;        /* Classified identity */
    BOOLEAN              FmaSupported;     /* ECX[12] — differs SNB vs IVB */
    BOOLEAN              F16cSupported;    /* ECX[29] — differs SNB vs IVB */
    BOOLEAN              RdrandSupported;  /* ECX[30] — differs SNB vs IVB */
    UINT32               RawEax;           /* Raw leaf 0x01 EAX for reference */
    UINT32               RawEcx;           /* Raw leaf 0x01 ECX for reference */
    UINT32               RawEdx;           /* Raw leaf 0x01 EDX for reference */
} DECODED_CPU_INFO;

/* =========================================================================
 * Helper: decode CPUID leaf 0x01 EAX/ECX into DECODED_CPU_INFO
 * ========================================================================= */

/**
 * DecodeCpuInfo — fills a DECODED_CPU_INFO from raw CPUID leaf 0x01 values.
 *
 * [Inference] — DisplayFamily/Model computation per Intel SDM Vol.2 CPUID:
 *   DisplayFamily = (FamilyId == 0xF) ? (FamilyId + ExtFamilyId) : FamilyId
 *   DisplayModel  = (FamilyId == 0x6 || FamilyId == 0xF)
 *                   ? ((ExtModelId << 4) | Model)
 *                   : Model
 */
STATIC INLINE VOID
DecodeCpuInfo (
    IN  UINT32           Eax,
    IN  UINT32           Ecx,
    IN  UINT32           Edx,
    OUT DECODED_CPU_INFO *Info
)
{
    CPUID_VERSION_INFO_EAX  EaxBits;
    CPUID_VERSION_INFO_ECX  EcxBits;

    EaxBits.Uint32 = Eax;
    EcxBits.Uint32 = Ecx;

    Info->RawEax    = Eax;
    Info->RawEcx    = Ecx;
    Info->RawEdx    = Edx;
    Info->Stepping  = EaxBits.Bits.Stepping;

    /* Display Family */
    if (EaxBits.Bits.FamilyId == 0xF) {
        Info->DisplayFamily = EaxBits.Bits.FamilyId + EaxBits.Bits.ExtendedFamilyId;
    } else {
        Info->DisplayFamily = EaxBits.Bits.FamilyId;
    }

    /* Display Model */
    if (EaxBits.Bits.FamilyId == 0x6 || EaxBits.Bits.FamilyId == 0xF) {
        Info->DisplayModel = (EaxBits.Bits.ExtendedModelId << 4) | EaxBits.Bits.Model;
    } else {
        Info->DisplayModel = EaxBits.Bits.Model;
    }

    /* Feature bits that differ between Sandy Bridge and Ivy Bridge */
    Info->FmaSupported    = (BOOLEAN)EcxBits.Bits.FMA;
    Info->F16cSupported   = (BOOLEAN)EcxBits.Bits.F16C;
    Info->RdrandSupported = (BOOLEAN)EcxBits.Bits.RDRAND;

    /* Classify identity */
    if (Info->DisplayFamily == CPUID_FAMILY_6) {
        switch (Info->DisplayModel) {
            case CPUID_MODEL_SANDY_BRIDGE:
                Info->Identity = CPU_SANDY_BRIDGE;
                break;
            case CPUID_MODEL_IVY_BRIDGE:
                Info->Identity = CPU_IVY_BRIDGE;
                break;
            case CPUID_MODEL_SANDY_BRIDGE_E:
            case CPUID_MODEL_IVY_BRIDGE_E:
            case CPUID_MODEL_HASWELL_E:
                Info->Identity = CPU_WRONG_PLATFORM;  /* LGA2011 family */
                break;
            default:
                Info->Identity = CPU_OTHER_LGA1155;
                break;
        }
    } else {
        Info->Identity = CPU_UNKNOWN;
    }
}

/* =========================================================================
 * Sandy Bridge vs. Ivy Bridge expected differences
 * [Inference — Intel product specifications; not validated on hardware]
 *
 * These are the key observable differences at the CPUID level that the
 * audit tool should check for. If the CPU identifies as Sandy Bridge but
 * shows Ivy Bridge features (or vice versa), that is anomalous and should
 * be flagged.
 * ========================================================================= */

/*
 * Sandy Bridge (model 0x2A) expected:
 *   FMA    = 0  (not supported)
 *   F16C   = 0  (not supported)
 *   RDRAND = 0  (not supported)
 *   AVX    = 1  (supported)
 *
 * Ivy Bridge (model 0x3A) expected:
 *   FMA    = 0  (still not supported — FMA came with Haswell)
 *   F16C   = 1  (supported)
 *   RDRAND = 1  (supported)
 *   AVX    = 1  (supported)
 *
 * [Inference] — FMA is Haswell+. Some sources show IVB with FMA in certain
 * stepping/microcode combinations; do not rely on FMA as a definitive IVB marker.
 * F16C and RDRAND are more reliable differentiators.
 */

#endif /* PLATFORM_CPUID_H_ */
