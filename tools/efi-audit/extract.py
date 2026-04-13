#!/usr/bin/env python3
"""
extract.py — EFI Binary Section Extractor

Status     : [Placeholder — not yet tested against Apple iMac12,2 EFI binary]
Credibility: [Inference] — PE32+ parsing is well-documented; Apple EFI quirks unknown

Purpose:
    Extracts raw sections from a PE32+ EFI binary for downstream analysis.
    Produces a directory of section blobs that can be scanned by analyze.py.

    Also supports extracting a binary image from a macOS firmware update
    package (.scap or raw firmware dump), if one is available.

Usage:
    python3 extract.py --input <firmware.bin> --outdir <sections/>
    python3 extract.py --input <firmware.bin> --list-sections

Requirements:
    Python 3.8+
    pefile : pip install pefile

[Placeholder — this tool is a scaffold. The actual Apple EFI binary must be
 obtained from the target iMac before this tool can be validated.
 Source: typically /System/Library/CoreServices/boot.efi or a firmware dump.
 Method: stage0 native-sniff phase; see experiments/stage0-native-sniff/README.md]
"""

import argparse
import json
import sys
from pathlib import Path

try:
    import pefile
    PEFILE_AVAILABLE = True
except ImportError:
    PEFILE_AVAILABLE = False


# ---------------------------------------------------------------------------
# PE32+ section extraction
# ---------------------------------------------------------------------------

def list_sections(pe_path: Path) -> list[dict]:
    """List all sections in a PE32+ binary."""
    if not PEFILE_AVAILABLE:
        raise RuntimeError("pefile library not installed. Run: pip install pefile")

    pe = pefile.PE(str(pe_path))
    sections = []
    for s in pe.sections:
        name = s.Name.rstrip(b"\x00").decode("ascii", errors="replace")
        sections.append({
            "name":             name,
            "virtual_address":  s.VirtualAddress,
            "virtual_size":     s.Misc_VirtualSize,
            "raw_offset":       s.PointerToRawData,
            "raw_size":         s.SizeOfRawData,
            "characteristics":  hex(s.Characteristics),
        })
    pe.close()
    return sections


def extract_sections(pe_path: Path, outdir: Path) -> list[dict]:
    """Extract all PE sections to outdir. Returns manifest."""
    if not PEFILE_AVAILABLE:
        raise RuntimeError("pefile library not installed. Run: pip install pefile")

    outdir.mkdir(parents=True, exist_ok=True)
    pe       = pefile.PE(str(pe_path))
    manifest = []

    seen_names: dict[str, str] = {}  # safe_name → original section name

    for s in pe.sections:
        name      = s.Name.rstrip(b"\x00").decode("ascii", errors="replace")
        safe_name = name.lstrip(".").replace("/", "_").replace("\\", "_") or "unnamed"

        # Detect output filename collisions caused by stripping leading dots.
        # e.g. ".text" and "..text" both map to "text.bin". Disambiguate by
        # appending an index rather than silently overwriting the first section.
        if safe_name in seen_names:
            idx = 2
            candidate = f"{safe_name}_{idx}"
            while candidate in seen_names:
                idx += 1
                candidate = f"{safe_name}_{idx}"
            print(
                f"  WARNING: section {name!r} collides with {seen_names[safe_name]!r} "
                f"after name sanitisation; renaming output to {candidate}.bin",
                file=sys.stderr,
            )
            safe_name = candidate
        seen_names[safe_name] = name

        outfile = outdir / f"{safe_name}.bin"
        data    = s.get_data()
        outfile.write_bytes(data)
        manifest.append({
            "name":    name,
            "outfile": str(outfile),
            "size":    len(data),
        })
        print(f"  Extracted: {name!r} → {outfile} ({len(data)} bytes)", file=sys.stderr)

    pe.close()
    return manifest


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Extract sections from a PE32+ EFI binary."
    )
    p.add_argument("--input",    required=True, help="Input EFI PE32+ binary")
    p.add_argument("--outdir",   default="sections",
                   help="Output directory for extracted sections (default: sections/)")
    p.add_argument("--list-sections", action="store_true",
                   help="Print section list and exit (do not extract)")
    p.add_argument("--manifest", help="Write extraction manifest to JSON file")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    src  = Path(args.input)

    if not src.exists():
        print(f"ERROR: input not found: {src}", file=sys.stderr)
        return 1

    if not PEFILE_AVAILABLE:
        print(
            "ERROR: pefile library not installed.\n"
            "Install it with: pip install pefile",
            file=sys.stderr,
        )
        return 1

    if args.list_sections:
        sections = list_sections(src)
        print(json.dumps(sections, indent=2))
        return 0

    manifest = extract_sections(src, Path(args.outdir))

    if args.manifest:
        Path(args.manifest).write_text(json.dumps(manifest, indent=2))
        print(f"Manifest written to: {args.manifest}", file=sys.stderr)

    print(f"Extracted {len(manifest)} sections to {args.outdir}/", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
