# Firmware

**Status**: [Placeholder] — no MCU selected or firmware written  
**Credibility**: [Placeholder]

This directory is reserved for microcontroller firmware if the interposer design includes an MCU in addition to (or instead of) the FPGA for slow-control, configuration, and USB bridging.

## Likely Use Cases

- FPGA configuration sequencing (loading bitstream from SPI flash)
- USB-to-UART bridge for telemetry output
- Power sequencing control and monitoring
- I2C/SMBus host for configuring FPGA registers

## Decision Gate

MCU selection and firmware development begins only after the FPGA module design is stable and the interposer PCB schematic is drafted. The MCU must not be selected before the Z-clearance measurement (R-001) confirms PCB feasibility.

## Directory Structure (Planned)

```
firmware/
  src/       ← C source files
  include/   ← Headers
  Makefile   ← Build system (to be determined by MCU selection)
```
