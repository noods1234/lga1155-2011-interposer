/*
 * SSDT-PMC-z68-reference.dsl
 *
 * Status     : Reference fragment only — NOT ready to apply
 * Credibility: [Inference] — Z68/Cougar Point device model is internally
 *              coherent; must be verified against real iMac12,2 DSDT before use
 *
 * Source     : Salvaged from noods1234/apple-set-os,
 *              branch claude/haswell-interposer-imac-lcEvg
 * Salvage decision: Keep with light review (see docs/salvage-audit.md)
 *
 * Purpose:
 *   Provides an ACPI SSDT fragment that adds or corrects the PMC (Power
 *   Management Controller) device entry for the Intel Z68 / Cougar Point PCH.
 *
 *   On some platforms the PMC device is missing from the DSDT, causing macOS
 *   to log "ACPI: no _HID on device" warnings or fail to load power management
 *   support. This SSDT adds it under the correct PCI path.
 *
 * Z68 / Cougar Point device assignment [Inference from Intel Z68 EDS]:
 *   PMC  : PCI Bus 0, Device 31, Function 2  (0x1F:0x02) — Storage controller
 *          NOTE: The exact function assignment for PMC vs. storage varies by
 *          PCH stepping and BIOS implementation. Verify against actual DSDT.
 *   SBUS : PCI Bus 0, Device 31, Function 3  (0x1F:0x03) — SMBus controller
 *          This is the correct SBUS assignment for Cougar Point.
 *
 * IMPORTANT — DO NOT APPLY WITHOUT CHECKING:
 *   1. Run `acpidump` on the target iMac12,2 (Stage 0 task T0.3)
 *   2. Decompile the DSDT with `iasl -d dsdt.dat`
 *   3. Search for existing _SB.PCI0.PMC, _SB.PCI0.PPMC, _SB.PCI0.SBUS entries
 *   4. If PMC / PPMC already exists in DSDT: this SSDT is UNNECESSARY and
 *      applying it will cause an ACPI conflict (duplicate device definition)
 *   5. If SBUS already exists correctly: do not duplicate it
 *   6. Only apply the parts of this SSDT for devices that are missing
 *
 * Correction from old branch:
 *   The previous version of this file contained a mistaken PPMC device
 *   declaration that conflicted with standard Cougar Point ACPI tables.
 *   That declaration has been removed. Only SBUS (D31:F3) is retained here
 *   as the primary reference fragment, since it is the more stable and
 *   well-documented entry.
 *
 * Compile with:
 *   iasl -tc SSDT-PMC-z68-reference.dsl
 * Place compiled .aml in OpenCore EFI/OC/ACPI/ and reference in config.plist.
 * OpenCore config is in opencore/config/ (not yet created — Stage 2+ only).
 */

DefinitionBlock ("", "SSDT", 2, "IPOSER", "SBUSFIX", 0x00000001)
{
    External (_SB_.PCI0, DeviceObj)

    Scope (_SB.PCI0)
    {
        /*
         * SBUS — SMBus Host Controller
         * Intel Z68 / Cougar Point: PCI Bus 0, Device 31, Function 3
         * _ADR encoding: (Device << 16) | Function = 0x001F0003
         *
         * Credibility: [Inference] — D31:F3 for SMBus is correct for
         * Cougar Point per Intel PCH EDS. Verify _ADR against real DSDT.
         *
         * This entry is needed if macOS fails to attach the SMBus driver,
         * which can prevent proper thermal sensor and SPD access from the OS.
         * Note: the interposer SMBus monitor operates at the hardware level
         * and does not depend on this ACPI entry being present.
         */
        Device (SBUS)
        {
            Name (_ADR, 0x001F0003)  // D31:F3 — SMBus [Inference]
            Name (_STA, 0x0F)        // Present, enabled, functional, visible

            /*
             * DVL0 — named object placeholder
             * Some macOS SMBus kext versions look for this node.
             * [Hypothesis — presence/absence may depend on macOS version]
             */
            Device (DVL0)
            {
                Name (_ADR, 0x00)
                Name (_STA, 0x0F)
            }
        }

        /*
         * PLACEHOLDER: PMC device entry
         *
         * If the iMac12,2 DSDT is missing a PMC device entry AND macOS
         * requires one, add it here after verifying the correct _ADR.
         *
         * For Z68 / Cougar Point, PMC is typically at D31:F2 (0x001F0002).
         * However, D31:F2 on Cougar Point is also the SATA controller in some
         * configurations. Verify before adding.
         *
         * DO NOT UNCOMMENT without verifying against the real DSDT.
         *
         * Device (PMC)
         * {
         *     Name (_ADR, 0x001F0002)  // PLACEHOLDER — verify D31:F2 assignment
         *     Name (_HID, EisaId ("APP9876"))  // PLACEHOLDER — verify with macOS kext
         *     Name (_STA, 0x0F)
         * }
         */
    }
}
