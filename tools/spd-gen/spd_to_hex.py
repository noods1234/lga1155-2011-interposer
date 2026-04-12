#!/usr/bin/env python3
"""
spd_to_hex.py — Convert validated SPD binary to Verilog $readmemh hex format

Status     : [Verified design pattern]
Credibility: [Verified] — $readmemh hex format is well-defined

Purpose:
    Converts a validated 256-byte SPD binary to a hex file suitable for
    Verilog $readmemh initialization of the spd_responder ROM.

    Must be run AFTER validate_spd.py passes. Never synthesize an FPGA image
    with an SPD hex file that has not passed validation.

Usage:
    python3 spd_to_hex.py --input <validated.bin> --output <spd_rom.hex>

Output format:
    One hex byte per line (no address prefix), suitable for:
        $readmemh("spd_rom.hex", spd_rom);
    where spd_rom is declared as: reg [7:0] spd_rom [0:255];
"""

import argparse
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Convert validated SPD binary to Verilog $readmemh hex."
    )
    p.add_argument("--input",  required=True, help="Validated SPD binary (256 bytes)")
    p.add_argument("--output", required=True, help="Output hex file path")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    src  = Path(args.input)

    if not src.exists():
        print(f"ERROR: file not found: {src}", file=sys.stderr)
        return 1

    data = src.read_bytes()
    if len(data) != 256:
        print(f"ERROR: expected 256 bytes, got {len(data)}", file=sys.stderr)
        return 1

    lines = [f"{b:02X}" for b in data]
    Path(args.output).write_text("\n".join(lines) + "\n")
    print(f"Wrote {len(lines)} entries to {args.output}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
