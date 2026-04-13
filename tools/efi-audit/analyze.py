#!/usr/bin/env python3
"""
analyze.py — EFI Binary CPUID Reference Scanner

Status     : Rewrite of analyze_efi_cpuid.py from apple-set-os branch
Credibility: [Inference] — pattern matching is sound in principle; patterns
             are derived from x86 CPUID instruction encoding and must be
             validated against the actual Apple EFI binary from iMac12,2.

Purpose:
    Scans a PE32+ EFI binary (or a raw extracted section) for CPUID instruction
    sequences and surrounding code patterns. Produces a structured JSON report
    of all CPUID call sites found.

    This is an analysis tool only. It does not patch, modify, or generate
    new binaries. Patch generation is in patchgen.py.

Salvage note:
    Core pattern-matching logic is preserved from the old branch's
    analyze_efi_cpuid.py. The following changes were made in this rewrite:
    - Split into this file (analysis only) vs. patchgen.py (patching) vs.
      validate.py (validation) vs. extract.py (binary extraction)
    - --nop-mrc flag removed from this tool; it belongs in patchgen.py
      behind an experiment profile
    - Output is now structured JSON, not ad-hoc text
    - Patterns are listed with metadata (name, bytes, confidence)
    - File is importable as a library by other tools

Usage:
    python3 analyze.py --input <efi_section.bin> --output <report.json>
    python3 analyze.py --input <efi_section.bin> --print-summary

Requirements:
    Python 3.8+
    pefile (optional, for PE parsing): pip install pefile
"""

import argparse
import json
import struct
import sys
from pathlib import Path
from typing import NamedTuple, Optional


# ---------------------------------------------------------------------------
# CPUID instruction patterns
# ---------------------------------------------------------------------------
# x86 CPUID instruction: 0F A2
# We look for sequences that set EAX (and optionally ECX) before CPUID.
# Each pattern has:
#   name        : human-readable description
#   pre_bytes   : bytes expected immediately before CPUID (if any)
#   cpuid_bytes : the CPUID opcode itself (always 0F A2)
#   confidence  : "high" if the pattern is very specific, "low" if broad
#
# [Inference]: These patterns are typical x86 compiler output for CPUID calls.
# They must be validated against disassembly of the actual Apple EFI binary.
# Do NOT use confidence="high" for patterns not confirmed against real binary.

CPUID_OPCODE = bytes([0x0F, 0xA2])

PATTERNS = [
    {
        "name":       "cpuid_raw",
        "description": "Bare CPUID instruction (any preceding code)",
        "match_bytes": CPUID_OPCODE,
        "confidence":  "low",   # [Inference]
        "context_before": 16,   # bytes before to capture for context
        "context_after":  16,
    },
    {
        "name":       "cpuid_leaf1_check",
        "description": "MOV EAX,1 / CPUID — likely querying family/model/stepping",
        "match_bytes": bytes([0xB8, 0x01, 0x00, 0x00, 0x00,  # MOV EAX, 1
                              0x0F, 0xA2]),                   # CPUID
        "confidence":  "high",  # [Inference — well-known compiler pattern]
        "context_before": 0,
        "context_after":  32,
    },
    {
        "name":       "cpuid_leaf0_check",
        "description": "XOR EAX,EAX / CPUID — leaf 0 (max leaf + vendor)",
        "match_bytes": bytes([0x31, 0xC0,   # XOR EAX, EAX
                              0x0F, 0xA2]), # CPUID
        "confidence":  "high",  # [Inference]
        "context_before": 0,
        "context_after":  32,
    },
    {
        "name":       "cpuid_family_compare",
        "description": "Pattern following CPUID where EAX is compared (family/model check)",
        "match_bytes": CPUID_OPCODE + bytes([0x89, 0xC3]),  # CPUID; MOV EBX, EAX (common after CPUID)
        "confidence":  "low",   # [Hypothesis — compiler-dependent]
        "context_before": 8,
        "context_after":  64,
    },
]

# Known CPUID model values relevant to this project [Inference from Intel SDM]
KNOWN_MODELS = {
    0x2A: "Sandy Bridge (expected: iMac12,2 stock)",
    0x3A: "Ivy Bridge (target for upgrade hypothesis)",
    0x3C: "Haswell",
    0x3F: "Haswell-E (WRONG PLATFORM — LGA2011-3, not LGA1155)",
    0x4F: "Broadwell-E (WRONG PLATFORM)",
}


# ---------------------------------------------------------------------------
# Data types
# ---------------------------------------------------------------------------

class CpuidMatch(NamedTuple):
    pattern_name:   str
    offset:         int
    match_bytes:    bytes
    context_before: bytes
    context_after:  bytes
    confidence:     str


# ---------------------------------------------------------------------------
# Core scanning logic
# ---------------------------------------------------------------------------

def scan_binary(data: bytes) -> list[CpuidMatch]:
    """
    Scan raw binary data for all known CPUID patterns.
    Returns a list of CpuidMatch, sorted by offset.
    """
    matches = []

    for pattern in PATTERNS:
        needle     = pattern["match_bytes"]
        ctx_before = pattern["context_before"]
        ctx_after  = pattern["context_after"]
        start      = 0

        while True:
            idx = data.find(needle, start)
            if idx == -1:
                break

            before = data[max(0, idx - ctx_before): idx]
            after  = data[idx + len(needle): idx + len(needle) + ctx_after]

            matches.append(CpuidMatch(
                pattern_name   = pattern["name"],
                offset         = idx,
                match_bytes    = data[idx: idx + len(needle)],
                context_before = before,
                context_after  = after,
                confidence     = pattern["confidence"],
            ))
            start = idx + 1

    matches.sort(key=lambda m: m.offset)
    return matches


def deduplicate(matches: list[CpuidMatch], window: int = 8) -> list[CpuidMatch]:
    """
    Remove duplicate matches within `window` bytes of each other.
    Prefer higher-confidence matches when deduplicating.
    """
    if not matches:
        return []

    confidence_order = {"high": 0, "low": 1}
    result = [matches[0]]
    for m in matches[1:]:
        prev = result[-1]
        if m.offset - prev.offset < window:
            # Keep whichever has higher confidence
            if confidence_order.get(m.confidence, 99) < confidence_order.get(prev.confidence, 99):
                result[-1] = m
        else:
            result.append(m)
    return result


# ---------------------------------------------------------------------------
# Report generation
# ---------------------------------------------------------------------------

def match_to_dict(m: CpuidMatch) -> dict:
    return {
        "pattern":        m.pattern_name,
        "offset_hex":     f"0x{m.offset:08X}",
        "offset_dec":     m.offset,
        "match_hex":      m.match_bytes.hex(),
        "confidence":     m.confidence,
        "context_before": m.context_before.hex(),
        "context_after":  m.context_after.hex(),
    }


def generate_report(data: bytes, source_path: str) -> dict:
    """
    Full analysis report as a dict (suitable for JSON serialization).
    """
    raw_matches = scan_binary(data)
    matches     = deduplicate(raw_matches)

    high_confidence = [m for m in matches if m.confidence == "high"]
    low_confidence  = [m for m in matches if m.confidence == "low"]

    report = {
        "tool":            "analyze.py",
        "version":         "0.1.0",
        "credibility":     "Inference",
        "source_file":     source_path,
        "binary_size":     len(data),
        "summary": {
            "total_matches":           len(matches),
            "high_confidence_matches": len(high_confidence),
            "low_confidence_matches":  len(low_confidence),
            "note":  (
                "Patterns are heuristic. High-confidence matches should be "
                "disassembled and verified manually before any patching. "
                "This tool does not generate patches."
            ),
        },
        "matches": [match_to_dict(m) for m in matches],
        "known_model_reference": {
            f"0x{k:02X}": v for k, v in KNOWN_MODELS.items()
        },
    }
    return report


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Scan EFI binary for CPUID instruction references."
    )
    p.add_argument("--input",  required=True,
                   help="Path to input EFI binary section (raw bytes)")
    p.add_argument("--output",
                   help="Write JSON report to this file (default: stdout)")
    p.add_argument("--print-summary", action="store_true",
                   help="Print human-readable summary to stderr")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    src  = Path(args.input)

    if not src.exists():
        print(f"ERROR: input file not found: {src}", file=sys.stderr)
        return 1

    data   = src.read_bytes()
    report = generate_report(data, str(src))

    json_out = json.dumps(report, indent=2)

    if args.output:
        Path(args.output).write_text(json_out)
    else:
        print(json_out)

    if args.print_summary:
        s = report["summary"]
        print(
            f"\nSummary for: {args.input}\n"
            f"  Total CPUID references found : {s['total_matches']}\n"
            f"  High confidence              : {s['high_confidence_matches']}\n"
            f"  Low confidence               : {s['low_confidence_matches']}\n"
            f"  Note: {s['note']}\n",
            file=sys.stderr,
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
