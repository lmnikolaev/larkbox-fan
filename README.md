# larkbox-fan

**Fan control for the Chuwi LarkBox mini PC (Celeron J4115) on Linux.**

[Русская версия](README.ru.md)

On Linux the LarkBox fan behaves randomly: it may work after installation and then never spin again after a reboot, or it may run all the time. This package makes the fan work exactly like on Windows: **on above 55 °C, off below**. No kernel module, no BIOS changes.

## How it works (short version)

The LarkBox BIOS has no working fan controller. Instead, the fan is switched **inside the ACPI method that reports the temperature of the DPTF sensor `SEN4`**. Every time the OS reads that temperature, the firmware compares the CPU temperature with 55 °C and switches the fan's GPIO on or off.

- **Windows:** Intel DPTF polls the sensor every few seconds, so the fan works as a thermostat.
- **Linux:** the kernel exposes `SEN4` as a thermal zone but never polls it, so the fan stays stuck in whatever state it had at the last read.

`larkbox-fan` is a tiny systemd service that reads the `SEN4` temperature every 5 seconds. That's all it takes.

The full analysis of the ACPI tables is in [docs/acpi-analysis.md](docs/acpi-analysis.md).

## Requirements

- Chuwi LarkBox (Celeron J4115). Other Chuwi Gemini Lake models may work too, see [Other models](#other-models).
- Debian 13 or newer, Ubuntu 23.04 or newer, or any other Debian-based distribution with systemd 253+.

## Quick install

One command downloads the latest release and installs it:

```sh
curl -fsSL https://raw.githubusercontent.com/lmnikolaev/larkbox-fan/main/install.sh | sudo sh
```

The script checks the model, downloads the `.deb` from [Releases](https://github.com/lmnikolaev/larkbox-fan/releases/latest), moves an old hand-made `larkbox-fan.service` (if any) out of the way and installs the package with `apt`. You can [read it first](install.sh), it's short. If `curl` is missing, run `sudo apt install curl` first.

## Manual installation

1. Download `larkbox-fan_1.0-1_all.deb` from the [Releases](https://github.com/lmnikolaev/larkbox-fan/releases/latest) page.
2. Install it:
   ```sh
   sudo apt install ./larkbox-fan_1.0-1_all.deb
   ```
3. Check that the service is running:
   ```sh
   systemctl status larkbox-fan
   ```
   You should see `active (running)` and a log line like `Polling /sys/class/thermal/thermal_zone2/temp every 5s`.

The service starts automatically on every boot.

> **Already using a hand-made service with the same name?** Remove it first:
> ```sh
> sudo systemctl disable --now larkbox-fan
> sudo rm /etc/systemd/system/larkbox-fan.service
> sudo systemctl daemon-reload
> ```

### Without the package

On a non-Debian distribution, copy the two files from `src/` and enable the service:

```sh
sudo install -Dm755 src/larkbox-fan /usr/libexec/larkbox-fan/larkbox-fan
sudo install -Dm644 src/larkbox-fan.service /usr/lib/systemd/system/larkbox-fan.service
sudo systemctl daemon-reload
sudo systemctl enable --now larkbox-fan
```

On systemd older than 253, remove the `ConditionFirmware=` line from the service file.

## Checking that it works

Put the CPU under load and listen to the fan:

```sh
for i in 1 2 3 4; do yes > /dev/null & done   # start load
watch -n2 'grep -H . /sys/class/thermal/thermal_zone*/temp'
pkill yes                                      # stop load
```

The fan should start within about 5 seconds once the CPU (`x86_pkg_temp` / `TCPU`) goes above 55 °C, and stop a little after it cools down.

Note that `SEN4` itself always shows **26850** (26.85 °C). That's normal: the sensor is fake, only its side effect matters.

## Configuration

Change the polling interval (default 5 s):

```sh
sudo systemctl edit larkbox-fan
```

```ini
[Service]
Environment=LARKBOX_FAN_INTERVAL=2
```

The 55 °C threshold is hard-coded in the BIOS and can't be changed by this package.

## Uninstall

```sh
sudo apt remove larkbox-fan
```

## Safety

- The service only **reads** a sysfs file. It doesn't write to hardware registers, so it can't damage anything.
- It runs as an unprivileged dynamic user in a sandbox (`ProtectSystem=strict`, no network, no home access).
- It only starts on machines whose SMBIOS product name begins with `LarkBox`, and exits quietly if no `SEN4` thermal zone exists.
- Reading `/sys` causes no disk I/O.

## Other models

Other Chuwi mini PCs based on Gemini Lake (LarkBox Pro, Herobox, …) probably use the same BIOS trick, but this hasn't been tested. To check yours:

```sh
grep -H . /sys/class/thermal/thermal_zone*/type    # is there a SEN4 zone?
cat /sys/class/dmi/id/product_name                  # what is the model name?
```

If there's a `SEN4` zone, reading its `temp` while the CPU is above 55 °C should start the fan. If it works but your product name doesn't start with `LarkBox`, please open an issue so the service condition can be extended.

## Credits

The polling workaround was first found by **braikin** and **GinKage** on the [Chuwi forum](https://forum.chuwi.com/t/larkbox-fan-does-not-work-rigth-on-linux/14697) in 2020. This project explains why it works and packages it properly.

## License

[MIT](LICENSE)
