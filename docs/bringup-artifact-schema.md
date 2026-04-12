# Bring-Up Artifact Schema

**Purpose**: Defines what constitutes a valid artifact for each experimental stage. An artifact is only promoted to [Verified] when it meets the requirements in this document.

This schema exists to prevent the most common failure mode of bring-up projects: confusing the presence of a file with the presence of evidence.

---

## Artifact Classes

### Class A — Raw Capture
A file produced directly by a measurement instrument or system-level dump tool. No post-processing other than format conversion.

**Requirements:**
- File name encodes: `{stage}-{artifact-type}-{date}-{sequence}.{ext}`
- Metadata YAML sidecar required: `{same-name}.meta.yaml`
- Credibility: [Verified] only if the sidecar specifies instrument, settings, and capture conditions
- Must not be modified after capture. Processed versions go to Class B.

**Examples:** oscilloscope waveform export, logic analyzer capture, `i2cdump` output, `acpidump` binary, EFI tool serial output.

---

### Class B — Processed / Decoded
Derived from a Class A artifact by a documented tool with logged parameters.

**Requirements:**
- Provenance field in metadata: which Class A file it was derived from
- Tool name, version, and command line recorded
- If the derivation involved judgment (e.g., manual annotation), credibility is [Inference], not [Verified]
- The source Class A file must exist and be committed

**Examples:** `iasl -d dsdt.dat` output, `decode-dimms` output, oscilloscope CSV converted to annotated timing table.

---

### Class C — Template / Placeholder
A schema or example file with no real measurement data. Must not be used in any active experiment.

**Requirements:**
- All data cells that are not real measurements must contain the literal string `PLACEHOLDER` or `0` with a comment marking it as placeholder
- File name or header must include the word `template` or `placeholder`
- Credibility: [Placeholder] — no other tag permitted for this class

**Examples:** `data/pinout/pin-classification-template.csv`, `data/rails/power-sequencing-template.csv`.

---

### Class D — Generated / Synthesized
Produced by a tool in this repo from other artifacts. Not a direct measurement.

**Requirements:**
- The generating tool and input artifact must be specified in metadata
- If generated from Class C input: credibility is [Placeholder]
- If generated from Class A/B input: credibility is [Inference]
- CRC or hash of the generating tool and its inputs must be recorded for reproducibility

**Examples:** `generate_spd.py` output, FPGA ROM hex file from `spd_to_hex.py`.

---

### Class E — Reference / Documentation
External specifications, datasheets, or design notes. Not primary measurements.

**Requirements:**
- Source URL or document reference must be recorded
- If the source is not publicly verifiable, credibility is [Hypothesis]
- Must not be used as sole evidence for a hardware decision

**Examples:** Intel Sandy Bridge EDS excerpts, JEDEC 21C SPD tables.

---

## Naming Convention

```
{stage}{index}-{type}-{descriptor}-{YYYYMMDD}-{seq:02d}.{ext}
```

| Part | Values | Example |
|------|--------|---------|
| stage | `s0`, `s1`, `s2`, `s3`, `s4` | `s0` |
| index | two digits | `01` |
| type | `smbus`, `scope`, `spd`, `cpuid`, `msr`, `acpi`, `rail`, `mech` | `smbus` |
| descriptor | short underscore-separated description | `post_capture` |
| date | `YYYYMMDD` | `20250101` |
| seq | sequence within same day | `01` |

**Examples:**
```
s0-smbus-post_capture-20250101-01.vcd
s0-smbus-post_capture-20250101-01.meta.yaml
s0-spd-dimm_a1-20250101-01.bin
s0-cpuid-sandy_bridge_stock-20250101-01.json
s0-rail-pwrgood_timing-20250101-01.csv
s0-mech-lga_z_clearance-20250101-01.md
```

---

## Metadata Sidecar Schema (`.meta.yaml`)

Every Class A artifact requires a sidecar with this schema:

```yaml
# Metadata sidecar for a bring-up artifact
# Required for Class A (raw capture) artifacts
# Optional but recommended for Class B

artifact_class: A          # A, B, C, D, or E
stage: 0                   # 0-4
credibility: Verified      # Verified / Inference / Hypothesis / Placeholder
artifact_type: smbus       # smbus / scope / spd / cpuid / msr / acpi / rail / mech

capture:
  date: "YYYY-MM-DD"
  operator: ""              # person who performed the capture
  system_state: ""          # e.g., "stock iMac12,2, no modifications, S5→S0 boot"

instrument:
  type: ""                  # e.g., "logic analyzer", "oscilloscope", "i2cdump"
  make_model: ""
  firmware_version: ""
  settings:                 # key-value pairs specific to instrument type
    sample_rate_mhz: null
    channel_count: null
    trigger: ""
    decode_protocol: ""

board:
  model: "iMac12,2"         # or unknown
  serial_number: ""         # optional; omit if privacy concern
  board_revision: ""        # silkscreen revision if visible
  modifications: []         # list any modifications from stock

cpu:
  family_hex: ""            # e.g., "0x06"
  model_hex: ""             # e.g., "0x2A" for Sandy Bridge
  stepping_hex: ""
  microcode_rev_hex: ""
  part_number: ""

dimm_slots:                 # fill slots that are populated
  A1: {part: "", capacity_gb: null, speed_mhz: null}
  A2: {part: "", capacity_gb: null, speed_mhz: null}
  B1: {part: "", capacity_gb: null, speed_mhz: null}
  B2: {part: "", capacity_gb: null, speed_mhz: null}

provenance:                 # Class B only
  source_artifact: ""
  tool: ""
  tool_version: ""
  command_line: ""

notes: ""
```

---

## Stage Gate Artifact Requirements

### Stage 0 → Stage 1 Gate

All of the following Class A artifacts must be present and have `.meta.yaml` sidecars with `credibility: Verified`:

| File pattern | Type | Minimum content |
|-------------|------|----------------|
| `data/smbus/s0*-smbus-post_capture-*.vcd` | A | Full POST sequence from power-on through DRAM init |
| `data/smbus/s0*-smbus-edge_rates-*.md` | A/B | SCL/SDA 10–90% rise/fall times in ns |
| `data/cpuid/s0*-cpuid-sandy_bridge_stock-*.json` | A | All standard + extended CPUID leaves |
| `data/cpuid/s0*-msr-sandy_bridge_stock-*.txt` | A | MSR audit output from MsrAudit.efi |
| `data/spd/s0*-spd-dimm_*.bin` | A | Raw SPD from each populated slot |
| `data/acpi/dsdt-raw.dat` | A | Raw DSDT binary |
| `data/acpi/dsdt-decompiled.dsl` | B | iasl decompilation of dsdt-raw.dat |
| `data/rails/s0*-rail-pwrgood_timing-*.csv` | A | 12V, VDIMM, VCORE, PWRGOOD timing |
| `hardware/measurements/socket-z-clearance.md` | A | LGA socket Z-clearance in mm with caliper reading |

**Gate condition**: ALL nine artifact families must exist. Any missing artifact is a hard stop.

### Stage 1 → Stage 2 Gate

In addition to all Stage 0 artifacts:

| File pattern | Type | Content |
|-------------|------|---------|
| `hardware/interposer-v*/schematic.pdf` | D | Passive interposer PCB schematic |
| `hardware/interposer-v*/test-results.md` | A | Bench continuity test results |
| `data/smbus/s1*-smbus-edge_rates_passive-*.md` | A | Edge rates WITH passive interposer installed |
| `experiments/stage1-passive/boot-log.md` | A | ≥ 10 consecutive boot attempts, pass/fail |

---

## Promotion Criteria

A file moves from [Placeholder] to [Inference] when:
- It is derived from a [Verified] Class A artifact by a documented tool
- The derivation process is reproducible (tool, version, command all recorded)

A file moves from [Inference] to [Verified] when:
- The claim has been confirmed by independent measurement
- Two independent instruments or methods agree within specified tolerance

A file stays [Hypothesis] when:
- It is technically plausible but no measurement has been made
- It is derived from a [Hypothesis] or [Placeholder] source

A [Placeholder] file **must not** be used as input to any experiment.
