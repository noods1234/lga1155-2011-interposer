# EFI Audit Tools

**Status**: Rewrite of `analyze_efi_cpuid.py` from salvage corpus  
**Credibility**: [Inference] — tool structure is sound; patterns unvalidated against real Apple EFI binary

## Tools

| Tool | Purpose | Status |
|------|---------|--------|
| `extract.py` | Extract sections from PE32+ EFI binary | Scaffold; requires `pefile`; not tested vs. Apple EFI |
| `analyze.py` | Scan binary for CPUID instruction references | Pattern matching implemented; patterns [Inference] |
| `patchgen.py` | Generate binary patch records from analysis | Implemented; `mrc-nop-hypothesis` profile is PLACEHOLDER stub |
| `validate.py` | Validate and apply patches to binary | Validation logic complete; not yet tested |

## Pipeline

```
<efi.bin>
    │
    ▼
extract.py ──► sections/text.bin
    │
    ▼
analyze.py ──► analysis.json
    │
    ▼
patchgen.py (--profile <name>) ──► patches.json
    │
    ▼
validate.py (--check) ──► pass/fail
    │
    ▼
validate.py (--apply --output patched.bin) ──► patched.bin
```

## Salvage Note

The core CPUID pattern-matching logic is preserved from the old branch's `analyze_efi_cpuid.py`. The following were changed in this rewrite:

- Split into four separate tools with single responsibilities
- `--nop-mrc` moved to `patchgen.py --profile mrc-nop-hypothesis` behind `--experiment-gate-confirmed`
- JSON structured output instead of ad-hoc text
- Patterns annotated with credibility and confidence levels

## Getting Started

```bash
pip install pefile     # for extract.py
# No other dependencies beyond Python 3.8+
```
