#!/usr/bin/env python3
"""
generate_spd.py — DDR3 SPD Image Generator

Status     : [Inference] — JEDEC 21C byte layout is well-documented; output
             must be validated by validate_spd.py before use in any experiment
Credibility: [Inference]

Purpose:
    Generates a 256-byte DDR3 SPD image conforming to JEDEC Standard 21C
    (SPD for DDR3 SDRAM Modules). The generated image is suitable for:
      - Programming into an I2C EEPROM
      - Loading into the FPGA spd_responder ROM via $readmemh
      - Reference / baseline comparison

    Output is a binary file. Use spd_to_hex.py to convert to hex for FPGA ROM.

    WARNING: Generated SPD must pass validate_spd.py CRC checks and field
    range validation before use. Never use a raw generated SPD in a live
    experiment without validation.

    WARNING: The DIMM timing parameters must match the actual installed DIMM.
    Using incorrect timing parameters (e.g., wrong CAS latency, wrong tRCD)
    may cause memory training failure or data corruption.
    Use the actual DIMM SPD data (from Stage 0 capture) as the baseline.

JEDEC references:
    - JEDEC Standard No. 21C, Annex L: SPD for DDR3 SDRAM
    - SPD bytes 0–127: basic module info (CRC over bytes 0–125)
    - SPD bytes 128–255: module-specific, manufacturer info

Usage:
    python3 generate_spd.py --config <spd_config.json> --output <out.bin>
    python3 generate_spd.py --dump-default-config    # print placeholder config and exit
    python3 generate_spd.py --help

Requirements:
    Python 3.8+
"""

import argparse
import json
import struct
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# SPD byte layout constants (JEDEC 21C Annex L, DDR3)
# All offsets are decimal byte addresses
# ---------------------------------------------------------------------------

SPD_SIZE = 256

# Byte 0: Number of bytes used / Number of bytes in SPD
SPD_BYTES_USED_TOTAL = 0
# Byte 1: SPD revision
SPD_REVISION = 1
# Byte 2: Key byte / DRAM device type
SPD_DRAM_TYPE = 2
# Byte 3: Key byte / Module type (UDIMM, SO-DIMM, etc.)
SPD_MODULE_TYPE = 3
# Byte 4: SDRAM density and banks
SPD_DENSITY_BANKS = 4
# Byte 5: Addressing (Row/Column bits)
SPD_ADDRESSING = 5
# Byte 6: Module nominal voltage
SPD_VOLTAGE = 6
# Byte 7: Module organization
SPD_ORGANIZATION = 7
# Byte 8: Bus width
SPD_BUS_WIDTH = 8
# Byte 9: Fine timebase (MTB) FTB [ps]
SPD_FTB = 9
# Byte 10: Medium timebase (MTB) dividend
SPD_MTB_DIVIDEND = 10
# Byte 11: Medium timebase (MTB) divisor
SPD_MTB_DIVISOR = 11
# Byte 12: tCKmin (minimum cycle time)
SPD_TCKMIN = 12
# Byte 14: CAS latencies supported (low)
SPD_CAS_LAT_LOW = 14
# Byte 15: CAS latencies supported (high)
SPD_CAS_LAT_HIGH = 15
# Byte 16: Minimum CAS latency time (tAAmin)
SPD_TAAMIN = 16
# Byte 17: tWRmin
SPD_TWRMIN = 17
# Byte 18: tRCDmin
SPD_TRCDMIN = 18
# Byte 19: tRRDmin
SPD_TRRDMIN = 19
# Byte 20: tRPmin
SPD_TRPMIN = 20
# Byte 21: Upper nibbles for tRAS and tRC
SPD_TRAS_TRC_UPPER = 21
# Byte 22: tRASmin LSB
SPD_TRASMIN_LSB = 22
# Byte 23: tRCmin LSB
SPD_TRCMIN_LSB = 23
# Bytes 24-25: tRFCmin
SPD_TRFCMIN_LSB = 24
SPD_TRFCMIN_MSB = 25
# Byte 26: tWTRmin
SPD_TWTRMIN = 26
# Byte 27: tRTPmin
SPD_TRTPMIN = 27
# Byte 28-29: tFAWmin
SPD_TFAWMIN_UPPER = 28
SPD_TFAWMIN_LSB = 29
# Byte 41: Fine offset for tRCDmin [Placeholder — FTB fields]
# Bytes 116-117: CRC for bytes 0-125
SPD_CRC_LOW = 116
SPD_CRC_HIGH = 117

# DRAM type: DDR3 = 0x0B
DRAM_TYPE_DDR3 = 0x0B

# Module types
MODULE_TYPE_RDIMM  = 0x01
MODULE_TYPE_UDIMM  = 0x02
MODULE_TYPE_SO_DIMM = 0x03

# Voltage: 1.5V operable = bit 0 clear, 1.35V operable = bit 1 set
VOLTAGE_150 = 0x00   # 1.5V only
VOLTAGE_135 = 0x02   # 1.35V and 1.5V


# ---------------------------------------------------------------------------
# CRC calculation (JEDEC 21C Annex L Section 4.1.2.L)
# ---------------------------------------------------------------------------

def compute_spd_crc(data: bytes) -> int:
    """
    Compute CRC-16/CCITT over bytes 0-125 of SPD.
    This is the standard CRC used by DDR3 SPD.
    Returns 16-bit CRC value.
    """
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
# SPD generation
# ---------------------------------------------------------------------------

# Default configuration for a generic DDR3-1333 8 GB SO-DIMM
# [Placeholder — replace with actual DIMM parameters from Stage 0 SPD capture]
DEFAULT_CONFIG = {
    "_note": "PLACEHOLDER — replace with actual DIMM parameters from Stage 0 data/spd/ capture",
    "_credibility": "Placeholder",
    "module_type":   "SO-DIMM",
    "capacity_mb":   8192,
    "speed_mhz":     1333,
    "cas_latency":   9,
    "data_width":    64,
    "ranks":         2,
    "sdram_width":   8,
    "voltage":       1.5,
    "manufacturer":  "PLACEHOLDER",
    "part_number":   "PLACEHOLDER",
}


def build_spd_from_config(config: dict) -> bytes:
    """
    Build a 256-byte DDR3 SPD image from a config dict.
    Returns bytes.

    [Placeholder — this generates a structurally valid SPD skeleton.
     Many fields are set to placeholder/zero values. The output MUST pass
     validate_spd.py before use. Timing fields in particular must be derived
     from the actual DIMM's datasheet or a measured SPD capture.]
    """
    spd = bytearray(SPD_SIZE)

    # Byte 0: bits [6:4] = bytes total (001 = 256), bits [3:0] = bytes used (0011 = 256)
    # → 0b0_001_0011 = 0x13   (was 0x92, which encoded an invalid/reserved combination)
    spd[SPD_BYTES_USED_TOTAL] = 0x13

    # Byte 1: SPD revision 1.0
    spd[SPD_REVISION] = 0x10

    # Byte 2: DRAM type = DDR3
    spd[SPD_DRAM_TYPE] = DRAM_TYPE_DDR3

    # Byte 3: Module type
    module_type_map = {
        "RDIMM":   MODULE_TYPE_RDIMM,
        "UDIMM":   MODULE_TYPE_UDIMM,
        "SO-DIMM": MODULE_TYPE_SO_DIMM,
    }
    spd[SPD_MODULE_TYPE] = module_type_map.get(config.get("module_type", "SO-DIMM"),
                                                MODULE_TYPE_SO_DIMM)

    # Byte 4: Density and banks [Placeholder — hardcoded for 8Gb device with 8 banks]
    # Bits [3:0]: total capacity per die (0101 = 8Gb)
    # Bits [5:4]: number of banks (01 = 8 banks)
    # [Placeholder — must match actual DRAM die density]
    spd[SPD_DENSITY_BANKS] = 0x15  # PLACEHOLDER

    # Byte 5: Addressing [Placeholder — 15 row bits, 10 column bits]
    # bits [5:3]: row address bits (010 = 15 rows)
    # bits [2:0]: col address bits (000 = 10 cols)
    # → 0b00_010_000 = 0x10   (was 0x19 = reserved 16 rows + 11 cols, wrong)
    spd[SPD_ADDRESSING] = 0x10  # PLACEHOLDER

    # Byte 6: Voltage
    spd[SPD_VOLTAGE] = VOLTAGE_150 if config.get("voltage", 1.5) >= 1.5 else VOLTAGE_135

    # Byte 7: Organization (ranks, SDRAM width)
    # Bits [5:3]: number of package ranks per DIMM
    #   000=1 rank, 001=2 ranks, 010=4 ranks  (per JEDEC 21C Table 7)
    # Bits [2:0]: SDRAM device width
    #   000=x4, 001=x8, 010=x16              (per JEDEC 21C Table 7)
    # Previous encodings were wrong: ranks[4]=0b011 and width[8]=0b011 (32-bit device).
    ranks_enc = {1: 0b000, 2: 0b001, 4: 0b010}
    width_enc = {4: 0b000, 8: 0b001, 16: 0b010}
    r = ranks_enc.get(config.get("ranks", 2), 0b001)
    w = width_enc.get(config.get("sdram_width", 8), 0b011)
    spd[SPD_ORGANIZATION] = (r << 3) | w

    # Byte 8: Bus width (011 = 64-bit, no ECC; 100 = 64-bit + 8-bit ECC)
    spd[SPD_BUS_WIDTH] = 0x03  # 64-bit bus, no ECC [Placeholder]

    # Bytes 9, 10, 11: MTB = 1/8 ns (FTB = 1 ps fine timebase)
    spd[SPD_FTB]          = 0x01   # FTB = 1 ps
    spd[SPD_MTB_DIVIDEND] = 0x01   # MTB dividend = 1
    spd[SPD_MTB_DIVISOR]  = 0x08   # MTB divisor  = 8 → MTB = 125 ps

    # Byte 12: tCKmin in MTB units
    # DDR3-1333: tCK = 1500 ps → 1500/125 = 12 MTB units
    # DDR3-1600: tCK = 1250 ps → 1250/125 = 10 MTB units
    speed_to_tck_mtb = {1333: 12, 1600: 10, 1066: 15, 800: 20}
    spd[SPD_TCKMIN] = speed_to_tck_mtb.get(config.get("speed_mhz", 1333), 12)

    # Bytes 14-15: CAS latencies supported [Placeholder — DDR3-1333 CL9/10/11]
    spd[SPD_CAS_LAT_LOW]  = 0xFE  # CL 7-14 supported [Placeholder]
    spd[SPD_CAS_LAT_HIGH] = 0x00

    # Byte 16: tAAmin [Placeholder — CL9 at DDR3-1333 = 13500 ps = 108 MTB = 0x6C]
    spd[SPD_TAAMIN] = 0x6C  # 108 MTB × 125 ps = 13500 ps = CL9 at 1333 MHz [Placeholder]
                             # (was 0x69 = 13125 ps, which contradicted the comment)

    # Remaining timing bytes [Placeholder — all zeros until replaced with real data]
    # tWRmin, tRCDmin, tRRDmin, tRPmin, tRAS, tRC, tRFC, tWTR, tRTP, tFAW
    # These MUST be populated from the actual DIMM datasheet or Stage 0 capture.
    # Using zero values will likely cause MRC training failure.
    # See data/spd/ for reference captured SPD images.

    # Compute and insert CRC (bytes 116-117)
    crc = compute_spd_crc(bytes(spd))
    spd[SPD_CRC_LOW]  = crc & 0xFF
    spd[SPD_CRC_HIGH] = (crc >> 8) & 0xFF

    return bytes(spd)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Generate a DDR3 SPD image from a configuration file."
    )
    p.add_argument("--config", help="JSON configuration file (see DEFAULT_CONFIG for format)")
    p.add_argument("--output", required=True, help="Output binary file path")
    p.add_argument("--dump-default-config", action="store_true",
                   help="Print default config JSON and exit")
    return p.parse_args()


def main() -> int:
    args = parse_args()

    if args.dump_default_config:
        print(json.dumps(DEFAULT_CONFIG, indent=2))
        return 0

    config = DEFAULT_CONFIG.copy()
    if args.config:
        config.update(json.loads(Path(args.config).read_text()))

    if config.get("_credibility") == "Placeholder":
        print(
            "WARNING: Using default placeholder configuration.\n"
            "         The timing fields are incomplete. This SPD will fail MRC.\n"
            "         Replace with actual DIMM parameters from Stage 0 capture.\n"
            "         See data/spd/ for reference SPD images.\n",
            file=sys.stderr,
        )

    spd = build_spd_from_config(config)
    Path(args.output).write_bytes(spd)
    print(f"SPD image written: {args.output} ({len(spd)} bytes)", file=sys.stderr)
    print("Run validate_spd.py on the output before any use.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
