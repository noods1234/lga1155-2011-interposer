# Salvage Audit: Inherited / Legacy Code

**Source repository**: `noods1234/apple-set-os`  
**Source branch**: `claude/haswell-interposer-imac-lcEvg`  
**Representative commit**: `bb1bacbc2190b89d13e89d43fd6d8ff50a6b7698`  
**Audit date**: Repository inception  
**Policy**: Every file is Keep / Rewrite / Reject. No file is carried over unchanged without explicit justification. No placeholder or synthetic value may remain unlabeled.

**Note on access**: The source repo is read-only for salvage purposes only. Do not develop inside it. The handoff document contains per-file analysis that was used to produce this audit.

---

## Executive Summary

The source branch is worth **mining, not inheriting**. It contains real scaffolding, some technically literate work, and useful subsystem ideas. It does not demonstrate closure on the core hardware risks. The biggest problems are:

1. Repository identity is still that of the older `apple_set_os.efi` utility — this project owns a different problem boundary.
2. The FPGA bridge file is a single monolithic module combining SMBus, SPD emulation, PMBus, and DDR timing in one file — untestable as a unit.
3. The EFI CPUID file uses hard-coded protocol function pointer offsets rather than typed EFI protocol structs — fragile and incorrect.
4. `--nop-mrc` appears as a usable code path rather than a quarantined experiment — violates the project's non-negotiable rules.
5. The most critical subsystem (memory initialization closure) is still speculative.

---

## File-by-File Salvage Table

| # | Path (source) | Subsystem | Current Status | Credibility | Decision | Reason | Immediate Next Action |
|---|---------------|-----------|---------------|-------------|----------|--------|----------------------|
| 1 | `interposer/memory/fpga_ddr_bridge.v` | FPGA / SMBus / SPD / PMBus | Conceptual scaffold with real RTL blocks. Hard-coded SPD content with placeholder CRC. Simplified timing comments that do not constitute an electrical interface spec. External level-shift assumed without specification. | Low-to-moderate | **Rewrite** | (a) Monolithic — combines SMBus monitor, SPD responder, PMBus stub, and DDR timing hints in one file. (b) SPD bytes are hard-coded with a placeholder CRC — invalid for any live experiment. (c) Timing comments are not synthesis constraints. (d) No testbench. (e) Level-shift assumption unspecified. | Split into five modules: `smbus_monitor.v`, `smbus_arbiter.v`, `spd_responder.v`, `pmbus_master.v` (stub), `telemetry_uart.v`. Replace inline SPD ROM with output from `tools/spd-gen/` pipeline. Add testbench for each module. |
| 2 | `efi/haswell_e_cpuid.c` | EFI bring-up helper | Real EFI source. Uses EFI services and MP startup logic. Protocol function pointers obtained via hard-coded byte offset arithmetic rather than proper typed protocol structures. | Moderate (EFI structure knowledge present; access pattern wrong) | **Rewrite** | (a) Hard-coded protocol pointer offsets are not portable across EFI implementations. (b) Offset access bypasses the typed `EFI_BOOT_SERVICES.LocateProtocol()` contract. (c) Absent: phase logging, serial/debug trace checkpoints, measurable abort conditions. (d) Absent: any mechanism to distinguish Sandy Bridge vs. Ivy Bridge before taking action. | Rewrite as `efi/src/cpuid_audit.c` — read-only, typed protocol access, full CPUID leaf dump to serial. No spoofing. Spoofing is Stage 2+ only, in a separate file, with explicit experiment gate. |
| 3 | `scripts/analyze_efi_cpuid.py` | Firmware extraction / analysis / patching | One of the more useful inherited files. Clearly exposes the experimental firmware strategy including `--nop-mrc`. Parsing logic appears genuine and reusable. `--nop-mrc` is present as a code path but not behind an experiment gate. | Moderate | **Keep parsing logic; rewrite structure** | (a) The core parsing and pattern-matching logic is worth carrying forward. (b) The monolithic script mixes extraction, analysis, patch generation, and validation — these must be separate tools with separate outputs. (c) `--nop-mrc` must be moved behind an experiment profile; it must never be the default or a simple flag. | Split into `tools/efi-audit/extract.py`, `tools/efi-audit/analyze.py`, `tools/efi-audit/patchgen.py`, `tools/efi-audit/validate.py`. Preserve useful parsing logic in `analyze.py`. Move `--nop-mrc` into a named experiment profile in `experiments/mrc-nop-hypothesis/`. |
| 4 | `opencore/ACPI/SSDT-PMC.dsl` | ACPI / macOS integration | Best of the four reviewed files. Z68/Cougar Point device model is internally coherent. Correctly retains `SBUS` at D31:F3. Correctly omits an earlier mistaken `PPMC` declaration. | Moderate-to-high | **Keep with light review** | (a) Correct device model for Z68 Cougar Point. (b) SBUS placement is accurate. (c) No mistaken PPMC. (d) Still requires verification against a real iMac DSDT before use — the SSDT may add a device that already exists in the DSDT, which would cause a conflict. | Move to `opencore/ACPI/reference/SSDT-PMC-z68-reference.dsl`. Add header noting it is a reference fragment, not ready-to-apply. Obtain real DSDT via `acpidump` in Stage 0 and verify compatibility before any use. |

---

## Additional Files (Inferred from Repo Structure)

| # | Path (inferred) | Decision | Reason |
|---|----------------|----------|--------|
| 5 | `opencore/config.plist` | **Reject** | If derived from the same lineage as the CPUID C file, it will contain wrong-platform CPUID masks. Build from scratch in Stage 2+ against actual hardware. |
| 6 | Any `mrc_bypass.*` | **Quarantine → `experiments/mrc-nop-hypothesis/`** | `--nop-mrc` is not a default. Any script that wraps MRC bypass as a callable option must be moved to experiments and given `EXPERIMENT_ONLY` headers. |
| 7 | Old `README.md` / `docs/` | **Reject root identity; extract claims case-by-case** | Repository identity must not be carried over. Individual factual claims may be worth extracting if tagged with credibility. |
| 8 | `interposer/` directory structure | **Partial — use as reference only** | The directory decomposition concept is useful but the module boundaries are wrong. New fpga/ layout supersedes it. |

---

## What to Carry Forward

| Item | Disposition | Target path |
|------|-------------|-------------|
| Corrected Z68 ACPI logic (`SBUS` vs. `PPMC` fix) | Keep as reference fragment | `opencore/ACPI/reference/SSDT-PMC-z68-reference.dsl` |
| Firmware extraction and analysis pipeline concept | Rewrite into four tools | `tools/efi-audit/` |
| SMBus monitor RTL concept | Rewrite as standalone module | `fpga/rtl/smbus_monitor.v` |
| SPD responder concept | Rewrite with external ROM | `fpga/rtl/spd_responder.v` |
| SMBus arbiter concept | Rewrite as standalone module | `fpga/rtl/smbus_arbiter.v` |
| Telemetry UART concept | Rewrite as standalone module | `fpga/rtl/telemetry_uart.v` |

## What NOT to Carry Forward

| Item | Reason |
|------|--------|
| Old repo identity / README | Wrong project boundary |
| Hard-coded SPD bytes and placeholder CRC | Invalid for any live experiment |
| Hard-coded EFI protocol pointer offsets | Fragile; incorrect access pattern |
| `--nop-mrc` as a default or simple flag | Violates project non-negotiable rule #9 |
| Any claim that OpenCore completion is near or that OS integration is a near-term gate | Hardware bring-up truth is the primary criterion |
| DDR3 signal routing logic from `fpga_ddr_bridge.v` | Deferred to Stage 3+; not carried into active code |
| PMBus master logic from `fpga_ddr_bridge.v` | Stub only; not implemented |
