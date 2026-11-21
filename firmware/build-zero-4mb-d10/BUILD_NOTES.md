# C5VRX 4 MB D10-forced build for the ESP32-C5-Zero

Local test build produced by this project. **Flashed and booted; D10 active;
the C5VRX menu raster locks on the Tang Nano and appears over HDMI. No FPV
camera/VTX was connected; live camera luma is still pending.**

This build exists because the C5VRX web flasher has no control for
**EXPERIMENTAL → Clock Pin D10**. The firmware is compiled with D10 forced on,
so no receiver-menu access is needed.

| Item | Value |
| --- | --- |
| C5VRX source | `main` @ `8b60fef0f43f` (2026-11-16) |
| Patches | `../esp32-c5-zero-4mb-d10.patch` (4 MB layout + forced D10 + bit 2 on GPIO6) |
| ESP-IDF | v6.0.2 (`7101770dc6db`), target `esp32c5` |
| App image | `c5vrx5.bin`, 1,255,536 bytes (`0x132870`) |
| App partition | 2.375 MiB (`0x260000`), 50% free |
| Merged image | `c5vrx5_zero_d10_merged.bin`, 1,321,072 bytes (`0x142870`) |
| Flash layout | 4 MB, DIO, 80 MHz; bootloader `0x2000`, partition table `0x8000`, app `0x10000` |
| Version / commit | `4mb-zero-d10-gpio6-test` / `local-d10` |

## D10 effect

The build sets `s_exp.value[EXP_CLOCK_D10] = 1` before the active D10 flag is
read. At boot:

- GPIO10 outputs the 40 MHz PARLIO TX clock.
- DAC bit 2 is routed to **GPIO6**.
- Console `T` should report:
  `SAMPLE_CLOCK enabled=1 requested=1 gpio=10 hz=40000000 dac_bit2_gpio=7 reboot=0`

The `7` in that upstream `T` line is a hardcoded print. The actual D10 setup
in this build is `cfg.data_gpio_nums[2] = 6`; use GPIO6.

### Why GPIO6 instead of the stock GPIO7

Stock C5VRX D10 uses **GPIO7** for bit 2. On the Zero, GPIO7 is a boot
strapping pin. With the FPGA tap connected, its pull-down/resistor load
prevented the app from booting: disconnecting GPIO7 made the same image boot.
GPIO6 is non-strapping and is not in C5VRX's internal IQ pin set, so this
build moves bit 2 there and leaves GPIO7 unconnected.

## Flash (app-only, preserves partition/NVS)

Enter the ROM loader with **hold BOOT → tap RESET → release BOOT**, then:

```sh
python -m esptool --chip esp32c5 -p PORT --before no-reset \
  --after watchdog-reset write-flash --flash-mode dio --flash-freq 80m \
  --flash-size 4MB 0x10000 c5vrx5.bin
```

Or flash the merged image at `0x0` (this overwrites the NVS gap):

```sh
python -m esptool --chip esp32c5 -p PORT write_flash 0x0 c5vrx5_zero_d10_merged.bin
```

Do not use the RTS hard reset; it hangs the Zero's native USB-JTAG. Open the
console with DTR asserted (115200); C5VRX's `tools/flash.py` DTR/RTS-low
monitor looks silent on the Zero. A physical power cycle is sometimes needed
after a watchdog reset before the USB console re-enumerates.

## Wiring

With this D10 build:

| DAC bit | GPIO | Zero pad |
| --- | ---: | --- |
| bit 0 | 23 | bottom |
| bit 1 | 24 | bottom |
| bit 2 | **6** | right |
| bit 3 | 12 | right |
| bit 4 | 8 | right |
| bit 5 | 9 | right |
| clock | 10 | right |
| GND | GND | left |

Move the bit-2 wire from GPIO7 to **GPIO6**; leave GPIO7 unconnected. The
Tang Nano pins are 25–30 for bits 0–5 and 35 for the clock (see
`docs/PINMAP.md`).
