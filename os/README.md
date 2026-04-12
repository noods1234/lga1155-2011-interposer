# OS-Level Instrumentation

**Status**: [Placeholder] — no OS-level scripts written  
**Credibility**: [Placeholder]

This directory will contain OS-level instrumentation scripts for both Linux and macOS. These are secondary to hardware bring-up.

## Planned Contents

```
os/
  linux/
    smbus_sniff.sh         ← Wrapper around i2cdump / i2ctransfer for SPD reading
    cpuid_capture.sh       ← Wrapper around cpuid tool for leaf capture
    rail_monitor.sh        ← Read power rail voltages via hwmon if available
  macos/
    thermal_dump.sh        ← Read Apple SMC thermal sensors
    ioreg_platform.sh      ← Dump IORegistry platform entries
```

## Note

OS-level tools depend on the OS successfully booting, which depends on hardware bring-up succeeding first. Do not invest in OS tooling before Stage 1.
