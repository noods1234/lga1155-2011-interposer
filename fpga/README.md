# FPGA RTL

**Status**: Module stubs implemented; none yet validated on target hardware  
**Credibility**: [Inference] for design patterns; [Placeholder] for all timing constants

---

## Module Summary

| Module | File | Status | Testbench |
|--------|------|--------|-----------|
| SMBus passive monitor | `rtl/smbus_monitor.v` | Design complete; not hardware-tested | TODO |
| SMBus arbiter / gate | `rtl/smbus_arbiter.v` | Design complete; not hardware-tested | TODO |
| SPD EEPROM emulator | `rtl/spd_responder.v` | Partial — bit-level SDA drive NON_FUNCTIONAL | TODO |
| PMBus / SVID observer | `rtl/pmbus_master.v` | NON_FUNCTIONAL PLACEHOLDER | N/A |
| Telemetry UART TX | `rtl/telemetry_uart.v` | Design complete; standard pattern | TODO |

## Gate Conditions Before Any Module Goes on a Live Bus

1. Corresponding testbench passes in simulation (`fpga/tb/`)
2. Synthesis timing report shows no critical path violations at operating clock
3. The `smbus_arbiter` has been validated in pass-through mode on a bench SMBus (not connected to iMac) before being connected to the live system
4. `spd_responder` bit-level SDA drive is implemented and simulation-validated before inject_en_o is ever asserted on a live bus

## FPGA Target

[Placeholder — FPGA part not yet selected]

Selection criteria:
- Must close timing for 50 MHz system clock with SMBus monitor and UART paths
- Must support `$readmemh` for SPD ROM initialization
- Must have sufficient I/O count for all interposer signal taps
- Must be available in a package compatible with interposer PCB Z-height constraints

Candidate families: Lattice iCE40 (very small package, Stage 0–2 use), Lattice ECP5 (more resources for Stage 3+). Do not select until interposer PCB Z-height is confirmed (R-001).

## SPD ROM Initialization

**Never hard-code SPD bytes in the RTL.**

SPD data must be generated and validated before synthesis:

```bash
cd tools/spd-gen
python3 generate_spd.py --dimm-type ddr3 --capacity 8gb --speed 1333 \
    --org 2rx8 --vendor PLACEHOLDER --out ../../data/spd/generated.bin
python3 validate_spd.py --input ../../data/spd/generated.bin
python3 spd_to_hex.py --input ../../data/spd/generated.bin \
    --out ../../fpga/rtl/spd_rom.hex
```

Then instantiate `spd_responder` with:
```verilog
spd_responder #(
    .DEVICE_ADDR(3'b000),
    .SPD_HEX_FILE("../../fpga/rtl/spd_rom.hex")
) u_spd_resp ( ... );
```
