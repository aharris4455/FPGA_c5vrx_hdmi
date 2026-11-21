# Firmware patches

## `esp32-c5-zero-4mb.patch`

The Waveshare **ESP32-C5-Zero** has **4 MB of flash**. C5VRX's stock build
assumes 8 MB:

- `sdkconfig.defaults` selects `CONFIG_ESPTOOLPY_FLASHSIZE_8MB`.
- `partitions.csv` lays out a 3 MiB app and a 1.5 MiB flight log, ending at
  `0x490000` (4.56 MiB).

The release app image is about 1.2 MiB, so the 4 MB layout in this patch
keeps the 1.5 MiB flight log and shrinks the app partition to 2.375 MiB:

| Partition | Stock 8 MB layout | Zero 4 MB layout |
| --- | ---: | ---: |
| factory app | 3 MiB | 2.375 MiB |
| flightlog | 1.5 MiB | 1.5 MiB |
| end offset | `0x490000` | `0x3F0000` |

`0x3F0000` is inside the Zero's 4 MiB (`0x400000`) flash. Do **not** flash the
stock prebuilt 8 MB image to the Zero; build from source with this patch.

### Apply

```sh
git clone https://github.com/Twotoz/C5VRX.git
cd C5VRX
git apply /path/to/esp32-c5-zero-4mb.patch
rm -f sdkconfig                 # sdkconfig.defaults changed
IDF_TARGET=esp32c5 idf.py build
```

For the Zero, flash through the ROM loader, not the XIAO-oriented
`tools/flash.py` path:

1. Hold BOOT, tap RESET, release BOOT.
2. Erase and flash (this wipes NVS/calibration):

```sh
esptool --chip esp32c5 -p PORT --before no-reset --after watchdog-reset \
  write-flash --erase-all --flash-mode dio --flash-freq 80m --flash-size 4MB \
  0x2000 build/bootloader/bootloader.bin \
  0x8000 build/partition_table/partition-table.bin \
  0x10000 build/c5vrx5.bin
```

Do not use esptool's RTS hard reset on the Zero; it hangs the native
USB-JTAG. The C5VRX `tools/flash.py` opens the console with DTR/RTS low and
expects the XIAO's USB path; on the Zero, console output requires **DTR high**
(see below).

Use ESP-IDF **6.0.2** as required by C5VRX. The Zero has no PSRAM, so use the
standard build, not `sdkconfig.psram.defaults`.

### D10-forced build (no web/menu access)

The C5VRX web flasher does not expose **EXPERIMENTAL → Clock Pin D10**. For
the FPGA tap, use the combined patch
[`esp32-c5-zero-4mb-d10.patch`](esp32-c5-zero-4mb-d10.patch), which applies
the 4 MB layout and sets `s_exp.value[EXP_CLOCK_D10] = 1` before the active
D10 flag is read. The build is in
[`build-zero-4mb-d10/`](build-zero-4mb-d10/) with
[build notes](build-zero-4mb-d10/BUILD_NOTES.md).

At boot it forces:

- GPIO10 = 40 MHz PARLIO TX clock
- DAC bit 2 = **GPIO6**
- `T`: `SAMPLE_CLOCK enabled=1 gpio=10 hz=40000000 dac_bit2_gpio=7`
  (the `7` is an upstream hardcoded print; the actual setup is GPIO6)

GPIO7, the stock C5VRX D10 bit-2 pin, is a boot strapping pin; with the FPGA
tap connected its load blocked boot on the Zero. This build moves bit 2 to
GPIO6 and leaves GPIO7 unconnected.

D10 cannot be turned off in this build; use the layout-only
`esp32-c5-zero-4mb.patch` build for normal selectable behavior.

### Build verified

A local ESP-IDF v6.0.2 build of C5VRX `main` with this patch succeeds:

- app `c5vrx5.bin`: **1,255,520 bytes** (`0x132860`), 50% free in the
  2.375 MiB app partition
- merged image: **1,321,056 bytes** (`0x142860`)
- `sdkconfig` and `flasher_args.json` select **4 MB**, DIO, 80 MHz

The built test files are in [`build-zero-4mb/`](build-zero-4mb/) with
[build notes](build-zero-4mb/BUILD_NOTES.md). The image was **flashed and
booted** on a Zero; the boot log reports:

```text
SAMPLE_CLOCK enabled=0 gpio=-1 hz=0 dac_bit2_gpio=11
C5VRX5 4mb-zero-test ready: A1 5865 MHz, D32-R2, ultrafine IQ, gain LEVEL
```

D10 is still off in this layout-only build; enable it and move bit 2 to
GPIO7 before using the tap. The forced-D10 build below uses **GPIO6**
instead, because GPIO7 is a boot strapping pin.

**Zero USB console:** the native USB-Serial/JTAG CDC needs **DTR asserted**.
The C5VRX `tools/flash.py` opens with DTR/RTS low (XIAO convention) and makes
the Zero look silent. Use a normal terminal at 115200 with DTR high, or a
script with `DTR=True, RTS=False`. Enter ROM with BOOT/RESET and use
`esptool --before no-reset --after watchdog-reset`; avoid the RTS hard
reset.

### Pin mapping

No pin-remap patch is needed on the Zero. It exposes the stock C5VRX DAC
pins (GPIO23, 24, 11, 12, 8, 9) and GPIO10, and its USB is the ESP32-C5
native USB on GPIO13/14, not a UART bridge. GPIO11/12 are UART0 but are free
when the console uses the native USB.

The stock D10 mode uses **GPIO7** for bit 2. On the Zero with the tap
connected, GPIO7's boot-strap load blocked boot; the forced-D10 build below
uses **GPIO6** instead. Stock map: bit0=GPIO23, bit1=GPIO24, bit2=GPIO7
(forced build: GPIO6), bit3=GPIO12, bit4=GPIO8, bit5=GPIO9, clock=GPIO10.

### Caveats

- The 4 MB layout was built, flashed and **booted** on a Zero. D10, the
  40 MHz clock, the six data lanes and the menu raster are confirmed; a live
  camera/VTX picture is still to be tested. The Zero USB console needs DTR
  asserted; `tools/flash.py`'s DTR/RTS-low monitor looks silent.
- The app partition has ~1.18 MiB of headroom over the 1.2 MiB release image.
  If a future C5VRX build grows past 2.375 MiB, increase the app partition
  and shrink the flight log, or use a board with 8 MB flash.
- The Zero uses GPIO26 for the antenna switch and GPIO27 for the WS2812;
  do not reuse them. The C5VRX internal IQ loopback on GPIO27 may make the
  RGB LED glow or flicker; that is harmless for the digital tap. GPIO2 is
  also part of that internal IQ loopback; leave it unconnected.
- GPIO7 is a boot-strapping pin. The forced-D10 build avoids it by using
  GPIO6 for bit 2; leave GPIO7 unconnected.
- C5VRX is experimental. Read its safety warning before flight use.
