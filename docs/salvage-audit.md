# Salvage Audit — Engineering Ledger

**Source repository**: `noods1234/apple-set-os`  
**Source branch**: `claude/haswell-interposer-imac-lcEvg`  
**Representative commit**: `bb1bacbc2190b89d13e89d43fd6d8ff50a6b7698`  
**Policy**: Every inherited artifact is Keep / Rewrite / Reject. No file is promoted to the new repo without an explicit row in this table.  
**Ledger version**: 2 (expanded from initial summary; reflects actual implementation state)

---

## Column Definitions

| Column | Meaning |
|--------|---------|
| `inherited_path` | Path in `noods1234/apple-set-os` |
| `new_path` | Path in this repo, or `—` if rejected |
| `subsystem` | Functional area |
| `decision` | Keep / Rewrite / Reject |
| `credibility` | Verified / Inference / Hypothesis / Placeholder |
| `impl_status` | Current state of the new-path artifact |
| `validation_status` | What has been confirmed against hardware or spec |
| `blocker` | What prevents promotion to next stage |
| `next_action` | Concrete next step with owner field |
| `notes` | Rationale and context |

---

## Primary Files

### Row 1 — FPGA Bridge

| Field | Value |
|-------|-------|
| **inherited_path** | `interposer/memory/fpga_ddr_bridge.v` |
| **new_path** | `fpga/rtl/smbus_monitor.v`, `fpga/rtl/smbus_arbiter.v`, `fpga/rtl/spd_responder.v`, `fpga/rtl/pmbus_master.v`, `fpga/rtl/telemetry_uart.v` |
| **subsystem** | FPGA / SMBus / SPD |
| **decision** | **Rewrite** |
| **credibility** | [Inference] — design patterns; [Placeholder] — all timing parameters |
| **impl_status** | Partial. `smbus_monitor.v` and `telemetry_uart.v` are structurally complete. `smbus_arbiter.v` clock-stretching is a marked stub. `spd_responder.v` bit-level SDA drive is NON_FUNCTIONAL. `pmbus_master.v` is a tie-off stub. |
| **validation_status** | Not validated. No testbench. No simulation run. No hardware test. |
| **blocker** | (1) `spd_responder.v` address match was wrong (BUG-01 — fixed in audit pass). (2) Bit-level I2C SDA output not implemented in `spd_responder.v`. (3) Clock stretching not implemented in `smbus_arbiter.v`. (4) No testbench for any module. SPD ROM has no validated hex image to load. |
| **next_action** | Write `fpga/tb/smbus_monitor_tb.v` and `fpga/tb/telemetry_uart_tb.v`. These are the minimum for Stage 1 gate. Do not advance `spd_responder` or `smbus_arbiter` to hardware until bit-level timing and clock stretch are implemented and simulated. |
| **notes** | Old `fpga_ddr_bridge.v` was monolithic (one file covering SMBus, SPD, PMBus, and DDR3 hints). Hard-coded SPD bytes with placeholder CRC. No synthesis constraints. No testbench. Split was correct; depth of each new module is still insufficient for hardware deployment. SPD content replaced with `$readmemh` pipeline; ROM hex file not yet generated (requires Stage 0 DIMM capture). `MY_ADDR_W/MY_ADDR_R` localparams from old code were wrong and removed. |

---

### Row 2 — EFI CPUID Helper

| Field | Value |
|-------|-------|
| **inherited_path** | `efi/haswell_e_cpuid.c` |
| **new_path** | `efi/src/cpuid_audit.c`, `efi/src/msr_audit.c` |
| **subsystem** | EFI / Platform Identification |
| **decision** | **Reject** inherited; **rewrite** from scratch |
| **credibility** | [Inference] — EFI protocol patterns; [Placeholder] — not compiled on target |
| **impl_status** | `cpuid_audit.c`: structurally complete, uses typed EFI protocol access, decodes Sandy Bridge vs. Ivy Bridge from leaf 0x01 ECX. `msr_audit.c`: complete, reads 20 relevant MSRs with CPU-identity filter. `CpuidAudit.inf` and `MsrAudit.inf`: build definitions written; `[Includes]` section was missing and has been fixed (BUG-03). |
| **validation_status** | Not compiled. Not tested on any platform. Not tested on iMac12,2 Apple EFI specifically. |
| **blocker** | (1) EDK II build environment not set up in this repo. (2) Apple EFI compatibility with `EFI_MP_SERVICES_PROTOCOL` unknown (R-005). (3) `AsmReadMsr64` has no `#GP` guard; tool will hang on unknown MSR. |
| **next_action** | Set up EDK II build. Compile both tools. Test on any UEFI platform before iMac12,2. Document which EDK II tag and toolchain were used. |
| **notes** | The rejected `haswell_e_cpuid.c` targeted Haswell-E (LGA2011-3) — wrong CPU family for this project. It also used hard-coded function-pointer offset arithmetic to access EFI services, bypassing the typed `gBS` interface. Both problems are corrected in the rewrite. The rewrite is read-only. No CPUID spoofing. `msr_audit.c` C89 declaration-after-statement bug was found and fixed in audit pass (BUG-02). |

---

### Row 3 — EFI Firmware Analysis Script

| Field | Value |
|-------|-------|
| **inherited_path** | `scripts/analyze_efi_cpuid.py` |
| **new_path** | `tools/efi-audit/extract.py`, `tools/efi-audit/analyze.py`, `tools/efi-audit/patchgen.py`, `tools/efi-audit/validate.py` |
| **subsystem** | Tools / Firmware Analysis |
| **decision** | **Keep parsing logic; rewrite structure** |
| **credibility** | [Inference] — CPUID instruction encoding and PE32+ parsing patterns |
| **impl_status** | All four tools written. `analyze.py` core pattern-matching logic preserved from old script. `patchgen.py` `mrc-nop-hypothesis` profile exists but generates no patches (MRC call site not yet identified — correct behavior). `validate.py` binary-diff logic complete. |
| **validation_status** | Not run against any EFI binary. Patterns not validated against iMac12,2 Apple EFI. `pefile` dependency not tested. |
| **blocker** | Apple EFI binary not yet obtained. Stage 0 must produce the binary before these tools can be validated. `--profile mrc-nop-hypothesis` correctly generates no patches (MRC call site not yet identified). |
| **next_action** | Obtain Apple EFI binary in Stage 0 (T0.3 acpidump will also reveal EFI volume structure). Run `extract.py` and `analyze.py`. Record how many CPUID references are found and at what offsets. Commit results to `data/` with credibility tags. |
| **notes** | Original script mixed extraction, analysis, patch generation, and validation in one file. `--nop-mrc` was a reachable flag, not an experiment-gated path. Rewrite correctly separates concerns and places MRC bypass behind `--experiment-gate-confirmed`. The patching pipeline (patchgen → validate → apply) enforces backup-before-patch. |

---

### Row 4 — ACPI SSDT-PMC

| Field | Value |
|-------|-------|
| **inherited_path** | `opencore/ACPI/SSDT-PMC.dsl` |
| **new_path** | `opencore/ACPI/reference/SSDT-PMC-z68-reference.dsl` |
| **subsystem** | ACPI / OpenCore |
| **decision** | **Keep with light review** (reference fragment only) |
| **credibility** | [Inference] — Z68/Cougar Point device topology; not verified against real iMac12,2 DSDT |
| **impl_status** | File moved to `reference/` subdirectory. Header annotated with verification requirements. PMC device entry left as commented-out Placeholder. SBUS at D31:F3 retained as the primary reference fragment. |
| **validation_status** | Not verified against actual iMac12,2 DSDT. DSDT dump not yet obtained (Stage 0 task T0.3). |
| **blocker** | Stage 0 must produce `data/acpi/dsdt-decompiled.dsl`. Must check whether SBUS device already exists in DSDT before applying this SSDT. If it already exists, this SSDT is unnecessary and applying it will create an ACPI conflict. |
| **next_action** | Complete Stage 0 T0.3. Compare SSDT against real DSDT. Decision outcomes: (a) SBUS missing from DSDT → keep SSDT, mark [Verified]; (b) SBUS present in DSDT → reject SSDT as unnecessary; (c) SBUS present but broken → keep SSDT with modifications, mark [Verified]. |
| **notes** | Old version had a mistaken `PPMC` device declaration that conflicted with standard Cougar Point ACPI tables. That was removed. The corrected version retains only SBUS at D31:F3, which is the well-documented Z68 SMBus controller placement. Do not promote this from reference to active use until DSDT check is complete. |

---

## Additional Files (Inferred or Discovered)

### Row 5 — OpenCore config.plist

| Field | Value |
|-------|-------|
| **inherited_path** | `opencore/config.plist` (inferred present) |
| **new_path** | — (rejected) |
| **decision** | **Reject** |
| **credibility** | [Hypothesis] — likely contains Haswell-E or wrong-family CPUID masks |
| **impl_status** | Not imported |
| **next_action** | Build from scratch in Stage 2+ using OpenCore documentation and actual hardware CPUID data from Stage 0. |

---

### Row 6 — MRC Bypass Scripts

| Field | Value |
|-------|-------|
| **inherited_path** | Any `mrc_bypass.*` or `--nop-mrc`-wrapping script |
| **new_path** | `experiments/mrc-nop-hypothesis/` (quarantined) |
| **decision** | **Quarantine** |
| **credibility** | [Hypothesis] |
| **impl_status** | `patchgen.py --profile mrc-nop-hypothesis` exists but generates no patches. Quarantine README documents gate conditions. |
| **next_action** | Do not advance. MRC call site must be identified by disassembly before this experiment can proceed. |

---

## Ledger Status

| Decision | Count | Notes |
|----------|-------|-------|
| Rewrite (complete) | 2 | FPGA RTL split, EFI tools rewrite |
| Rewrite (partial) | 1 | FPGA modules have structural gaps |
| Keep with review | 1 | SSDT-PMC reference fragment |
| Reject | 2 | haswell_e_cpuid.c, config.plist |
| Quarantine | 1 | MRC bypass |

**Bugs found and fixed during this audit pass:**
- BUG-01: `spd_responder.v` address match always-false (removed wrong first condition)
- BUG-02: `msr_audit.c` C89 declaration-after-statement
- BUG-03: INF files missing `[Includes]` section
- BUG-04: Dead `bit_idx` register in `spd_responder.v`
- BUG-05: `smbus_monitor.v` CLK_DIV default 125 → 31 (400 kHz correct default)

**Not yet fixed (require design work, not one-line edits):**
- `spd_responder.v` SS_SEND_BYTE bit-level SDA output: NON_FUNCTIONAL, correctly labeled
- `smbus_arbiter.v` clock-stretching: STUB, correctly labeled
- Missing testbenches: gate condition for Stage 1 unmet

---

*This ledger must be updated when any inherited artifact changes status, when a new bug is found, or when a validation step is completed.*
