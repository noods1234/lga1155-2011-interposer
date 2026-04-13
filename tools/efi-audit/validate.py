#!/usr/bin/env python3
"""
validate.py — Patch Validator and Application Tool

Status     : [Placeholder — not yet tested against a real binary]
Credibility: [Inference] — validation logic is structurally correct

Purpose:
    1. Validates a patch record (from patchgen.py) against the original binary:
       checks that each patch's original_hex bytes match the bytes at the
       specified offset in the binary.
    2. Optionally applies validated patches to produce a patched output binary.

    Validation always runs before application. If any patch fails validation,
    no patches are applied.

    This is the last gate before any EFI binary modification. Do not skip it.

Usage:
    python3 validate.py --binary <firmware.bin> --patches <patches.json> --check
    python3 validate.py --binary <firmware.bin> --patches <patches.json> \
        --apply --output <patched.bin>

WARNING:
    Applying patches to a system EFI binary is a hardware-risk operation.
    A corrupt EFI binary can brick the system. Always:
    1. Keep a verified backup of the original binary.
    2. Have a recovery path (e.g., Apple Internet Recovery, ROM programmer).
    3. Only flash the patched binary using a method that can be reversed.

Requirements:
    Python 3.8+
"""

import argparse
import json
import shutil
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

class ValidationError(Exception):
    pass


def validate_patches(binary: bytes, patches: list[dict]) -> list[dict]:
    """
    Validate all patches against the binary.
    Returns list of validation results; raises ValidationError if any fail.
    """
    results = []
    has_failure = False

    for i, patch in enumerate(patches):
        # Skip metadata-only entries (Placeholder stubs)
        if "offset_dec" not in patch:
            results.append({
                "patch_index": i,
                "status":      "skipped",
                "reason":      patch.get("note", "No offset — likely a placeholder"),
            })
            continue

        offset       = patch["offset_dec"]
        expected_hex = patch["original_hex"]
        expected     = bytes.fromhex(expected_hex)
        length       = len(expected)

        if offset + length > len(binary):
            results.append({
                "patch_index":  i,
                "status":       "FAIL",
                "reason":       f"Offset 0x{offset:08X} + {length} bytes exceeds binary size",
                "offset_hex":   f"0x{offset:08X}",
            })
            has_failure = True
            continue

        actual = binary[offset: offset + length]
        if actual == expected:
            results.append({
                "patch_index":    i,
                "status":         "ok",
                "offset_hex":     f"0x{offset:08X}",
                "expected_hex":   expected_hex,
                "actual_hex":     actual.hex(),
            })
        else:
            results.append({
                "patch_index":    i,
                "status":         "FAIL",
                "reason":         "Original bytes do not match",
                "offset_hex":     f"0x{offset:08X}",
                "expected_hex":   expected_hex,
                "actual_hex":     actual.hex(),
            })
            has_failure = True

    if has_failure:
        raise ValidationError(
            "One or more patches failed validation. "
            "No patches have been applied. "
            "See validation results for details."
        )

    return results


def apply_patches(binary: bytes, patches: list[dict]) -> bytes:
    """
    Apply all validated patches to binary. Returns modified bytes.
    Caller must have run validate_patches() first.
    """
    data = bytearray(binary)
    applied_count = 0

    for patch in patches:
        if "offset_dec" not in patch or not patch.get("replacement_hex"):
            continue
        offset       = patch["offset_dec"]
        replacement  = bytes.fromhex(patch["replacement_hex"])
        data[offset: offset + len(replacement)] = replacement
        applied_count += 1

    print(f"Applied {applied_count} patches.", file=sys.stderr)
    return bytes(data)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Validate and optionally apply EFI binary patches."
    )
    p.add_argument("--binary",  required=True, help="Original EFI binary")
    p.add_argument("--patches", required=True, help="Patch record JSON from patchgen.py")
    p.add_argument("--check",   action="store_true",
                   help="Validate patches only; do not apply")
    p.add_argument("--apply",   action="store_true",
                   help="Apply patches after validation")
    p.add_argument("--output",  help="Output path for patched binary (required with --apply)")
    p.add_argument("--results", help="Write validation results to JSON file")
    return p.parse_args()


def main() -> int:
    args = parse_args()

    if args.apply and not args.output:
        print("ERROR: --apply requires --output", file=sys.stderr)
        return 1

    binary_path = Path(args.binary)
    patch_path  = Path(args.patches)

    if not binary_path.exists():
        print(f"ERROR: binary not found: {binary_path}", file=sys.stderr)
        return 1
    if not patch_path.exists():
        print(f"ERROR: patches file not found: {patch_path}", file=sys.stderr)
        return 1

    binary      = binary_path.read_bytes()
    patch_doc   = json.loads(patch_path.read_text())
    patch_list  = patch_doc.get("patches", [])

    print(f"Binary:  {binary_path} ({len(binary)} bytes)", file=sys.stderr)
    print(f"Patches: {len(patch_list)} entries", file=sys.stderr)

    # Warn if experiment-gated profile
    if patch_doc.get("experiment"):
        print(
            f"\nWARNING: This patch set is from an EXPERIMENT profile "
            f"({patch_doc.get('profile', 'unknown')}).\n"
            f"{patch_doc.get('warning', '')}\n",
            file=sys.stderr,
        )

    results = None
    try:
        results = validate_patches(binary, patch_list)
        print(f"Validation: PASS ({len(results)} checks)", file=sys.stderr)
    except ValidationError as e:
        print(f"\nValidation: FAIL\n{e}", file=sys.stderr)
        if args.results and results is not None:
            Path(args.results).write_text(json.dumps(results, indent=2))
            print(f"Partial results written to: {args.results}", file=sys.stderr)
        return 1

    if args.results:
        Path(args.results).write_text(json.dumps(results, indent=2))

    if args.apply:
        patched = apply_patches(binary, patch_list)
        # Safety: backup original alongside output
        backup = Path(args.output).with_suffix(".original.bin")
        shutil.copy2(binary_path, backup)
        print(f"Backup of original written to: {backup}", file=sys.stderr)
        Path(args.output).write_bytes(patched)
        print(f"Patched binary written to: {args.output}", file=sys.stderr)
        print(
            "\nIMPORTANT: Verify the patched binary before flashing.\n"
            "Keep the .original.bin backup in a safe location.",
            file=sys.stderr,
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
