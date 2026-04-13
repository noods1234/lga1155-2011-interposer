# Stage 0: Native Instrumentation — Data Collection Package

**Status**: Not started — awaiting physical hardware and test equipment
**Credibility**: [Placeholder] — no data captured
**Artifact schema**: docs/bringup-artifact-schema.md
**Session template**: data/metadata/stage0-capture-template.yaml

---

## Before You Start

Copy the session template and fill it in completely before powering on:

```bash
cp data/metadata/stage0-capture-template.yaml \
   data/metadata/s0-session-YYYYMMDD-01.yaml
```

Fill every field. If a field is genuinely unknown (e.g., board revision not
visible), mark it `"unknown"` — not `"PLACEHOLDER"`. PLACEHOLDER means
not yet attempted; unknown means attempted and not determinable.

---

## Directory Structure (post-capture)

```
data/
  metadata/
    s0-session-YYYYMMDD-01.yaml         ← fill before starting
  smbus/
    s0-smbus-post_capture-YYYYMMDD-01.vcd
    s0-smbus-post_capture-YYYYMMDD-01.meta.yaml
    s0-smbus-edge_rates-YYYYMMDD-01.md
    s0-smbus-edge_rates-YYYYMMDD-01.meta.yaml
  cpuid/
    s0-cpuid-sandy_bridge_stock-YYYYMMDD-01.json
    s0-cpuid-sandy_bridge_stock-YYYYMMDD-01.meta.yaml
    s0-msr-sandy_bridge_stock-YYYYMMDD-01.txt
    s0-msr-sandy_bridge_stock-YYYYMMDD-01.meta.yaml
  acpi/
    dsdt-raw.dat
    dsdt-raw.dat.meta.yaml
    dsdt-decompiled.dsl
    dsdt-decompiled.dsl.meta.yaml
  rails/
    s0-rail-pwrgood_timing-YYYYMMDD-01.csv
    s0-rail-pwrgood_timing-YYYYMMDD-01.meta.yaml
  spd/
    s0-spd-dimm_a1-YYYYMMDD-01.bin      ← one per populated slot
    s0-spd-dimm_a1-YYYYMMDD-01.meta.yaml
hardware/
  measurements/
    socket-z-clearance.md
    socket-z-clearance.md.meta.yaml
```

---

## Equipment Checklist

Complete before starting the session. Record make/model/firmware in session YAML.

| Item | Min spec | Purpose |
|------|----------|---------|
| Oscilloscope | 100 MHz BW, 4 ch | Rail sequencing (T0.4), edge rates (T0.7) |
| Logic analyzer | 24 MHz sample rate, I2C decode | SMBus capture (T0.1) |
| Calipers | 0.01 mm resolution | Z-clearance (T0.6) |
| Linux live USB | i2c-tools, acpidump, iasl installed | T0.3, T0.5 |
| USB-UART adapter | 3.3 V TTL | EFI tool output (T0.2) |

---

## Expected Values Table

What a healthy stock iMac12,2 with Sandy Bridge CPU should show.
If any measured value is outside the expected range, stop and mark the task
`blocked` in the session YAML before continuing.

| Task | Parameter | Expected | Flag if |
|------|-----------|----------|---------|
| T0.1 | I2C addresses active during POST | 0x50–0x53 (SPD reads) | Address outside 0x50–0x57 is unexpected |
| T0.1 | Transactions per slot before DRAM init | ≥ 10 SPD reads per slot | Fewer may mean capture missed early POST |
| T0.2 | CPUID leaf 0x01 EAX[11:8] Family | 0x6 | Any other value: wrong CPU family, stop |
| T0.2 | CPUID leaf 0x01 Model (EAX[7:4] + EAX[19:16]<<4) | 0x2A (Sandy Bridge) or 0x3A (Ivy Bridge) | 0x3F = Haswell-E, wrong platform |
| T0.2 | ECX bit 29 (F16C) | 0 on SNB, 1 on IVB | Mismatch → CPU identity uncertain |
| T0.2 | ECX bit 30 (RDRAND) | 0 on SNB, 1 on IVB | Same |
| T0.4 | VDIMM steady state | 1.5 V ± 5% (1.425–1.575 V) | < 1.35 V or > 1.65 V |
| T0.4 | PWRGOOD timing relative to VDIMM | PWRGOOD rises after VDIMM stable | PWRGOOD before VDIMM = sequencing fault |
| T0.5 | SPD byte 2 (DRAM type) | 0x0B (DDR3) | Any other value |
| T0.5 | SPD CRC (bytes 116–117) | Passes validate_spd.py | CRC fail = corrupted read, retry |
| T0.6 | LGA socket Z-clearance | Unknown — MEASURE IT | < 0.3 mm → R-001 escalates to blocking |
| T0.7 | SCL/SDA rise time (10–90%) | < 300 ns | > 1000 ns = excessive bus capacitance |
| T0.7 | SMBus clock frequency | 100 kHz or 400 kHz | Other values unexpected on stock system |

---

## Tasks

### T0.1 — SMBus POST Capture

**Artifact**: `data/smbus/s0-smbus-post_capture-YYYYMMDD-01.vcd`
**Class**: A (raw capture) — see docs/bringup-artifact-schema.md
**Credibility required**: Verified

**Minimum capture content**:
- Full POST sequence from S5 exit through DRAM initialization
- At least one complete START → address → data bytes → STOP per populated slot
- Addresses 0x50–0x53 must all appear if all four DIMM slots are populated

**Procedure**:
1. Identify SMBus test points. Candidates: 4.7 kΩ pull-up resistors near PCH (tied
   to 3.3 V), or DIMM connector pins 9 (SCL) and 10 (SDA) per JEDEC DDR3 pinout.
   **Confirm with DMM continuity check before probing under power.**
2. Attach logic analyzer. Ground clip to board ground only — not chassis.
3. Configure: I2C decode mode, 400 kHz max, threshold = 1.65 V (half of 3.3 V rail).
4. Arm trigger on first SDA falling edge (START condition).
5. Power on. Let boot complete. Stop capture at first OS screen.
6. Verify in analyzer: I2C addresses 0x50–0x53 are present in the log.
7. Export as VCD. Rename to artifact convention.
8. Write `.meta.yaml` sidecar: instrument, sample rate, threshold, trigger setting,
   system state ("stock iMac12,2, no modifications, S5→S0 boot").

**Go/no-go**: If no I2C transactions captured, or fewer slots than populated DIMMs
appear in the address log → task is `blocked`. Do not advance to Stage 1.

---

### T0.2 — CPUID Capture (Sandy Bridge stock)

**Artifact**: `data/cpuid/s0-cpuid-sandy_bridge_stock-YYYYMMDD-01.json`
**Class**: A
**Credibility required**: Verified

**Required leaves**:
- 0x00 through highest basic leaf
- 0x80000000 through highest extended leaf
- Leaf 0x01 decoded: Family, Model, Stepping, ECX feature flags
- Leaf 0x04 (cache topology), 0x0B (core/thread counts if present)

**Preferred method — EFI tool** (captures exact Apple EFI environment):
```
# Build efi/CpuidAudit/ per efi/README.md (requires EDK II)
# Copy CpuidAudit.efi → FAT32 USB as EFI/BOOT/BOOTX64.EFI
# Boot iMac from USB; capture serial output to file
# Rename to s0-cpuid-sandy_bridge_stock-YYYYMMDD-01.json
```

**Fallback — Linux userspace**:
```bash
cpuid -1 -r | tee s0-cpuid-sandy_bridge_stock-YYYYMMDD-01.txt
```
Note: Linux userspace CPUID runs after OS has set up the CPU. EFI-level capture
is preferred because it reflects the state MRC sees during training.

**Go/no-go**: Family must be 0x06. Model must be 0x2A or 0x3A. Any other value
is a hard stop — investigate the installed CPU before continuing.

---

### T0.2b — MSR Capture

**Artifact**: `data/cpuid/s0-msr-sandy_bridge_stock-YYYYMMDD-01.txt`
**Class**: A
**Credibility required**: Verified

Run `efi/MsrAudit/MsrAudit.efi` immediately after T0.2 in the same EFI session.
The tool reads 20 MSRs: microcode revision (0x8B), RAPL power limits (0x610/0x614),
SpeedStep/turbo state (0x1A0/0xCE), VMX lock (0x3A), and others.

**If the tool hangs**: the last printed `[>>]` line identifies the offending MSR.
Record this in the session YAML blocker field. This is risk R-005 manifesting — an
Apple EFI platform check beyond standard UEFI. Do not retry; move on to T0.3 and
document the hang point precisely.

---

### T0.3 — ACPI Dump

**Artifacts**:
- `data/acpi/dsdt-raw.dat` (Class A — raw binary)
- `data/acpi/dsdt-decompiled.dsl` (Class B — derived from dsdt-raw.dat via iasl)

```bash
# Boot Linux live USB
sudo acpidump -b -o /tmp/acpi/
cp /tmp/acpi/dsdt.dat data/acpi/dsdt-raw.dat

# Decompile (iasl must be installed)
iasl -d data/acpi/dsdt-raw.dat
mv dsdt.dsl data/acpi/dsdt-decompiled.dsl
```

**Post-decompile checks** (record results in dsdt-decompiled.dsl.meta.yaml notes):
```bash
# Does SBUS device already exist?
grep -i "SBUS\|SMB0\|SMBus" data/acpi/dsdt-decompiled.dsl

# Does PPMC device exist? (known potential conflict)
grep -i "PPMC" data/acpi/dsdt-decompiled.dsl

# What PCI path is the SMBus controller?
grep -i "0x001F0003\|Device.*SMB" data/acpi/dsdt-decompiled.dsl
```

Three outcomes for `opencore/ACPI/reference/SSDT-PMC-z68-reference.dsl`:
- SBUS absent from DSDT → SSDT needed; mark [Inference]
- SBUS present and correct → SSDT unnecessary; mark reference as rejected
- SBUS present but broken → SSDT needed with modifications; document the conflict

---

### T0.4 — Power Rail Sequencing

**Artifact**: `data/rails/s0-rail-pwrgood_timing-YYYYMMDD-01.csv`
**Class**: A
**Credibility required**: Verified

**Four oscilloscope channels**:

| Ch | Signal | Expected voltage | Notes |
|----|--------|-----------------|-------|
| 1  | 12 V input | 12 V ± 5% | Use as trigger (rising edge) |
| 2  | VDIMM | 1.5 V ± 5% | Near DIMM slots |
| 3  | VCORE (CPU VRM output) | 0.6–1.4 V (dynamic) | Near CPU VRM inductors |
| 4  | PWRGOOD (PCH output) | 3.3 V or 5 V logic | Confirm level with DMM first |

**Test points**: Not confirmed — locate with DMM before probing live.

**CSV format**:
```
time_ms,v_12v,v_vdimm,v_vcore,v_pwrgood
0.000,...
```
Time zero = 12 V rising edge. Sample rate: ≥ 100 kSa/s (1 ms resolution minimum).

**Critical measurement**: Δt(VDIMM stable → PWRGOOD asserts). Must be positive.
Record raw value in the artifact `.meta.yaml` sidecar notes field
and in the `.meta.yaml` notes field.

---

### T0.5 — SPD Capture

**Artifacts**: `data/spd/s0-spd-dimm_a1-YYYYMMDD-01.bin` (one per populated slot)
**Class**: A
**Credibility required**: Verified

```bash
# Boot Linux live USB
sudo modprobe i2c-dev i2c-i801
i2cdetect -l                    # find SMBus bus number
i2cdetect -y <bus>              # confirm 0x50–0x53 present

# Dump each populated slot (i2cdump outputs hex; convert to binary)
i2cdump -y <bus> 0x50 b > /tmp/slot_a1_hex.txt
# Convert: python3 -c "
#   import sys, re
#   data = []
#   for line in open(sys.argv[1]):
#       if re.match(r'^[0-9a-f]{2}:', line):
#           data += [int(x,16) for x in line.split()[1:17] if x != 'XX']
#   open(sys.argv[2],'wb').write(bytes(data))
# " /tmp/slot_a1_hex.txt data/spd/s0-spd-dimm_a1-YYYYMMDD-01.bin

# Validate immediately after capture
python3 tools/spd-gen/validate_spd.py \
    --input data/spd/s0-spd-dimm_a1-YYYYMMDD-01.bin
```

**This is the gold standard**. The FPGA SPD emulation pipeline must produce
output byte-for-byte identical to this capture. Any deviation is a bug.

Record slot population in session YAML `memory.slots` and set `spd_captured: true`
for each slot successfully captured.

---

### T0.6 — LGA Socket Z-Clearance

**Artifact**: `hardware/measurements/socket-z-clearance.md`
**Class**: A (direct measurement)
**Credibility required**: Verified

**This is a project gate. R-001 is unresolvable without it.**

**Procedure**:
1. Power off. Discharge: hold power button 10 s after disconnecting mains.
2. Remove CPU cooler and heatsink. Do not damage IHS or socket.
3. CPU installed: measure height of IHS top above socket retention bracket.
   Record as `h_cpu_installed_mm`.
4. CPU removed (LGA procedure — do NOT bend pins): measure socket contact
   field height above retention bracket. Record as `h_socket_empty_mm`.
5. Measure interposer contact requirement: CPU package spec height = 1.23 mm
   nominal (verify against Intel LGA1155 mechanical drawing).
6. Available Z-clearance = `h_cpu_installed_mm − h_socket_empty_mm − 1.23`

**Decision gate**:

| Clearance | Status | Action |
|-----------|--------|--------|
| ≥ 0.5 mm | R-001 cleared | Standard 0.4 mm FR4 interposer feasible |
| 0.3–0.5 mm | R-001 conditional | Thin PCB (0.2–0.3 mm) required; verify fab options |
| < 0.3 mm | **R-001 BLOCKING** | No PCB interposer; pivot to wire-tap only |

Record raw caliper readings, not just the conclusion. The `.md` artifact must
contain: measurement date, operator, instrument, all raw readings, and the
derived clearance value.

---

### T0.7 — SMBus Edge Rate Baseline

**Artifact**: `data/smbus/s0-smbus-edge_rates-YYYYMMDD-01.md`
**Class**: A/B
**Credibility required**: Verified

**Oscilloscope measurements** (same test points as T0.1):

| Signal | Measurement | Acceptable | Flag if |
|--------|------------|------------|---------|
| SCL | 10–90% rise time (ns) | < 300 ns | > 1000 ns |
| SCL | 10–90% fall time (ns) | < 300 ns | > 300 ns |
| SDA | 10–90% rise time (ns) | < 300 ns | > 1000 ns |
| SDA | 10–90% fall time (ns) | < 300 ns | > 300 ns |
| SCL | Bus frequency (kHz) | 100 or 400 | Neither value |
| Bus | Logic high voltage (V) | 3.3 ± 10% | < 2.7 V |

**This is the pre-interposer baseline.** Stage 1 passive tap insertion must not
degrade any value by more than 10% or risk R-007 escalates.

The output `.md` file must contain the raw numbers:

```markdown
# SMBus Edge Rates — Stock iMac12,2

Date: YYYY-MM-DD
Operator:
Instrument:
System state: stock iMac12,2, no modifications, S5→S0 boot

| Signal | Rise (ns) | Fall (ns) | Freq (kHz) | V_high (V) |
|--------|-----------|-----------|------------|------------|
| SCL    |           |           |            |            |
| SDA    |           |           | n/a        | n/a        |

Notes:
```

---

## Stage 1 Gate Checklist

All nine artifact families must exist, be committed, and have `.meta.yaml` sidecars
with `credibility: Verified`. Any missing or Placeholder artifact is a hard stop.
Update session YAML `stage_gate` block when all are complete.

- [ ] `data/smbus/s0-smbus-post_capture-*.vcd`
- [ ] `data/smbus/s0-smbus-edge_rates-*.md`
- [ ] `data/cpuid/s0-cpuid-sandy_bridge_stock-*.json`
- [ ] `data/cpuid/s0-msr-sandy_bridge_stock-*.txt`
- [ ] `data/spd/s0-spd-dimm_*.bin` (all populated slots)
- [ ] `data/acpi/dsdt-raw.dat`
- [ ] `data/acpi/dsdt-decompiled.dsl`
- [ ] `data/rails/s0-rail-pwrgood_timing-*.csv`
- [ ] `hardware/measurements/socket-z-clearance.md`

Set `stage_gate.gate_status: "PASS"` only when all nine are checked and
`r001_cleared: true` (Z-clearance ≥ 0.3 mm).
