# Verification: C5VRX FPGA tap on the Waveshare ESP32-C5-Zero

**Bottom line**

- The target receiver is the **Waveshare ESP32-C5-Zero (no headers)**. It
  exposes the stock C5VRX DAC pins (GPIO23, 24, 11, 12, 8, 9) and GPIO10,
  and its USB is the ESP32-C5 native USB on GPIO13/14. **No pin-remap patch
  is needed**; GPIO11/12 are free UART0 pads when the console uses native
  USB [6][7][8][9]. **Confidence: high.**
- The FPGA tap is C5VRX's normal-firmware **Clock Pin D10** option: 6-bit
  composite video plus a 40 MHz clock, 20 MS/s unique codes, bit order
  GPIO23/24/7/12/8/9 [1][2]. This is the route implemented here.
  **Confidence: high.**
- The real firmware modification is flash size: the Zero has **4 MB**, while
  C5VRX's stock build assumes 8 MB (`0x490000` = 4.56 MiB of partitions)
  [6][10]. The provided patch keeps the 1.5 MiB flight log, sets the app
  partition to 2.375 MiB, and ends the layout at `0x3F0000`. A local ESP-IDF
  v6.0.2 build succeeds: app `0x132860` (1,255,520 bytes), 50% free;
  merged image 1,321,056 bytes. The image was flashed to the Zero with all
  region hashes verified and **boots**. A forced-D10 build then booted with
  `SAMPLE_CLOCK enabled=1 gpio=10`. On hardware, the stock D10 bit-2 pin
  GPIO7 was loaded by the FPGA tap and blocked boot; disconnecting it
  restored boot, so the forced build uses GPIO6 instead. **Confidence: high
  for the build/flash/boot and the GPIO7 strap finding; medium for the live
  composite picture.**
- The Tang Nano 9K inputs (pins 25–30 and 35, bank 2, 3.3 V) are suitable,
  the design builds, and simulation locks on NTSC and PAL and produces full
  720x480 / 720x576 frames [12][14]. The HDMI test pattern has been observed
  on hardware through a USB capture card (OBS), confirming the PLL/TMDS/
  connector path. The D10 tap then locked to the C5VRX menu raster and
  displayed it over HDMI; no camera/VTX was connected, so the live camera
  picture is the remaining test. **Confidence: high for build/simulation,
  HDMI output and the menu-raster tap; medium for live camera luma.**

## Scope and method

**Decision / use:** confirm the C5VRX firmware/hardware integration for the
actual receiver board (Waveshare ESP32-C5-Zero, no headers) and verify the
required modifications before wiring the Tang Nano.

**Questions:**

1. Which C5VRX "FPGA" mode should the Tang Nano use?
2. What exactly is on the bus (clock, rate, bit order, levels)?
3. Does the Zero support the stock C5VRX DAC pin map?
4. What firmware/build change is required on a 4 MB Zero?
5. Are the chosen Tang Nano pins suitable and toolchain-compatible?
6. What remains unverified?

**Method:** quick-mode review of C5VRX primary sources (README, firmware
source, partition table/config, research ledger, issue #256 bench report),
the Waveshare Zero documentation/FAQ/schematic, and the Tang Nano 9K pin
data, followed by local simulation and a full synthesis/place-and-route
build.

**Out of scope:** RF performance, analog DAC calibration, colour decoding,
audio, flight safety, and a physical board test.

## Findings

### 1. The D10 tap is the documented external-capture route

C5VRX-5's README describes **EXPERIMENTAL → Clock Pin D10**. When enabled,
GPIO10 exports the 40 MHz PARLIO TX clock and DAC bit 2 moves from
GPIO11 to GPIO7. The README states the bit order low to high is
GPIO23, GPIO24, GPIO7, GPIO12, GPIO8, GPIO9 (labelled D4, D5, D3, D7, D8,
D9); GPIO11 is disconnected from TX; data shifts on falling edges and should
be captured on rising edges; the bus is six-bit composite video with
identical `[D,D]` pairs at TX40 and 20 MS/s unique codes; the colour burst is
preserved [1].

The research ledger records the same option and the operator decision behind
it [3]. The firmware source confirms the default table
`{23, 24, 11, 12, 8, 9, -1, -1}` and the D10 relocation
`clk_out_gpio_num = 10`, `data_gpio_nums[2] = 7` [5].

### 2. Bench numbers support the design assumptions

LAP87's bench report in issue #256 measured on a Tang Nano 20K with the
clock on GPIO2 at the time [2]:

| Property | Measurement |
| --- | --- |
| Clock | 40.0 MHz |
| Capture edge | data changes falling, rising-edge sample works |
| Unique rate | 20 MS/s, samples arrive as `[D,D]` |
| NTSC line | 2,530–2,544 samples at 40 MHz (63.25–63.6 µs) |
| H sync | 182–190 samples (4.55–4.75 µs) |
| Vertical equalising | every 1,272 samples (31.8 µs, half-line) |
| Levels | sync tip 13–24, blanking 24–32, white 48–62 (6-bit) |
| Result | luma locks on HDMI; colour not attempted |

These numbers drive the FPGA thresholds: 20 MS/s decimation, 70–140-sample
hsync validation, broad-pulse detection at 250 samples (12.5 µs), and a
leaky minimum tracker rather than a fixed sync threshold. The report is a
single bench source, but it is a first-party measurement with raw counts and
is consistent with the README.

A later note in the same issue says the GPIO11 bit-2 25 ns rising-edge delay
was the motivation for moving bit 2 to GPIO7, and that a timing fix on
GPIO7 was **not yet verified** [1][2]. The Zero exposes GPIO7, so this is
still a bench item. **Confidence: medium.**

### 3. `FPGA_IQ` is a different, much larger route

`hardware_experiments/fpga_iq/hwx.h` describes a custom build
(`-DC5VRX_HWX=fpga_iq`) that sends raw MODEM_DIAG Q4/I4 bits on eight GPIOs
with **no clock output** and no DAC. The FPGA owns demodulation. The file
also says the receiver keeps running on its RX40/raw32K loopback and that
the menu raster can be placed on the IQ pads [4]. The ledger says this
experiment had "firmware build only; no board or FPGA check yet" [3].

Choosing D10 is therefore the lower-risk route: it uses the normal packaged
firmware, an external clock, and a documented six-bit composite stream. The
spec's phrase "experimental fpga mode" is ambiguous, but D10 is the mode
that matches "HDMI support comes from the Tang Nano" without implementing a
WBFM receiver in the FPGA.

### 4. The Zero supports the stock C5VRX pin map

The Zero is an ESP32-C5-HF4 board with **4 MB flash**, **no PSRAM**, native
USB on GPIO13/14, and castellated pads instead of headers [6]. Its exposed
pads are:

- left: 5V, GND, 3V3, GPIO0–GPIO5
- right: GPIO11, GPIO12, GPIO13, GPIO14, GPIO10, GPIO9, GPIO8, GPIO7, GPIO6
- bottom: GPIO23, GPIO24, GPIO25, GPIO28

The Zero FAQ says the onboard GPIOs in use are **GPIO27 and GPIO26** [7].
The schematic shows the WS2812 RGB LED on GPIO27 and the antenna switch
control on GPIO26 [8]. GPIO13/14 are the native USB pair. GPIO11/12 are
UART0 TX/RX but are not connected to a USB-UART bridge on the Zero; the USB
port is the chip's native USB [8][9].

The stock C5VRX DAC pins are GPIO23, 24, 11, 12, 8, 9. All are exposed, and
GPIO10 (the D10 clock) is exposed. Stock D10 uses GPIO7 for bit 2, but on
hardware with the FPGA tap connected, GPIO7's boot-strap load prevented the
app from booting; disconnecting GPIO7 restored boot. The forced-D10 build
therefore moves bit 2 to **GPIO6** (non-strapping, not in C5VRX's IQ pin
set) and leaves GPIO7 unconnected. **Confidence: high** for the pin
availability and the strap finding; the GPIO6 edge timing is still a bench
item.

### 5. The Zero needs a 4 MB flash layout

C5VRX's stock build selects 8 MB and uses:

| Partition | Stock layout |
| --- | ---: |
| `factory` app | 3 MiB at `0x10000` |
| `flightlog` | 1.5 MiB at `0x310000` |
| end | `0x490000` = 4.56 MiB |

The Zero has 4 MiB (`0x400000`) [6]. The v5.0.621 `c5vrx5.bin` app asset is
1,255,568 bytes (~1.2 MiB) [11], so the app itself fits; the stock partition
table does not.

The patch in [`../firmware/esp32-c5-zero-4mb.patch`](../firmware/esp32-c5-zero-4mb.patch)
changes `CONFIG_ESPTOOLPY_FLASHSIZE_4MB=y` and uses:

| Partition | Zero layout |
| --- | ---: |
| `factory` app | 2.375 MiB at `0x10000` |
| `flightlog` | 1.5 MiB at `0x270000` |
| end | `0x3F0000` = 3.94 MiB |

This leaves 64 KiB inside the Zero's 4 MiB flash. The app partition has
about 1.18 MiB of headroom over the release image. The layout was built
locally with ESP-IDF v6.0.2: app `0x132860` (1,255,520 bytes), 50% free;
merged image 1,321,056 bytes; `sdkconfig`/`flasher_args.json` select 4 MB.
It was flashed to the Zero with bootloader/partition/app hashes verified and
booted. The forced-D10 build then booted with `SAMPLE_CLOCK enabled=1
gpio=10`; GPIO7 was found to be a boot-strap problem with the tap connected,
so bit 2 was moved to GPIO6. **Confidence: high** for the arithmetic,
build, flash and boot; **medium** for the live composite/FPGA link.

The Zero's native USB-Serial/JTAG console needs **DTR asserted**. C5VRX's
`tools/flash.py` opens the port with DTR/RTS low (an XIAO convention) and
makes the Zero look silent. esptool's RTS hard reset also hangs the native
USB-JTAG; use BOOT/RESET into ROM and
`--before no-reset --after watchdog-reset`. This is an empirical
Zero-specific behavior observed during this build/flash, not a C5VRX
documentation claim.

### 6. Tang Nano 9K pin choice

The Tang Nano 9K J6 header exposes pins 25–30 contiguously, and pin 35 is
the RGB-LCD clock pin on the same header. LiteX's board definition lists
these as 3.3 V `LVCMOS33` and lists the 27 MHz clock on pin 52, LEDs on
10/11, button on 4, and HDMI on 68–75 [12]. The Sipeed schematic identifies
pin 35 as `IOB29A/GCLKT_4` (global-clock capable) [13].

The design uses pins 25–30 for `cvbs[0..5]` and pin 35 for the 40 MHz clock.
Pin 35 is shared with the LCD FPC connector, so the LCD must be unplugged.
The open-source placer did not automatically promote the 40 MHz input to a
global clock; an explicit `BUFG` removed a small hold violation. The final
build reports 47.17 MHz for the capture clock and 32.98 MHz for the read
clock, above their 40/27 MHz operating points.

## Where the evidence conflicts / uncertainty

- **Zero pinout image vs. schematic.** The public pinout image labels the
  WS2812 pin "GP29", but the schematic and FAQ identify GPIO27 (the C5 has
  GPIO0–GPIO28; GPIO29 is not a valid GPIO). Either way, do not use GPIO27
  or GPIO26 for the tap. We use the schematic/FAQ as the authority.
- **Native USB vs. UART0.** GPIO11/12 are UART0, but the Zero does not have
  a USB-UART bridge; the USB port is the native USB on GPIO13/14. This is
  why the stock DAC map works. A serial adapter on GPIO12 would contend with
  bit 3.
- **4 MB patch.** The layout builds cleanly with ESP-IDF v6.0.2, the
  4 MB app-size check passes, the image flashed with verified hashes, and
  the board boots the test build. D10/FPGA and the flight-log runtime on
  the 1.5 MiB partition still need a board check. The Zero console needs
  DTR asserted, and esptool's RTS hard reset hangs the native USB-JTAG;
  use BOOT/RESET + `--before no-reset --after watchdog-reset`.
- **D3/GPIO7 bit-2 timing.** C5VRX's README says the D3 timing fix is not
  verified; the bench report's skew was on GPIO11. Our design uses one
  sample per pair; it does not implement a majority filter.
- **GPIO7 is a strapping pin — confirmed on hardware.** With stock D10 bit 2
  on GPIO7 and the FPGA tap connected, the Zero did not boot; disconnecting
  GPIO7 restored boot. The forced-D10 build uses GPIO6 and leaves GPIO7
  unconnected. GPIO6 timing through the tap still needs a scope/bench check.
- **Vertical phase.** The output reload constants (`523`/`624`) were chosen
  in simulation against a standard NTSC/PAL generator. A real camera's
  vertical blanking may differ by a few lines; they are localparams and may
  need a small trim.
- **Partial hardware test.** The HDMI test pattern and the C5VRX menu raster
  through the D10/GPIO6 tap are confirmed; the D10-forced firmware boots
  with the clock enabled. A live camera/VTX picture is still to be checked
  (none connected during this test).

## Implications

**Recommendation:** use the forced-D10 4 MB build (or the layout patch plus
the receiver menu), wire bit 2 to **GPIO6**, leave GPIO7 unconnected, and
solder the seven signals plus ground to the castellated pads. The D10 clock
is GPIO10. The menu-raster tap is confirmed; connect a camera/VTX on A1
5865 for the live-picture check.

**What would resolve the open questions:**

1. A build and flash of the 4 MB patch on a real Zero, including a boot log
   and `esp_partition` table check.
2. A scope capture of the D10 tap on the Zero: 40 MHz clock, all six lanes,
   levels, and the GPIO6 bit-2 edge.
3. A real NTSC and PAL camera on the Tang Nano with the current bitstream,
   checking LED1 lock, LED2 PAL, and the top/bottom line alignment.
4. A colour decoder on the captured burst, if colour is required.

## Sources

[1] Twotoz/C5VRX. "C5VRX — ESP32-C5 Analog 5.8 GHz FPV Receiver", README,
    "Optional digital video capture: Clock Pin D10".
    <https://github.com/Twotoz/C5VRX> (raw:
    <https://raw.githubusercontent.com/Twotoz/C5VRX/main/README.md>).
    Accessed 2026-11-19.

[2] LAP87. "Bench results for the sample clock (PR #257) from an FPGA
    capture, and a pin proposal", comment in Twotoz/C5VRX issue #256,
    2026-10-30.
    <https://github.com/Twotoz/C5VRX/issues/256#issuecomment-6530295384>.
    Accessed 2026-11-19.

[3] Twotoz/C5VRX. `docs/RESEARCH_LEDGER.md`, entries "Hardware experiment
    FPGA_IQ" and "D10 sample clock and six-bit DAC".
    <https://github.com/Twotoz/C5VRX/blob/main/docs/RESEARCH_LEDGER.md>.
    Accessed 2026-11-19.

[4] Twotoz/C5VRX. `hardware_experiments/fpga_iq/hwx.h`.
    <https://github.com/Twotoz/C5VRX/blob/main/hardware_experiments/fpga_iq/hwx.h>.
    Accessed 2026-11-19.

[5] Twotoz/C5VRX. `main/transport.c` (DAC GPIO table and D10 relocation).
    <https://github.com/Twotoz/C5VRX/blob/main/main/transport.c>.
    Accessed 2026-11-19.

[6] Waveshare. "ESP32-C5-Zero" documentation (4 MB flash, no PSRAM,
    ESP32-C5-HF4, castellation, USB).
    <https://docs.waveshare.com/ESP32-C5-Zero>. Accessed 2026-11-19.

[7] Waveshare. "ESP32-C5-Zero FAQ" ("Which onboard GPIOs are occupied? A:
    GPIO27 and GPIO26").
    <https://docs.waveshare.com/ESP32-C5-Zero/FAQ>. Accessed 2026-11-19.

[8] Waveshare. `ESP32-C5-Zero` schematic (WS2812 on GPIO27, antenna switch
    on GPIO26, native USB pins).
    <https://github.com/waveshareteam/ESP32-C5-Zero/blob/main/hardware/schematics/ESP32-C5-Zero.pdf>.
    Opened from the official repository; PDF page text extracted locally.

[9] Waveshare. `ESP32-C5-Zero` example repository and pinout.
    <https://github.com/waveshareteam/ESP32-C5-Zero>. Accessed 2026-11-19.

[10] Twotoz/C5VRX. `sdkconfig.defaults` and `partitions.csv` (8 MB flash,
     3 MiB app, 1.5 MiB flightlog).
     <https://github.com/Twotoz/C5VRX/blob/main/sdkconfig.defaults> and
     <https://github.com/Twotoz/C5VRX/blob/main/partitions.csv>.
     Accessed 2026-11-19.

[11] Twotoz/C5VRX. Release `c5vrx5-v5.0.621`, asset `c5vrx5.bin`
     (1,255,568 bytes).
     <https://github.com/Twotoz/C5VRX/releases/tag/c5vrx5-v5.0.621>.
     Accessed 2026-11-19.

[12] LiteX-Boards. `litex_boards/platforms/sipeed_tang_nano_9k.py` (clock,
     LEDs, button, J6/J7 headers, HDMI pins).
     <https://github.com/litex-hub/litex-boards/blob/master/litex_boards/platforms/sipeed_tang_nano_9k.py>.
     Accessed 2026-11-19.

[13] Sipeed. "Tang Nano 9K" schematic (`Tang_Nano_9k_3672_Schematic.pdf`),
     pin 35 `IOB29A/GCLKT_4`.
     <https://dl.sipeed.com/fileList/TANG/Nano%209K/2_Schematic/Tang_Nano_9k_3672_Schematic.pdf>.
     PDF; pin name observed via the published schematic excerpt.

[14] This repository: `sim/frame_ntsc.png`, `sim/frame_pal.png`,
     `sim/tb_core.v`, `rtl/`, `fpga_esp_rx.fs`, and
     `firmware/build-zero-4mb/`. FPGA simulation/build and the C5VRX 4 MB
     firmware build ran on 2026-11-19 with OSS-CAD-Suite Yosys 0.70 /
     nextpnr 0.11.1 and ESP-IDF v6.0.2.
