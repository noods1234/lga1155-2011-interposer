# System Architecture Overview

**Document status**: [Inference] with [Placeholder] sections clearly marked  
**Platform**: iMac12,2 / Intel Z68 / Sandy Bridge LGA 1155  
**Last reviewed**: Initial draft

---

## 1. Physical Platform

### 1.1 Host System

| Attribute | Value | Credibility |
|-----------|-------|-------------|
| Model | iMac 12,2 (Mid 2011, 27-inch) | [Verified] |
| Chipset | Intel Z68 Express | [Verified] |
| CPU socket | LGA 1155 | [Verified] |
| Stock CPU family | Sandy Bridge (Core i5-2xxx / i7-2xxx) | [Verified] |
| Target upgrade CPU | Ivy Bridge (Core i7-3xxx) | [Hypothesis] |
| DDR3 slots | 4x SO-DIMM (2 channels × 2 ranks each) | [Verified] |
| Max validated RAM | 32 GB (4× 8 GB DDR3-1333) | [Verified — Apple support doc] |
| Platform Hub | Intel PCH (Cougar Point, Z68) | [Verified] |

### 1.2 LGA 1155 Socket

| Attribute | Value | Credibility |
|-----------|-------|-------------|
| Total contacts | 1155 | [Verified] |
| Socket pitch | 1.0 mm | [Verified — Intel mechanical spec] |
| Contact rows/cols | Approx. 38 × 38 minus corners | [Inference] |
| Signal groups | Power, DDR3, PCIe, DMI, SMBus, GPIO, analog | [Inference from Intel docs] |
| Mechanical height budget for interposer | Unknown — requires physical measurement | [Placeholder] |
| Interposer PCB max thickness (estimated) | 0.4–0.8 mm (VERY tight) | [Hypothesis — not measured] |

**RISK**: The LGA 1155 socket lid and CPU IHS clearance may leave insufficient Z-height for an interposer PCB plus two sets of pogo pins or LGA contacts. This is a primary physical feasibility question. See `docs/risk-register.md` R-001.

---

## 2. Signal Architecture

### 2.1 CPU-Side Signal Groups on LGA 1155

The following groups are relevant to interposer research. Pin assignments are derived from Intel platform documentation and community reverse-engineering; they must be verified against oscilloscope measurements before any active experiment.

```
┌─────────────────────────────────────────────────────────────────┐
│                      CPU (Sandy/Ivy Bridge)                     │
│                                                                 │
│  DDR3 Channel A (≈170 pins)  │  DDR3 Channel B (≈170 pins)     │
│  PCIe ×16 (32 lanes + refs)  │  PCIe ×4 (8 lanes + refs)       │
│  DMI (4 lanes + refs)        │  Display (DP/LVDS — PCH-routed) │
│  SMBus (2 pins)              │  Power management (SVID etc.)    │
│  Straps / Config (handful)   │  RESET_N, PWRGOOD                │
│  VCC/GND (majority of pins)  │  Analog (PLL ref, etc.)          │
└───────────────────┬─────────────────────────────────────────────┘
                    │  LGA 1155 socket + interposer layer
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│              Motherboard (Z68 PCB + PCH)                        │
│                                                                 │
│  DDR3 DIMM slots ──► (CPU memory controller routes to DIMMs)   │
│  PCIe slots ──────► Z68 PCH                                    │
│  DMI ─────────────► Z68 PCH                                    │
│  SMBus ────────────► PCH + DIMM SPD EEPROMs                    │
│  Power supply rails ► VRM on board                             │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Signals the Interposer Targets

**Priority group 1 — Passive observation only (Stage 0/1):**

| Signal | Direction | Purpose | Credibility |
|--------|-----------|---------|-------------|
| SMBus CLK | Bidirectional | SPD read; thermal sensor access | [Verified — SMBus standard + Z68 docs] |
| SMBus DAT | Bidirectional | Same | [Verified] |
| PWRGOOD | Motherboard→CPU | Platform power-good assertion | [Verified — Intel pinout] |
| RESET_N | Motherboard→CPU | System reset | [Verified — Intel pinout] |
| THERMTRIP_N | CPU→Motherboard | CPU over-temperature | [Verified — Intel pinout] |
| PROCHOT_N | CPU→Motherboard | CPU power throttle | [Verified — Intel pinout] |

**Priority group 2 — Strap / config (Stage 1 experiments):**

| Signal | Notes | Credibility |
|--------|-------|-------------|
| BSEL[1:0] | Bus speed selection straps | [Hypothesis — may be fixed/NC on this platform] |
| CPU strap pins (various) | Platform configuration | [Hypothesis — require oscilloscope verification] |
| SVID bus | CPU-VRM serial voltage ID | [Inference — present on Sandy Bridge] |

**Priority group 3 — DDR3 buses (Stage 3+, high risk):**

| Signal group | Notes | Credibility |
|-------------|-------|-------------|
| CKE[3:0] | Clock enable per rank | [Inference] |
| CS_N[3:0] | Chip select | [Inference] |
| ODT[3:0] | On-die termination control | [Inference] |
| RAS_N, CAS_N, WE_N | DRAM command | [Inference] |
| BA[2:0] | Bank address | [Inference] |
| A[15:0] | Row/column address | [Inference] |
| DQ[63:0] | Data bus | [Inference] |
| DQS[7:0], DQS_N[7:0] | Data strobe | [Inference] |
| CLK[3:0], CLK_N[3:0] | Differential clocks | [Inference] |

**CRITICAL**: DDR3 signal interception at LGA1155 requires signal routing at DDR3-1333/1600 speeds (~667/800 MHz clock). Any additional trace length or impedance discontinuity introduced by the interposer will likely cause timing failures. This is the hardest physical problem in the project. See risk R-004.

---

## 3. FPGA Architecture

The interposer FPGA serves as a signal observer, arbiter, and (in later stages) modifier. It is decomposed into independent modules to allow staged validation.

### 3.1 Module Decomposition

```
fpga/rtl/
  smbus_monitor.v    — Passive SMBus sniffer; logs all transactions
  smbus_arbiter.v    — Active SMBus gate; selectively passes or blocks
  spd_responder.v    — Emulates SPD EEPROM on SMBus (Stage 1+)
  pmbus_master.v     — PMBus/SVID observer (Stage 1+ hypothesis)
  telemetry_uart.v   — UART telemetry output to host via USB bridge
```

Each module is designed to compile, simulate, and be validated independently. No module assumes another module is functional. The top-level entity wires them together with explicit enable flags.

### 3.2 Module Interfaces

All module interfaces use synchronous registered I/O on a single clock domain (target: 50 MHz system clock derived from oscillator on interposer PCB). Clock crossing for SMBus-speed signals is handled explicitly with synchronizers.

```
smbus_monitor: (smb_clk_in, smb_dat_in) → (byte_valid, byte_data, addr_phase)
smbus_arbiter: (smb_clk_in, smb_dat_in, gate_en) → (smb_clk_out, smb_dat_out)
spd_responder: (smb_clk, smb_dat_io, device_addr[3:0]) → (ack_driven)
pmbus_master:  (smb_clk, smb_dat_io) → [Placeholder — not designed]
telemetry_uart:(data_in[7:0], data_valid) → (uart_tx)
```

**[Placeholder]**: `pmbus_master` and SVID monitoring are not yet designed. The module file exists as a structural placeholder and is marked `NON_FUNCTIONAL` in its header.

### 3.3 SPD Pipeline

SPD bytes must not be hand-edited. The generation pipeline is:

```
tools/spd-gen/
  generate_spd.py   → Takes DDR3 JEDEC parameters → emits binary SPD image
  validate_spd.py   → Checks CRC and field ranges against JEDEC 21C
  spd_to_hex.py     → Formats binary for FPGA ROM initialization
```

The SPD responder loads its data from a ROM initialized at synthesis time from the validated hex file.

---

## 4. SMBus Topology

```
Z68 PCH SMBus master
    │
    ├── DIMM A1 SPD EEPROM  (0x50)
    ├── DIMM A2 SPD EEPROM  (0x51)
    ├── DIMM B1 SPD EEPROM  (0x52)
    ├── DIMM B2 SPD EEPROM  (0x53)
    ├── Thermal sensors     (various 0x18–0x1F range)
    └── [Interposer tap]    ← passive monitor tap via interposer
```

**[Inference]**: The Z68 PCH initiates SPD reads during POST. The interposer SMBus tap observes these reads. In Stage 1, the `spd_responder` may respond in place of one DIMM slot's EEPROM to inject synthetic SPD data. This requires holding the real EEPROM off the bus (isolating it) — a non-trivial bus isolation problem that must be validated on the bench before any live system test.

---

## 5. Sandy Bridge vs. Ivy Bridge CPUID and Straps

[Hypothesis — requires experimental validation]

Sandy Bridge (model 0x2A/0x2D): CPUID.Family=6, Model=0x2A  
Ivy Bridge   (model 0x3A):       CPUID.Family=6, Model=0x3A

The Z68 chipset firmware (and EFI) checks CPUID to select MRC parameters. Ivy Bridge also requires different power management initialization. The hypothesis is that if the interposer can:

1. Mask or alter CPU identification signals early in reset sequence
2. Present Sandy Bridge strapping to the PCH
3. Allow the system to complete MRC with Sandy Bridge parameters
4. Then allow the Ivy Bridge CPU to run

...then a limited form of Sandy-Bridge-compatible initialization might succeed. This is **highly speculative** and may be physically impossible due to DDR3 training differences and cache/memory topology changes. Do not advance to Stage 2 until Stage 0 baseline data clearly indicates a viable path.

---

## 6. Power Architecture

[Inference — requires board-level measurement]

| Rail | Nominal | Source | Notes |
|------|---------|--------|-------|
| VCORE | 0.8–1.35 V (VID-controlled) | On-board VRM | SVID bus from CPU |
| VTT | 0.675 V (half VDIMM) | On-board | DDR3 reference |
| VDIMM | 1.35 or 1.5 V | On-board | DDR3 supply |
| VCCPLL | 1.8 V | PMIC | CPU PLL supply |
| VCCA | 1.05 V | PMIC | CPU analog supply |
| 3.3V | 3.3 V | PSU | Logic supply |
| 5V | 5.0 V | PSU | Drive supply |
| 12V | 12.0 V | PSU | VRM input, fans |

Power sequencing is documented in `data/rails/power-sequencing-template.csv`. All values marked `[PLACEHOLDER]` until measured.

---

## 7. Known Unknowns

1. LGA 1155 interposer PCB physical feasibility — Z-height, impedance matching at DDR3 speeds
2. Whether Sandy Bridge and Ivy Bridge have different physical pin assignments or only CPUID differences
3. Whether Z68 PCH revision on this specific iMac supports Ivy Bridge at all (some Z68 revisions do not)
4. Whether MRC can be coerced with any interposer-level technique
5. Exact SMBus transaction sequence during Z68 POST
6. Whether Apple's EFI does additional silicon validation checks beyond CPUID

These are not filled in with guesses. They are research targets for Stage 0.
