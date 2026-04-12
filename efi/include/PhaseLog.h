/**
 * PhaseLog.h — Phase Logging Macros for EFI Tools
 *
 * Status     : [Verified design pattern]
 * Credibility: [Verified] — standard EFI print wrapper; no platform assumptions
 *
 * Purpose:
 *   Provides lightweight macros for logging sequential phase transitions in
 *   EFI applications. Each phase emits a labelled line so that if the
 *   application hangs or returns an error, the last printed line identifies
 *   the exact failure point.
 *
 *   This is important for Apple EFI debugging where there is no JTAG and
 *   the only observable output may be the screen or a serial port.
 *
 * Usage:
 *   #include "PhaseLog.h"
 *
 *   PHASE_BEGIN("Locating MP Services Protocol");
 *   Status = gBS->LocateProtocol(...);
 *   if (EFI_ERROR(Status)) {
 *       PHASE_FAIL(Status, "MP Services not available");
 *       return Status;
 *   }
 *   PHASE_OK("MP Services located");
 *
 * Output format on screen / serial:
 *   [>>] Locating MP Services Protocol
 *   [OK] MP Services located
 *
 *   [>>] Some later phase
 *   [!!] FAIL (Status=0x800000000000000E): Some later phase
 *
 * Requires: UefiLib (Print), UefiBootServicesTableLib (optional for timestamp)
 */

#ifndef PHASE_LOG_H_
#define PHASE_LOG_H_

#include <Uefi.h>
#include <Library/UefiLib.h>

/* -------------------------------------------------------------------------
 * Core phase macros
 * ------------------------------------------------------------------------- */

/**
 * PHASE_BEGIN(msg) — announce start of a named phase
 * Use this immediately before the operation that could fail.
 * If the system hangs after this line, the hang is in this phase.
 */
#define PHASE_BEGIN(msg)  \
    Print (L"[>>] " msg L"\n")

/**
 * PHASE_OK(msg) — phase completed successfully
 */
#define PHASE_OK(msg)     \
    Print (L"[OK] " msg L"\n")

/**
 * PHASE_FAIL(Status, msg) — phase failed; print EFI status code
 * Does NOT return or abort — caller is responsible for control flow.
 */
#define PHASE_FAIL(Status, msg)   \
    Print (L"[!!] FAIL (Status=0x%llX): " msg L"\n", (UINT64)(Status))

/**
 * PHASE_NOTE(msg) — informational annotation (not a phase transition)
 */
#define PHASE_NOTE(msg)   \
    Print (L"[--] " msg L"\n")

/**
 * PHASE_WARN(msg) — non-fatal warning
 */
#define PHASE_WARN(msg)   \
    Print (L"[~~] WARN: " msg L"\n")

/**
 * PHASE_VALUE(label, fmt, val) — print a labelled value
 * Example: PHASE_VALUE("CPUID EAX", "0x%08X", eax);
 */
#define PHASE_VALUE(label, fmt, val) \
    Print (L"      " label L" = " fmt L"\n", (val))

/**
 * PHASE_SEPARATOR — visual separator between major sections
 */
#define PHASE_SEPARATOR() \
    Print (L"------------------------------------------------------------\n")

/* -------------------------------------------------------------------------
 * EFI_ERROR check helper
 *
 * Usage:
 *   PHASE_BEGIN("LocateProtocol");
 *   Status = gBS->LocateProtocol(...);
 *   PHASE_CHECK_RETURN(Status, "LocateProtocol failed");
 *   PHASE_OK("Protocol located");
 *
 * If Status is an error, prints the failure and returns Status from the
 * enclosing function. The enclosing function must return EFI_STATUS.
 * ------------------------------------------------------------------------- */
#define PHASE_CHECK_RETURN(Status, msg)         \
    do {                                         \
        if (EFI_ERROR (Status)) {                \
            PHASE_FAIL ((Status), (msg));        \
            return (Status);                     \
        }                                        \
    } while (0)

/**
 * PHASE_CHECK_WARN — same but does not return; logs warning and continues
 */
#define PHASE_CHECK_WARN(Status, msg)            \
    do {                                         \
        if (EFI_ERROR (Status)) {                \
            PHASE_WARN (msg);                    \
            Print (L"      (Status=0x%llX)\n",   \
                   (UINT64)(Status));            \
        }                                        \
    } while (0)

#endif /* PHASE_LOG_H_ */
