# Experiment: MRC NOP Hypothesis

**Status**: QUARANTINED — do not activate  
**Credibility**: [Hypothesis]  
**Risk register**: R-003  
**Gate condition**: Stage 0 complete AND explicit written decision to proceed

---

## What This Experiment Is

This directory quarantines the `--nop-mrc` concept from the old branch. The idea is: identify the MRC (Memory Reference Code) call site in the Apple EFI binary and replace it with NOP instructions, then observe what happens.

**Expected outcome**: Boot failure. The system will hang during memory initialization because MRC is responsible for training the DDR3 channels, configuring the memory controller, and making DRAM usable. Without it, no memory is available and the platform cannot proceed.

**Diagnostic value**: Observing the exact failure point (hang location, any diagnostic codes, power rail behavior) may reveal how MRC interacts with the interposer and what the minimum viable MRC inputs are.

## Why It Is Quarantined Here

The `--nop-mrc` path existed as a reachable code path in the old branch's `scripts/analyze_efi_cpuid.py`. Per project non-negotiable rule #9:

> Treat `--nop-mrc` as an experiment only, never as a default solution.

The patch generation for this experiment is implemented in `tools/efi-audit/patchgen.py` under the `mrc-nop-hypothesis` profile, behind an `--experiment-gate-confirmed` flag. To use it:

```bash
# Step 1: Analyze the EFI binary
python3 tools/efi-audit/extract.py --input <efi.bin> --outdir sections/
python3 tools/efi-audit/analyze.py --input sections/text.bin --output mrc_analysis.json

# Step 2: Generate the patch (requires explicit gate flag)
python3 tools/efi-audit/patchgen.py \
    --analysis mrc_analysis.json \
    --profile mrc-nop-hypothesis \
    --experiment-gate-confirmed \
    --output mrc_nop_patch.json

# Step 3: Validate against original binary
python3 tools/efi-audit/validate.py \
    --binary <efi.bin> \
    --patches mrc_nop_patch.json \
    --check
```

## Gate Conditions Before Running

- [ ] Stage 0 all deliverables complete and committed
- [ ] Physical recovery method verified (CMOS clear restores original EFI; Apple Internet Recovery confirmed reachable)
- [ ] MRC call site identified in EFI binary by disassembly (not just pattern match)
- [ ] Risk R-003 reviewed and accepted for this specific experiment instance
- [ ] A [Verified] backup of the original EFI binary stored off-system

## Current Status of MRC Call Site Identification

**[Placeholder]** — The MRC call site in the iMac12,2 Apple EFI binary has not been identified. `patchgen.py --profile mrc-nop-hypothesis` currently generates no patches (the function returns a placeholder stub). This is intentional.

To progress this experiment: complete Stage 0, obtain the Apple EFI binary, disassemble it, and locate the MRC initialization sequence. Document the offset and bytes here before touching the patchgen implementation.
