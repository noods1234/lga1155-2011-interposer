# Stage 0: Native Sandy Bridge Instrumentation

**Status**: Not started — awaiting physical hardware access and test equipment  
**Credibility**: [Placeholder] — no data captured yet  
**Gate condition for Stage 1**: All deliverables in this directory populated and marked [Verified]

---

## Objective

Establish a complete, measured baseline of the iMac12,2 platform in its stock configuration **before any modification**. No interposer. No BIOS changes. No OS patches.

Every number in this repository that affects hardware decisions must originate from a measurement made during this stage. Anything not yet measured is explicitly [Placeholder].

---

## Required Equipment

| Item | Purpose | Minimum spec |
|------|---------|-------------|
| Oscilloscope | Power rail sequencing, edge rates, signal timing | 100 MHz BW, 2 channels min; 4 channels preferred |
| Logic analyzer | SMBus transaction capture | 8 channels, 24 MHz+ sample rate; I2C decode support |
| Calipers | LGA socket Z-clearance measurement | 0.01 mm resolution |
| USB-to-UART adapter | Serial console output from EFI tools | Any 3.3 V TTL adapter |
| i2c-tools (Linux live USB) | Dump SPD EEPROM contents | `i2cdump`, `decode-dimms` |
| iasl | Decompile ACPI tables | Any recent version |
| acpidump / Linux | Dump raw ACPI tables | Linux live USB boot |

---

## Task Checklist

### T0.1 — SMBus capture during POST

**Goal**: Capture a complete SMBus transaction log from power-on through DRAM initialization.

**Method**:
1. Identify SMBus CLK and DAT test points on iMac12,2 board. Candidate locations: SMBus pull-up resistors (typically 4.7 kΩ to 3.3 V near PCH), DIMM slots, or PCH SMBus pin pad.  
   **[Placeholder — test point locations not yet confirmed. Do not probe blindly.]**
2. Attach logic analyzer probes to SMBus CLK and DAT with ground clip to board ground.
3. Set logic analyzer to I2C decode mode, 400 kHz max bus speed.
4. Power on iMac; capture from power-on through OS boot.
5. Export capture as VCD or CSV.

**Output**: `data/smbus/stage0-post-smbus.vcd`  
**Credibility required**: [Verified] — must be actual capture, not reconstructed

---

### T0.2 — CPUID capture (Sandy Bridge stock)

**Goal**: Capture all CPUID leaves from the installed Sandy Bridge CPU.

**Method A — EFI tool** (preferred):
1. Build `efi/src/cpuid_audit.c` against EDK II.
2. Copy the resulting `.efi` application to a FAT32 USB drive as `EFI/BOOT/BOOTX64.EFI`.
3. Boot iMac from USB; the tool outputs CPUID leaves to screen.
4. Photograph or capture serial output.

**Method B — Linux**:
1. Boot Linux live USB.
2. Run: `cpuid -1 -r > cpuid_sandy_bridge.txt` (install `cpuid` package).
3. Alternatively: `cat /proc/cpuinfo` for basic model info.

**Output**: `data/cpuid/sandy-bridge-stock.json`  
**Format**: JSON with leaf number, EAX/EBX/ECX/EDX values, decoded family/model/stepping.

---

### T0.3 — ACPI table dump

**Goal**: Capture raw DSDT and all SSDTs from the running platform.

**Method**:
1. Boot Linux live USB.
2. Run: `sudo acpidump -b -o acpi_dump/` to dump all tables as binary.
3. Run: `iasl -d acpi_dump/dsdt.dat` to decompile DSDT.
4. Run: `iasl -d acpi_dump/ssdt*.dat` to decompile all SSDTs.

**Output**: 
- `data/acpi/dsdt-raw.dat` (binary)
- `data/acpi/dsdt-decompiled.dsl` (decompiled)
- `data/acpi/ssdt-*.dat` and corresponding `.dsl` files

**Purpose**: Required to verify whether PMC / SBUS ACPI entries already exist before applying `opencore/ACPI/reference/SSDT-PMC-z68-reference.dsl`.

---

### T0.4 — Power rail sequencing

**Goal**: Measure power-on sequencing from S5 exit to PWRGOOD assertion.

**Method**:
1. Identify test points for: 12 V (ATX), VDIMM (1.5 V near DIMM slots), VCORE (near CPU VRM), PWRGOOD (PCH output).  
   **[Placeholder — test point locations not confirmed]**
2. Set oscilloscope to trigger on 12 V rising edge.
3. Capture: 12 V, VDIMM, VCORE, PWRGOOD on four channels.
4. Export waveform data.

**Output**: `data/rails/stage0-rail-timing.csv` (populate measured values from template)

**Critical measurement**: PWRGOOD assertion time relative to VDIMM stable. Must verify VTT is stable before PWRGOOD. See risk register R-003.

---

### T0.5 — SPD capture from installed DIMMs

**Goal**: Read exact SPD contents from all installed DIMM slots.

**Method**:
1. Boot Linux live USB.
2. Load I2C modules: `modprobe i2c-dev i2c-i801`
3. List I2C buses: `i2cdetect -l`
4. Scan for SPD EEPROMs (addresses 0x50–0x57): `i2cdetect -y <bus_number>`
5. Dump each EEPROM: `i2cdump -y <bus> 0x50 b > slot_a1.bin` (etc.)
6. Decode: `decode-dimms slot_a1.bin`

**Output**: `data/spd/stage0-slot-a1.bin`, `stage0-slot-a2.bin`, etc.  
**Purpose**: This is the gold-standard SPD data. The SPD generation pipeline must produce output that matches this exactly for pass-through emulation validation.

---

### T0.6 — LGA socket Z-clearance measurement

**Goal**: Determine whether an interposer PCB is physically feasible.

**Method**:
1. With system powered OFF and discharged, carefully remove CPU cooler and heatsink.
2. With CPU installed, measure height of CPU IHS above socket retention bracket using calipers.
3. Remove CPU (following LGA socket handling procedure — do NOT damage pins).
4. Measure depth of LGA socket below retention bracket level.
5. Calculate available Z-clearance: (socket depth) − (any required CPU contact clearance).

**Output**: `hardware/measurements/socket-z-clearance.md`

**Decision gate**: If available clearance < 0.3 mm, Risk R-001 escalates to project-stopping. The interposer PCB approach must be reconsidered (pivot to socket-level wire taps only).

---

### T0.7 — SMBus edge rate baseline

**Goal**: Confirm SMBus signal quality on stock system before any interposer tap.

**Method**:
1. With oscilloscope on SMBus CLK, measure 10–90% rise time of SCL edges during active POST.
2. Measure SDA edge rates similarly.
3. Record: rise time (ns), fall time (ns), bus voltage (V), clock frequency (kHz).

**Output**: `data/smbus/stage0-edge-rates.md`  
**Purpose**: This is the baseline. After passive interposer insertion in Stage 1, edge rates must not degrade by more than 10% or R-007 escalates.

---

## Gate Condition for Stage 1

All of the following files must exist, contain measured (not placeholder) data, and be committed:

- [ ] `data/smbus/stage0-post-smbus.vcd`
- [ ] `data/cpuid/sandy-bridge-stock.json`
- [ ] `data/acpi/dsdt-decompiled.dsl`
- [ ] `data/rails/stage0-rail-timing.csv` (measured values filled in)
- [ ] `data/spd/stage0-slot-a1.bin` (minimum; all populated slots preferred)
- [ ] `hardware/measurements/socket-z-clearance.md`
- [ ] `data/smbus/stage0-edge-rates.md`

**No Stage 1 activity begins until this checklist is complete.**

---

## Notes on iMac12,2 Specific Concerns

- The iMac uses a custom Apple PCB. SMBus test points may not follow standard ATX layout.
- The board is not easily replaceable. Exercise extreme care when probing.
- Do not probe under load with long scope leads — ground current can cause glitches.
- Apple's EFI may perform actions during POST that differ from standard UEFI. The CPUID audit tool (T0.2) will reveal some of these; EFI binary analysis (tools/efi-audit) is a follow-on task.
