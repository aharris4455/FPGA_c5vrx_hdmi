# Provenance: C5VRX FPGA tap on the ESP32-C5-Zero

- **Date:** 2026-11-19
- **Mode:** quick
- **Decision / use:** confirm the C5VRX firmware/hardware integration for
  the Waveshare ESP32-C5-Zero (no headers) and verify the modifications
  before wiring the Tang Nano.
- **Key questions:** D10 vs FPGA_IQ; bus format; Zero pin compatibility;
  4 MB flash layout; Tang Nano pins; remaining uncertainty.
- **Sources consulted:** 14 (plus local simulation/build artifacts).
- **Sources accepted:** 12 primary/secondary; 2 PDFs used through their
  published text (Sipeed schematic excerpt, Waveshare schematic extracted
  from the official repository) and flagged in the report.
- **Sources rejected:** none rejected as content farms. The Zero pinout
  image's "GP29" label is contradicted by the schematic/FAQ and is flagged
  rather than used.
- **Verification:** PASS WITH NOTES
  - Re-opened the C5VRX README, issue #256 comment, ledger, `hwx.h`,
    `transport.c`, `sdkconfig.defaults`, `partitions.csv`, release asset
    metadata, Waveshare Zero docs/FAQ/schematic, and the LiteX platform
    file.
  - Checked the quoted bus numbers against the bench comment.
  - Checked the stock partition table end offset (`0x490000`) against the
    Zero's 4 MB flash and the 1.2 MiB release app.
  - Ran the NTSC and PAL simulations; inspected the dumped frames.
  - Ran the full Yosys/nextpnr/gowin_pack build; no errors.
  - Built C5VRX with ESP-IDF v6.0.2 and the 4 MB patch: app `0x132860`,
    50% free; merged image 1,321,056 bytes; 4 MB flasher args.
  - Flashed the bootloader, partition table and app to the Zero on
    `/dev/ttyACM0`; all region hashes verified. esptool's RTS hard reset
    hung the native USB-JTAG; recovery was BOOT/RESET into ROM, a clean
    erase/reflash with `--before no-reset --after watchdog-reset`, a USB
    power cycle, and a console opened with **DTR asserted**.
  - The board boots the test build and prints the C5VRX startup/status log
    (`C5VRX5 4mb-zero-test ready`, `SAMPLE_CLOCK enabled=0`).
  - The FPGA HDMI test pattern was observed on hardware through the USB3
    capture card in OBS, confirming the HDMI output path.
  - The forced-D10 4 MB build booted (`SAMPLE_CLOCK enabled=1 gpio=10`).
    With stock D10 bit 2 on GPIO7, the FPGA tap's load blocked boot;
    disconnecting GPIO7 restored boot. The build was changed to bit 2 on
    GPIO6.
  - The Tang Nano locked to the C5VRX NTSC menu raster and displayed the
    menu over HDMI (observed in OBS). No FPV camera/VTX was connected, so
    live camera luma remains to be tested.
  - FATAL: none.
  - MAJOR: live composite capture and the GPIO6 data timing are not yet
    tested.
  - MINOR: the Zero pinout image labels the WS2812 "GP29" while the
    schematic/FAQ say GPIO27; D3/GPIO7 bit-2 timing is unverified in C5VRX;
    GPIO7's strap load was confirmed on hardware and the build now uses
    GPIO6; vertical phase constants are simulation-derived;
    the Zero native USB console needs DTR high and esptool's RTS reset hangs
    the USB-JTAG.
- **Limitations:** no scope, no HDMI sink test; the 4 MB image is flashed and
  boots, but D10/FPGA and the video link are still to be checked.
- **Plan:** `VERIFICATION.plan.md`
- **Report:** `VERIFICATION.md`
