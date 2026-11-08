# ACPI analysis: how the Chuwi LarkBox fan is controlled

Hardware: Chuwi LarkBox, Intel Celeron J4115 (Gemini Lake), 6 GB RAM, 2-wire fan (no PWM, no tachometer).
BIOS: American Megatrends `GB01_ZW_1_03`, 09.07.2020.
Tables were exported from the Windows registry (`HKLM\HARDWARE\ACPI`) and decompiled with `iasl`.

## 1. The documented fan paths are dead code

The BIOS is based on Intel's reference code and contains every standard way of controlling a fan, but none of them can work on this board:

| Path | Where | What it does |
|---|---|---|
| DPTF fan participant `TFN1` (INT3404) | `DptfTab` SSDT | `_FSL` / `_FST` read and write the fan level through `\_SB.PCI0.SBRG.H_EC` |
| ACPI fan `FAN0` + power resource `FN00` | DSDT | `_ON` / `_OFF` call `FCTL`, which writes to the EC |
| Thermal zone `TZ01` | DSDT | `_AC0` trip points turn `FAN0` on and off |

All of them end in the embedded controller `H_EC`, and:

- `H_EC._STA` returns `Zero`: the EC is declared absent. Windows also reports the EC firmware version as 255.255.
- `ECRD` returns hard-coded values, and `ECWT` and `ECMD` have empty bodies.
- `TFN1` is only enabled when the BIOS fan option (`DFAN`) is on, and its methods are stubs anyway.

The Windows driver for this machine is the stock Intel DPTF 8.4 package (`dptf_acpi.sys`, `dptf_cpu`, `esif_uf.exe`). There is nothing LarkBox-specific in it, and it doesn't access I/O ports.

## 2. The real fan switch is hidden in `SEN4._TMP`

`DptfTab` defines a DPTF temperature sensor:

```asl
Device (SEN4)
{
    Name (_HID, EisaId ("INT3403"))        // DPTF Temperature Sensor
    Name (_UID, "SEN4")
    Name (_STR, Unicode ("Thermistor Skin"))
    ...
    Method (_TMP, 0, Serialized)  // _TMP: Temperature
    {
        If ((\_SB.IETM.KTOC (\_SB.PCI0.TCPU.TMP1 ()) > 0x37))
        {
            \_SB.GPO0.TMPE = 0x44000201
        }
        Else
        {
            \_SB.GPO0.TMPE = 0x44000200
        }

        If (\_SB.PCI0.SBRG.H_EC.ECAV)
        {
            Return (\_SB.IETM.CTOK (\_SB.PCI0.SBRG.H_EC.ECRD (RefOf (\_SB.PCI0.SBRG.H_EC.TSR4))))
        }
        Else
        {
            Return (0x0BB8)
        }
    }
    ...
}
```

- `TCPU.TMP1()` returns the CPU package temperature (`PKGT`) in tenths of a kelvin. `KTOC` converts it to °C, and `0x37` = **55 °C**.
- `TMPE` is defined in the DSDT under the GPIO controller `GPO0` (INT3453, `_UID 2`, "North" community):

  ```asl
  OperationRegion (TMPN, SystemMemory, 0xD0C509E0, 0x08)
  Field (TMPN, DWordAcc, NoLock, Preserve)
  {
      TMPE,   32
  }
  ```

  `0xD0C509E0` is the `PAD_CFG_DW0` register of a north-community pad (offset `0x9E0`, pad 62 counting from the `0x600` pad-config base with a 16-byte stride).
- Values written to `PAD_CFG_DW0`:

  | Value | Mode | RX | TX | Output |
  |---|---|---|---|---|
  | `0x44000201` | GPIO | disabled | enabled | **1 → fan on** |
  | `0x44000200` | GPIO | disabled | enabled | **0 → fan off** |

- Because `H_EC.ECAV` is 0, `_TMP` always returns `0x0BB8` = 3000 = 300.0 K = **26.85 °C**. The sensor reading is fake, only the side effect matters.

## 3. Why Windows works and Linux doesn't

- **Windows:** the DPTF service polls every participant periodically (`_TSP`), so `SEN4._TMP` runs every few seconds, which gives a 55 °C thermostat with no hysteresis.
- **Linux:** `int3403_thermal` registers `SEN4` as a thermal zone (`type` = `SEN4`, `temp` = 26850). The int340x driver is notification-driven and sets no polling interval, so `_TMP` only runs when something happens to read the zone. The GPIO keeps whatever value it got at the last read.

That explains every symptom reported for Linux:

- the fan works after installation (the installer or a monitoring tool read the zone) and stops after a reboot;
- the fan runs constantly (last read was above 55 °C);
- `thermald` helps on some systems, because it happens to read `SEN4`;
- toggling BIOS fan options changes nothing.

It was confirmed experimentally: with the CPU below 55 °C, `cat /sys/class/thermal/thermal_zone2/temp` stops a running fan instantly. Under load above 55 °C, the same command starts it.

## 4. Unrelated: `_PTS` and GPIO_214

`PPTS` (called from `_PTS`) writes `\_SB.SGOV (0x00C40AF0, Zero)`, which is northwest-community pad 79, `GPIO_214`. Under Linux this pad is in GPIO mode with its output buffer disabled (`PAD_CFG_DW0` = `0x44000102`), so this write has no effect. It is not the fan switch.
