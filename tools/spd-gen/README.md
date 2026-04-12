# SPD Generation Pipeline

**Status**: Tools implemented; not yet validated against a real DIMM or MRC  
**Credibility**: [Inference] — JEDEC 21C byte layout is documented; end-to-end pipeline not tested

## Purpose

Generates and validates DDR3 SPD images for use in the FPGA `spd_responder` module. Replaces the hard-coded SPD bytes from the old `fpga_ddr_bridge.v`.

**Rule**: Never hand-edit SPD bytes. Never use an SPD image that has not passed `validate_spd.py`. Never synthesize an FPGA bitstream with an SPD hex file from a source other than this pipeline.

## Pipeline

```bash
# Step 1: Get real DIMM SPD data (Stage 0, task T0.5)
#   data/spd/stage0-slot-a1.bin  ← this is your gold standard

# Step 2: Generate an SPD image
python3 generate_spd.py --config my_dimm_config.json --output generated.bin

# Step 3: Validate
python3 validate_spd.py --input generated.bin --strict

# Step 4: Convert to FPGA ROM hex
python3 spd_to_hex.py --input generated.bin --output ../../fpga/rtl/spd_rom.hex
```

## Tools

| Tool | Input | Output | Status |
|------|-------|--------|--------|
| `generate_spd.py` | JSON config | 256-byte SPD binary | Implemented; timing fields are [Placeholder] |
| `validate_spd.py` | 256-byte binary | Pass/fail + warnings | Implemented |
| `spd_to_hex.py` | Validated binary | Verilog `$readmemh` hex | Implemented |

## Critical Warning

The default config in `generate_spd.py` has timing fields (tWR, tRCD, tRAS, etc.) set to zero. An SPD image with zero timing fields will cause MRC to fail. Before using any generated SPD in an experiment:

1. Capture the real DIMM SPD bytes in Stage 0 (task T0.5)
2. Create a config JSON from the decoded DIMM parameters
3. Regenerate with the real parameters
4. Validate with `--strict`
5. Compare the generated binary byte-by-byte with the captured binary before use
