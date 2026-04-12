#!/usr/bin/env python3
"""
patchgen.py — EFI Binary Patch Generator

Status     : [Hypothesis — patch logic is a concept; no patch has been tested
              against the actual Apple iMac12,2 EFI binary]
Credibility: [Hypothesis]

Purpose:
    Generates binary patches for EFI firmware based on the output of analyze.py.
    Patches are written as diff-style records (offset, original_bytes,
    replacement_bytes) for review and application by validate.py.

    PATCHES ARE NOT APPLIED BY THIS TOOL. This tool only generates the patch
    record. Application is a separate step that requires explicit confirmation.

EXPERIMENT GATES:
    Certain patch types are gated behind named experiment profiles. These are
    NOT production operations. They must not be enabled without explicit
    intent and documentation.

    --profile mrc-nop-hypothesis  [EXPERIMENT ONLY — see below]

    The --nop-mrc / mrc-nop-hypothesis profile:
        Replaces an identified MRC call sequence with NOP instructions.
        WARNING: This will almost certainly cause memory initialization failure,
        system hang, or data corruption. It is a diagnostic experiment to
        characterize what happens when MRC is bypassed, not a usable mode.
        Requires:
          - Stage 0 baseline data committed
          - Explicit entry in docs/risk-register.md for this experiment
          - Physical recovery method verified (CMOS clear, known-good boot)
        If you are reading this and wondering whether to use --profile mrc-nop-hypothesis:
        The answer is no, unless you have completed all the above and explicitly
        intend to observe the failure mode.

Usage:
    python3 patchgen.py --analysis <report.json> --profile cpuid-audit-nop
    python3 patchgen.py --analysis <report.json> --profile mrc-nop-hypothesis \
        --experiment-gate-confirmed
    python3 patchgen.py --list-profiles

Requirements:
    Python 3.8+
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Optional


# ---------------------------------------------------------------------------
# Patch profiles
# ---------------------------------------------------------------------------

PROFILES = {
    "cpuid-log-only": {
        "description": "Insert a breakpoint (INT3) before each high-confidence CPUID "
                       "reference for debugging. Non-destructive when used with a "
                       "debugger attached.",
        "experiment_gate": False,
        "patches": "dynamic",   # computed from analysis output
        "credibility": "Hypothesis",
    },
    "mrc-nop-hypothesis": {
        "description": (
            "EXPERIMENT ONLY. Replaces the identified MRC call site with NOP "
            "instructions. WILL CAUSE BOOT FAILURE. Purpose: observe exact "
            "failure mode of MRC bypass for diagnostic characterization. "
            "See docs/risk-register.md R-003."
        ),
        "experiment_gate": True,  # requires --experiment-gate-confirmed
        "patches": "dynamic",
        "credibility": "Hypothesis",
        "risk_register_ref": "R-003",
        "warning": (
            "THIS PATCH WILL PREVENT THE SYSTEM FROM BOOTING. "
            "Ensure you have a physical recovery method before applying. "
            "See docs/risk-register.md R-003."
        ),
    },
}


# ---------------------------------------------------------------------------
# Patch generation
# ---------------------------------------------------------------------------

def generate_cpuid_log_patches(analysis: dict) -> list[dict]:
    """
    Generate INT3 (0xCC) insertion patches before each high-confidence CPUID
    reference. These are for use with a hardware debugger only.
    """
    patches = []
    for match in analysis.get("matches", []):
        if match["confidence"] == "high":
            offset      = match["offset_dec"]
            orig_bytes  = bytes.fromhex(match["match_hex"])
            # Replace first 2 bytes with INT3, INT3 — for debugger trap
            # NOTE: This is destructive. Only use with debugger attached.
            # [Hypothesis — not validated]
            patch_bytes = bytes([0xCC, 0xCC]) + orig_bytes[2:]
            patches.append({
                "offset_hex":     f"0x{offset:08X}",
                "offset_dec":     offset,
                "original_hex":   orig_bytes.hex(),
                "replacement_hex": patch_bytes.hex(),
                "description":    f"INT3 trap before {match['pattern']}",
                "credibility":    "Hypothesis",
                "applied":        False,
            })
    return patches


def generate_mrc_nop_patches(analysis: dict) -> list[dict]:
    """
    [EXPERIMENT ONLY] Locate what appears to be the MRC call site and NOP it.

    [Placeholder — MRC call site identification is NOT implemented.
     This function is a structural stub. To implement it:
     1. Obtain the actual Apple EFI binary from the iMac
     2. Disassemble and identify the MRC initialization call sequence
     3. Document the exact offset and byte sequence
     4. Implement the pattern here with VERIFIED credibility
     Until then this returns an empty list with an explanatory note.]
    """
    return [{
        "note": (
            "PLACEHOLDER — MRC call site pattern not yet identified. "
            "Complete Stage 0 oscilloscope/EFI analysis before implementing. "
            "This patch profile is structurally reserved; it generates no patches."
        ),
        "credibility": "Placeholder",
        "applied": False,
    }]


def generate_patches(profile_name: str, analysis: dict) -> dict:
    profile = PROFILES.get(profile_name)
    if profile is None:
        raise ValueError(f"Unknown profile: {profile_name!r}")

    if profile_name == "cpuid-log-only":
        patch_list = generate_cpuid_log_patches(analysis)
    elif profile_name == "mrc-nop-hypothesis":
        patch_list = generate_mrc_nop_patches(analysis)
    else:
        patch_list = []

    return {
        "tool":          "patchgen.py",
        "version":       "0.1.0",
        "profile":       profile_name,
        "description":   profile["description"],
        "credibility":   profile["credibility"],
        "experiment":    profile["experiment_gate"],
        "warning":       profile.get("warning", None),
        "patch_count":   len(patch_list),
        "patches":       patch_list,
        "applied":       False,
        "instructions": (
            "Review each patch. Then use validate.py --apply to apply. "
            "validate.py will re-check offsets against the original binary "
            "before writing anything."
        ),
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Generate EFI binary patches from analysis report."
    )
    p.add_argument("--analysis", help="Path to analyze.py JSON output")
    p.add_argument("--profile",  help="Patch profile to apply")
    p.add_argument("--output",   help="Write patch record to JSON file (default: stdout)")
    p.add_argument(
        "--experiment-gate-confirmed",
        action="store_true",
        help="Required for experiment-gated profiles. Confirms you understand the risk.",
    )
    p.add_argument("--list-profiles", action="store_true",
                   help="List available patch profiles and exit")
    return p.parse_args()


def main() -> int:
    args = parse_args()

    if args.list_profiles:
        for name, info in PROFILES.items():
            gate = "[EXPERIMENT GATE REQUIRED]" if info["experiment_gate"] else ""
            print(f"  {name:30s} {gate}")
            print(f"    {info['description'][:80]}")
        return 0

    if not args.analysis or not args.profile:
        print("ERROR: --analysis and --profile are required", file=sys.stderr)
        return 1

    profile = PROFILES.get(args.profile)
    if profile is None:
        print(f"ERROR: unknown profile: {args.profile!r}", file=sys.stderr)
        return 1

    if profile["experiment_gate"] and not args.experiment_gate_confirmed:
        print(
            f"\nERROR: Profile '{args.profile}' is an EXPERIMENT and requires "
            f"--experiment-gate-confirmed.\n"
            f"Read the profile description carefully before using this flag:\n"
            f"  {profile['description']}\n",
            file=sys.stderr,
        )
        return 1

    analysis_path = Path(args.analysis)
    if not analysis_path.exists():
        print(f"ERROR: analysis file not found: {analysis_path}", file=sys.stderr)
        return 1

    analysis = json.loads(analysis_path.read_text())
    result   = generate_patches(args.profile, analysis)
    json_out = json.dumps(result, indent=2)

    if args.output:
        Path(args.output).write_text(json_out)
    else:
        print(json_out)

    return 0


if __name__ == "__main__":
    sys.exit(main())
