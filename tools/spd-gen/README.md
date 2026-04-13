# SPD Generation Pipeline

**Status**: Implemented; not yet validated against a real DIMM or MRC  
**Credibility**: [Inference] — JEDEC 21C byte layout is documented; end-to-end pipeline untested on hardware

---

## Purpose

Generates and validates DDR3 SPD images for use in the FPGA `spd_responder` module. Replaces
the hard-coded SPD bytes from the old `fpga_ddr_bridge.v` with a reproducible, auditable pipeline.

**Absolute rules:**
- Never hand-edit SPD bytes.
- Never use an SPD image that has not passed `validate_spd.py`.
- Never synthesize an FPGA bitstream with an SPD hex file from any source other than this pipeline.
- Never use a generated SPD as a substitute for a captured SPD in any live experiment.

---

## Usable vs. Placeholder Decision Table

| Situation | Action |
|-----------|--------|
| Stage 0 SPD capture complete (`data/spd/s0*-spd-dimm_*.bin` present) | Use captured binary as gold standard; run `validate_spd.py` on it to confirm it is well-formed |
| Stage 0 not yet complete | Generated SPD is **[Placeholder]** only — do not load into FPGA for live experiments |
| Need FPGA-loadable ROM for bench continuity test (no live memory traffic) | Generated SPD acceptable; `_credibility` field in config must say `"Placeholder"` |
| MRC memory training test | **Must use captured SPD**, or a generated SPD derived from captured parameters and validated to match |

The timing bytes (17–29) are the hard gate. An all-zero timing block is caught by `validate_spd.py`
as an **error** (not a warning) and will cause MRC training failure.

---

## Pipeline

```bash
# ── Stage 0 complete path ────────────────────────────────────────────────────

# Step 1: Capture real DIMM SPD in Stage 0 (task T0.5)
#   Result: data/spd/s0-spd-dimm_a1-YYYYMMDD-01.bin  ← gold standard

# Step 2: Validate the captured binary
python3 validate_spd.py --input data/spd/s0-spd-dimm_a1-YYYYMMDD-01.bin --strict

# Step 3: Decode captured bytes and build a config JSON
#   (manual step: read decode-dimms output or SPD viewer and fill in config)
#   See "Config Format" section below.

# Step 4: Generate from config (produces a config-derived image for comparison)
python3 generate_spd.py --config my_dimm.json --output generated.bin

# Step 5: Validate the generated image
python3 validate_spd.py --input generated.bin --strict

# Step 6: Compare generated image against capture byte-by-byte
python3 - <<'EOF'
import sys
cap = open("data/spd/s0-spd-dimm_a1-YYYYMMDD-01.bin", "rb").read()
gen = open("generated.bin", "rb").read()
diffs = [(i, cap[i], gen[i]) for i in range(256) if cap[i] != gen[i]]
if diffs:
    print(f"MISMATCH: {len(diffs)} byte(s) differ")
    for i, c, g in diffs:
        print(f"  byte {i:3d} (0x{i:02X}): captured=0x{c:02X}  generated=0x{g:02X}")
    sys.exit(1)
else:
    print("MATCH: generated image is byte-identical to captured SPD")
EOF

# Step 7: Convert to FPGA ROM hex (only after validation passes)
python3 spd_to_hex.py --input generated.bin --output ../../fpga/rtl/spd_rom.hex

# ── Placeholder-only path (bench test, no live memory traffic) ───────────────

python3 generate_spd.py --dump-default-config > placeholder.json
python3 generate_spd.py --config placeholder.json --output placeholder.bin
python3 validate_spd.py --input placeholder.bin
#  ↑ This WILL report errors for zero timing bytes. That is correct behavior.
#  Do not pass --strict; do not use this image for memory training.
```

---

## Config Format

The JSON config passed to `generate_spd.py --config` maps to JEDEC 21C SPD fields.
Generate the default scaffold with:

```bash
python3 generate_spd.py --dump-default-config
```

```json
{
  "_note": "PLACEHOLDER — replace with actual DIMM parameters from Stage 0 data/spd/ capture",
  "_credibility": "Placeholder",
  "module_type":  "SO-DIMM",
  "capacity_mb":  8192,
  "speed_mhz":    1333,
  "cas_latency":  9,
  "data_width":   64,
  "ranks":        2,
  "sdram_width":  8,
  "voltage":      1.5,
  "manufacturer": "PLACEHOLDER",
  "part_number":  "PLACEHOLDER"
}
```

| Config key | SPD byte | JEDEC field | Notes |
|------------|----------|-------------|-------|
| `module_type` | 3 | Key byte / Module type | `"SO-DIMM"`, `"UDIMM"`, `"RDIMM"` |
| `speed_mhz` | 12 | tCKmin | 1333 → 12 MTB, 1600 → 10 MTB (MTB = 125 ps) |
| `cas_latency` | 16 | tAAmin | CL9 @ DDR3-1333 = 0x6C (108 MTB = 13500 ps) |
| `ranks` | 7 bits [5:3] | Package ranks | 1→000, 2→001, 4→010 |
| `sdram_width` | 7 bits [2:0] | SDRAM device width | x4→000, x8→001, x16→010 |
| `voltage` | 6 | Nominal voltage | 1.5V → 0x00, 1.35V → 0x02 |

**Timing fields not yet in the config** (bytes 17–29) are zeroed by default and must be
populated manually from the captured DIMM's datasheet or decoded SPD data before live use.

---

## Forbidden Zero Timing Bytes

The following bytes are **always errors** in `validate_spd.py` when all are zero:

| Byte | JEDEC field | Unit | Typical DDR3-1333 value |
|------|-------------|------|------------------------|
| 17 | tWRmin | MTB | 0x0C (15 ns = 120 MTB at 125 ps/MTB) |
| 18 | tRCDmin | MTB | 0x07 (13.75 ns ≈ 11 MTB) |
| 19 | tRRDmin | MTB | 0x05 (7.5 ns ≈ 6 MTB) |
| 20 | tRPmin | MTB | 0x07 (13.75 ns ≈ 11 MTB) |
| 21 | tRAS/tRC upper nibbles | — | upper nibbles of bytes 22/23 |
| 22 | tRASmin LSB | MTB | 0x21 (33 MTB × 125 ps = 37.5 ns) |
| 23 | tRCmin LSB | MTB | 0x28 (40 MTB × 125 ps = 50 ns) |
| 24–25 | tRFCmin | MTB | varies by die density |
| 26 | tWTRmin | MTB | 0x04 (4 MTB × 125 ps = 7.5 ns) |
| 27 | tRTPmin | MTB | 0x04 |
| 28–29 | tFAWmin | MTB | 0x2D (45 ns ÷ 125 ps = 45 MTB for 1Kib page) |

These values are **[Inference]** (JEDEC typical; your DIMM may differ). Use the Stage 0
captured SPD image for authoritative values.

---

## Validation Rules

`validate_spd.py` enforces the following:

**Hard errors** (always fail, cannot be suppressed):

| Check | Byte(s) | Condition |
|-------|---------|-----------|
| File size | — | Must be exactly 256 bytes |
| DRAM type | 2 | Must be 0x0B (DDR3) |
| CRC | 116–117 | CRC-16/CCITT over bytes 0–125 must match |
| tCKmin nonzero | 12 | Zero means no clock defined |
| tAAmin nonzero | 16 | Zero means no CAS latency defined |
| Byte 0 = 0x92 | 0 | Invalid DDR3 encoding (reserved bits set) |
| Byte 0 = 0x00 | 0 | Must be non-zero |
| SDRAM width > 2 | 7 [2:0] | 011+ are reserved in DDR3 |
| All timing bytes zero | 17–29 | Placeholder SPD — guaranteed MRC failure |

**Warnings** (printed but do not fail unless `--strict`):

| Check | Byte(s) | Condition |
|-------|---------|-----------|
| tCKmin out of range | 12 | Outside 7–30 MTB (not DDR3-plausible) |
| SPD revision zero | 1 | Expected 0x10 or 0x11 |
| Row address > 2 | 5 [5:3] | Reserved in DDR3 |
| Col address > 2 | 5 [2:0] | Reserved in DDR3 |
| Rank encoding > 3 | 7 [5:3] | Unusual value |

Run `--strict` for any SPD that will be used in a live experiment.

---

## Fixture Tests

Four self-contained tests can be run without hardware to verify the pipeline logic:

```bash
# Test 1 — Default placeholder config reports timing errors
python3 generate_spd.py --dump-default-config > /tmp/t1.json
python3 generate_spd.py --config /tmp/t1.json --output /tmp/t1.bin 2>/dev/null
python3 validate_spd.py --input /tmp/t1.bin
# Expected: VALIDATION FAILED — bytes 17-29 all-zero error

# Test 2 — Minimal valid SPD (with tCKmin and tAAmin only) reports timing error
python3 - <<'EOF'
import json, subprocess, sys
cfg = json.loads(subprocess.check_output(
    ["python3", "tools/spd-gen/generate_spd.py", "--dump-default-config"]))
cfg["_credibility"] = "test"
with open("/tmp/t2.json", "w") as f: json.dump(cfg, f)
EOF
python3 tools/spd-gen/generate_spd.py --config /tmp/t2.json --output /tmp/t2.bin 2>/dev/null
python3 tools/spd-gen/validate_spd.py --input /tmp/t2.bin
# Expected: VALIDATION FAILED — timing bytes still zero

# Test 3 — CRC is recomputed correctly (corrupt one byte, expect CRC error)
python3 - <<'EOF'
data = bytearray(open("/tmp/t2.bin","rb").read())
data[18] ^= 0xFF       # flip tRCDmin (CRC-covered byte)
open("/tmp/t3.bin","wb").write(data)
EOF
python3 tools/spd-gen/validate_spd.py --input /tmp/t3.bin
# Expected: CRC mismatch error

# Test 4 — spd_to_hex.py produces 256 lines of hex
python3 tools/spd-gen/spd_to_hex.py --input /tmp/t2.bin --output /tmp/t4.hex 2>/dev/null
lines=$(wc -l < /tmp/t4.hex)
[ "$lines" -eq 256 ] && echo "PASS: 256 lines" || echo "FAIL: got $lines lines"
```

Run these from the repo root after any change to the pipeline tools.

---

## Output File Handling

**Do not commit `.bin` or `.hex` files** generated from placeholder configs. The `.gitignore`
at repo root excludes `*.bin` and `fpga/rtl/spd_rom.hex` for this reason.

Files that **should** be committed:
- `data/spd/s0*-spd-dimm_*.bin` — raw captures from Stage 0 (Class A artifacts)
- `data/spd/*.meta.yaml` — sidecars for captured SPD files
- Config JSON files used to generate validated SPD images (`tools/spd-gen/configs/*.json`)

Files that **must not** be committed until Stage 0 is complete:
- `fpga/rtl/spd_rom.hex` — generated from placeholder; will mislead synthesis

---

## Common Failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Bytes 17-29 all zero` error | Timing fields not populated | Fill from Stage 0 SPD capture or DIMM datasheet |
| `CRC mismatch` error | SPD binary was modified after generation | Re-run `generate_spd.py` from config; never hand-edit .bin |
| `Byte 0 = 0x92` error | Old generate_spd.py bug (PY-2) | Update to current generate_spd.py; regenerate |
| `SDRAM device width = 3` error | Old width_enc table bug (PY-3) | Update to current generate_spd.py; regenerate |
| `tAAmin = 0x69` in hex output | Old tAAmin value (PY-5) | Update to current generate_spd.py; regenerate |
| MRC hangs or fails to train | Timing parameters wrong or all-zero | Use captured SPD from Stage 0; do not use placeholder |
| `$readmemh` init warning in simulation | spd_rom.hex not present | Run pipeline first; hex file is generated, not committed |
