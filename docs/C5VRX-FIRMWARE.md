# C5VRX firmware side

The FPGA design uses C5VRX's **Clock Pin D10** digital capture option. This
page records what the receiver must do, what the stock firmware provides, and
the one build change needed for the **Waveshare ESP32-C5-Zero (no headers)**.

## What the stock firmware already provides

C5VRX-5 (v5.0.573 and later) includes the option in the normal packaged
firmware; no custom FPGA-tap build is needed ([C5VRX README, "Optional
digital video capture: Clock Pin D10"](https://github.com/Twotoz/C5VRX#optional-digital-video-capture-clock-pin-d10)).

1. In the receiver menu open **EXPERIMENTAL → Clock Pin D10** and set it
   **ON**. It takes effect at the next boot.
2. Power off and move the 2 kΩ **bit-2** branch (or the direct tap wire)
   from **GPIO11** to **GPIO7**.
3. Reboot. GPIO10 now carries the 40 MHz PARLIO TX clock, and the bus bit
   order low to high is:

   `GPIO23, GPIO24, GPIO7, GPIO12, GPIO8, GPIO9`

   (C5VRX labels these D4, D5, D3, D7, D8, D9). GPIO11 is no longer driven
   by the video path.
4. Console `T` reports `SAMPLE_CLOCK` with the active/requested state, pin,
   rate and the DAC-bit-2 pin.

This is the **stock** D10 mode. On the Zero with the FPGA tap connected,
GPIO7's boot-strap load blocked boot; the forced-D10 build below moves bit 2
to **GPIO6** and leaves GPIO7 unconnected.

Confirmed bus behaviour from the bench report in
[C5VRX issue #256](https://github.com/Twotoz/C5VRX/issues/256#issuecomment-6530295384):

- 40.0 MHz clock, data changes on the falling edge, capture on the rising
  edge.
- Two identical samples per 20 MS/s code (`[D,D]`).
- NTSC line 2,530–2,544 samples at 40 MHz; hsync 182–190 samples;
  equalising pulses every 1,272 samples in the vertical interval.
- Levels at 1.0x output varied between boots: sync tip 13–24, blanking
  24–32, white 48–62. The FPGA slicer tracks the tip.
- A Tang Nano 20K with this bus locked and displayed luma on HDMI; colour
  was not attempted.

## Why not the `FPGA_IQ` hardware experiment?

The repository also has `hardware_experiments/fpga_iq/hwx.h`, a custom build
(`-DC5VRX_HWX=fpga_iq`) that sends raw MODEM_DIAG Q4/I4 bits on eight pins
and **no clock**. That route requires the FPGA to do WBFM demodulation,
sync recovery and colour decoding, and the experiment's own notes say it has
had no board or FPGA check. This project uses the six-bit composite tap
instead.

## Waveshare ESP32-C5-Zero

The Zero is a small ESP32-C5-HF4 board with **4 MB flash**, **no PSRAM**,
native USB on GPIO13/14, and castellated pads instead of headers. The
official pinout breaks out:

- left side: 5V, GND, 3V3, GPIO0–GPIO5
- right side: GPIO11, GPIO12, GPIO13, GPIO14, GPIO10, GPIO9, GPIO8, GPIO7,
  GPIO6
- bottom: GPIO23, GPIO24, GPIO25, GPIO28

Occupied on the board: **GPIO26** (antenna switch) and **GPIO27** (WS2812
RGB LED) [Zero docs] [Zero FAQ]. GPIO13/14 are USB-JTAG. GPIO11/12 are
UART0 TX/RX but are **not** connected to a USB-UART bridge on the Zero, so
they are free when the console uses the native USB.

### Pin map: D10 build, bit 2 on GPIO6

The stock C5VRX DAC pins are all exposed. The stock D10 mode uses GPIO7 for
bit 2, but on the Zero with the FPGA tap connected, GPIO7's boot-strap load
prevented the firmware from booting (confirmed on hardware). The forced-D10
build therefore uses **GPIO6** for bit 2 and leaves GPIO7 unconnected.

| DAC bit | C5VRX name | Zero GPIO | Zero pad side | Tang Nano pin |
| --- | --- | ---: | --- | --- |
| bit 0 (LSB) | D4 | 23 | bottom | 25 |
| bit 1 | D5 | 24 | bottom | 26 |
| bit 2 | D3 (custom D10) | 6 | right | 27 |
| bit 3 | D7 | 12 | right | 28 |
| bit 4 | D8 | 8 | right | 29 |
| bit 5 (MSB) | D9 | 9 | right | 30 |
| clock | D10 | 10 | right | 35 |
| ground | — | GND | left | GND |

GPIO23/24 are on the bottom edge of the board, so the wire bundle goes to
two sides. Solder to the castellated pads; the "without headers" version has
no 2.54 mm pins. Keep the seven signal wires short and add a dedicated
ground wire.

### The real modification: 4 MB flash

C5VRX's stock build assumes **8 MB**:

- `sdkconfig.defaults` sets `CONFIG_ESPTOOLPY_FLASHSIZE_8MB`.
- `partitions.csv` uses a 3 MiB app and a 1.5 MiB flight log, ending at
  `0x490000` (4.56 MiB).

The Zero has 4 MiB. The released `c5vrx5.bin` app is about 1.2 MiB, so this
project provides a patch that keeps the 1.5 MiB flight log and sets the app
partition to 2.375 MiB:

| Partition | Stock 8 MB | Zero 4 MB |
| --- | ---: | ---: |
| factory app | 3 MiB | 2.375 MiB |
| flightlog | 1.5 MiB | 1.5 MiB |
| end offset | `0x490000` | `0x3F0000` |

The unified diff is
[`../firmware/esp32-c5-zero-4mb.patch`](../firmware/esp32-c5-zero-4mb.patch).

Apply and build:

```sh
git clone https://github.com/Twotoz/C5VRX.git
cd C5VRX
git apply /path/to/esp32-c5-zero-4mb.patch
rm -f sdkconfig
IDF_TARGET=esp32c5 idf.py build
```

For the Zero, flash through the ROM loader. Hold BOOT, tap RESET, release
BOOT, then:

```sh
esptool --chip esp32c5 -p PORT --before no-reset --after watchdog-reset \
  write-flash --erase-all --flash-mode dio --flash-freq 80m --flash-size 4MB \
  0x2000 bootloader/bootloader.bin \
  0x8000 partition_table/partition-table.bin \
  0x10000 c5vrx5.bin
```

Do not use the RTS hard reset on the Zero; it hangs the native USB-JTAG.
C5VRX's `tools/flash.py` is XIAO-oriented and opens the console with DTR/RTS
low; the Zero console needs **DTR asserted**.

Use ESP-IDF **6.0.2**. Do not use the stock prebuilt 8 MB image on the Zero,
and do not use the PSRAM build (`sdkconfig.psram.defaults`); the Zero has no
PSRAM. The standard image runs without PSRAM.

### Forced-D10 build (no menu/web access)

The C5VRX web flasher has no control for **EXPERIMENTAL → Clock Pin D10**,
and the receiver menu is only visible on the AV/video output. For the FPGA
tap, a local build can force it:

- patch: [`../firmware/esp32-c5-zero-4mb-d10.patch`](../firmware/esp32-c5-zero-4mb-d10.patch)
- image: [`../firmware/build-zero-4mb-d10/`](../firmware/build-zero-4mb-d10/)
- app: 1,255,536 bytes (`0x132870`), 50% free
- boot: GPIO10 = 40 MHz clock, bit 2 = **GPIO6**
- `T`: `SAMPLE_CLOCK enabled=1 gpio=10 hz=40000000 dac_bit2_gpio=7`
  (the `7` is an upstream hardcoded print; the actual D10 setup in this
  build is GPIO6)

The patch sets `s_exp.value[EXP_CLOCK_D10] = 1` before the active D10 flag
is read, forces D10 on, and changes the D10 bit-2 pin from GPIO7 to GPIO6.
GPIO7 is left disconnected. Use the layout-only patch if you want the normal
menu-selectable behavior (with stock GPIO7, which needs a strap check).

### Build result

The 4 MB layout was built locally with ESP-IDF v6.0.2, target `esp32c5`:

- app `c5vrx5.bin`: **1,255,520 bytes** (`0x132860`), 50% free in the
  2.375 MiB app partition
- merged image: **1,321,056 bytes** (`0x142860`)
- `sdkconfig` and `flasher_args.json` select **4 MB**, DIO, 80 MHz
- built test files: [`../firmware/build-zero-4mb/`](../firmware/build-zero-4mb/)

It has been flashed to a Zero (ESP32-C5HF4, 4 MB, USB-Serial/JTAG) with the
bootloader, partition table and app all hash-verified, and it **boots**. The
Tang Nano locks to the C5VRX NTSC menu raster over the D10/GPIO6 tap and
shows the menu on HDMI; no camera/VTX was connected for a live picture.

```text
SAMPLE_CLOCK enabled=0 gpio=-1 hz=0 dac_bit2_gpio=11
C5VRX5 4mb-zero-test ready: A1 5865 MHz, D32-R2, ultrafine IQ, gain LEVEL
STATUS channel=A1 freq=5865 ... fw=4mb-zero-test+local-test
```

D10 is still off (`SAMPLE_CLOCK enabled=0`). The first flash attempt used
esptool's RTS hard reset, which hung the native USB-JTAG; recovery was
BOOT/RESET into ROM, a clean erase/reflash with
`--before no-reset --after watchdog-reset`, and a console opened with DTR
asserted.

### Zero USB console

The native USB-Serial/JTAG CDC needs **DTR asserted**. C5VRX's
`tools/flash.py` opens with DTR/RTS low (XIAO convention) and makes the Zero
look silent. Use a normal terminal at 115200 with DTR high, or a script with
`DTR=True, RTS=False`. To flash, enter ROM with BOOT/RESET and use esptool
with `--before no-reset --after watchdog-reset`; avoid the RTS hard reset.

### Firmware caveats

- The 4 MB layout builds, flashes and boots. D10, the 40 MHz clock, all six
  lanes and the FPGA tap still need a bench check. The Zero USB console
  needs DTR asserted; `tools/flash.py`'s DTR/RTS-low monitor looks silent.
- The app partition has about 1.18 MiB of headroom. If a future C5VRX build
  grows past 2.375 MiB, resize the partitions or use an 8 MB board.
- The C5VRX firmware uses GPIO27 and GPIO2 internally for its IQ loopback.
  On the Zero, GPIO27 is the WS2812 data line; the RGB LED may glow or
  flicker during reception. This is cosmetic and does not affect the tap.
  GPIO2 is exposed on the Zero; leave it unconnected. GPIO26 is the antenna
  switch; C5VRX does not drive it, so check the board's antenna-selection
  default if you use the IPEX connector.
- GPIO11/12 are UART0. They are free for the DAC tap when the console uses
  the native USB, but a serial adapter connected to those pads would
  contend with bit 3 (GPIO12), and with GPIO11 if Clock Pin D10 is off
  (the default bit-2 pin).
- GPIO7 is a boot-strapping pin on the ESP32-C5. Stock C5VRX D10 uses it
  for bit 2; with the FPGA tap connected, its load blocked boot on the Zero.
  The forced-D10 build uses GPIO6 instead; leave GPIO7 unconnected.
- C5VRX is experimental. Read its safety warning before flight use.

### Confidence

- **High:** the D10 option, 40 MHz / 20 MS/s / `[D,D]` bus, bit order and
  "capture on rising edge" are documented by C5VRX and measured in issue
  #256.
- **High:** the Zero pinout/occupancy (official pinout, schematic and FAQ).
- **High:** the 4 MB partition arithmetic (stock partitions end at
  `0x490000`; the release app is ~1.2 MiB), the local ESP-IDF v6.0.2 build
  (app `0x132860`, 50% free), the flash write (all hashes verified), and the
  boot/status log.
- **Medium:** D10/FPGA capture on the Zero, which is still to be checked.

## First bench checklist

1. Apply the 4 MB patch, build, flash, and confirm the receiver boots and
   shows the normal C5VRX menu/status on its own output (or console). After
   a clean flash, run **CALIBRATE** with the VTX off; the erased NVS reports
   `NOT_CALIBRATED` until then.
2. Set **EXPERIMENTAL → Clock Pin D10 = ON** (or use the forced build).
   The forced build uses bit 2 on GPIO6; move the wire there, not GPIO7.
3. With the VTX off, measure the 40 MHz clock on GPIO10 and confirm the six
   data pads are driven.
4. Solder the seven signals and a ground to the Tang Nano. Power the Tang
   Nano from its own USB-C before the Zero drives the bus; do not bridge 5 V
   or 3.3 V between the boards. The Zero's USB is the native ESP32-C5 USB on
   GPIO13/14, so it remains available for the console/flasher.
5. Expect colour bars until the FPGA locks, then the camera picture in luma.
   Check LED1 (lock) and LED2 (PAL).
6. If the picture rolls, verify the detected standard and the vertical
   offset localparams in `rtl/video_out.v`.
7. Switch **Clock Pin D10 = OFF** and move bit 2 back before using the
   analog goggle output again.

[Zero docs]: https://docs.waveshare.com/ESP32-C5-Zero
[Zero FAQ]: https://docs.waveshare.com/ESP32-C5-Zero/FAQ
