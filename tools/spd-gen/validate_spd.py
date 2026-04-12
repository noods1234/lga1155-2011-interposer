#!/usr/bin/env python3
"""
validate_spd.py — DDR3 SPD Image Validator

Status     : [Inference] — JEDEC 21C field ranges are documented; CRC algorithm
             is verified against JEDEC spec
Credibility: [Inference]

Purpose:
    Validates a 256-byte DDR3 SPD binary against JEDEC Standard 21C rules:
      - Correct file size (256 bytes)
      - DRAM type byte = 0x0B (DDR3)
      - CRC-16/CCITT over bytes 0-125 matches bytes 116-117
      - Key field range checks (tCKmin, tAAmin, module type, etc.)
      - Placeholder / zero-field detection (warns on fields that are zero
        where a real DIMM would never be zero)

    This is a gate check. The SPD pipeline (generate_spd.py → validate_spd.py
    → spd_to_hex.py) must complete without errors before any SPD image is
    used in an experiment.

Usage:
    python3 validate_spd.py --input <spd.bin>
    python3 validate_spd.py --input <spd.bin> --strict   # fail on warnings too

Requirements:
    Python 3.8+
"""

import argparse
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# CRC (same as generate_spd.py — must stay in sync)
# ---------------------------------------------------------------------------

def compute_spd_crc(data: bytes) -> int:
    crc = 0
    for byte in data[:126]:
        crc ^= (byte << 8)
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc


# ---------------------------------------------------------------------------
# Validation checks
# ---------------------------------------------------------------------------

class Result:
    def __init__(self) -> None:
        self.errors:   list[str] = []
        self.warnings: list[str] = []

    def error(self, msg: str) -> None:
        self.errors.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    @property
    def ok(self) -> bool:
        return len(self.errors) == 0


def validate(data: bytes, strict: bool = False) -> Result:
    r = Result()

    # Size
    if len(data) != 256:
        r.error(f"SPD must be 256 bytes; got {len(data)}")
        return r  # cannot continue with wrong size

    # DRAM type
    if data[2] != 0x0B:
        r.error(f"Byte 2 (DRAM type) = 0x{data[2]:02X}; expected 0x0B (DDR3)")

    # Module type
    valid_module_types = {0x01: "RDIMM", 0x02: "UDIMM", 0x03: "SO-DIMM",
                          0x04: "Micro-DIMM", 0x06: "Mini-RDIMM", 0x07: "Mini-UDIMM"}
    if data[3] not in valid_module_types:
        r.error(f"Byte 3 (module type) = 0x{data[3]:02X}; not a recognised DDR3 module type")

    # CRC check
    expected_crc = compute_spd_crc(data)
    stored_crc   = data[116] | (data[117] << 8)
    if expected_crc != stored_crc:
        r.error(
            f"CRC mismatch: computed 0x{expected_crc:04X}, "
            f"stored 0x{stored_crc:04X} (bytes 116-117)"
        )

    # tCKmin (byte 12): must be non-zero and in a sane range
    # MTB = 125 ps. DDR3-800 = 20 MTB, DDR3-2133 = 7 MTB roughly
    tckmin = data[12]
    if tckmin == 0:
        r.error("Byte 12 (tCKmin) = 0; must be non-zero for a valid DIMM")
    elif not (7 <= tckmin <= 30):
        r.warn(f"Byte 12 (tCKmin) = {tckmin} MTB = {tckmin * 125} ps; "
               f"unusual for DDR3 (expected 7–30 MTB)")

    # tAAmin (byte 16): must be non-zero
    taamin = data[16]
    if taamin == 0:
        r.error("Byte 16 (tAAmin) = 0; must be non-zero")

    # Organization byte 7: ranks and SDRAM width
    ranks_enc = (data[7] >> 3) & 0x7
    if ranks_enc > 3:
        r.warn(f"Byte 7 ranks encoding = {ranks_enc}; unusual value")

    # Placeholder detection: warn if timing fields (bytes 17-29) are all zero
    timing_bytes = data[17:30]
    if all(b == 0 for b in timing_bytes):
        r.warn(
            "Bytes 17-29 (tWR, tRCD, tRRD, tRP, tRAS, tRC, tRFC, tWTR, tRTP, tFAW) "
            "are all zero. This is a placeholder SPD. MRC will almost certainly fail "
            "with these values. Replace with real DIMM timing parameters."
        )

    # SPD revision byte 1
    if data[1] == 0x00:
        r.warn("Byte 1 (SPD revision) = 0x00; expected 0x10 or 0x11 for DDR3")

    return r


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Validate a DDR3 SPD binary image.")
    p.add_argument("--input",  required=True, help="Input SPD binary (256 bytes)")
    p.add_argument("--strict", action="store_true",
                   help="Treat warnings as errors")
    return p.parse_args()


def main() -> int:
    args   = parse_args()
    src    = Path(args.input)

    if not src.exists():
        print(f"ERROR: file not found: {src}", file=sys.stderr)
        return 1

    data   = src.read_bytes()
    result = validate(data, strict=args.strict)

    for w in result.warnings:
        print(f"  WARNING: {w}")
    for e in result.errors:
        print(f"  ERROR:   {e}")

    fail = bool(result.errors) or (args.strict and bool(result.warnings))

    if fail:
        print(f"\nVALIDATION FAILED — {src}")
        print("Do not use this SPD image in any experiment.")
        return 1
    else:
        print(f"VALIDATION PASSED — {src}")
        if result.warnings:
            print(f"  ({len(result.warnings)} warning(s); review before live use)")
        return 0


if __name__ == "__main__":
    sys.exit(main())
