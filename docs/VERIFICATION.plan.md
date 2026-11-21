# Verification plan: C5VRX FPGA tap on the ESP32-C5-Zero

- **Mode:** quick
- **Decision / use:** confirm the C5VRX firmware/hardware integration for
  the actual receiver board (Waveshare ESP32-C5-Zero, no headers) and verify
  the required modifications before wiring the Tang Nano.

## Key questions

1. Which C5VRX "FPGA" mode should the Tang Nano use?
2. What is the exact bus format (clock, rate, bit order, levels, edges)?
3. Does the Zero expose the stock C5VRX DAC pins, and are any occupied?
4. What firmware/build change is required on a 4 MB Zero?
5. Are the chosen Tang Nano pins suitable and toolchain-compatible?
6. What remains unverified?

## Angles

- **Receiver firmware:** README, `main/transport.c`, research ledger,
  `hardware_experiments/fpga_iq/hwx.h`.
- **Bench evidence:** C5VRX issue #256, especially LAP87's measurements.
- **Receiver board:** Waveshare ESP32-C5-Zero pinout, FAQ, schematic,
  native USB vs UART0, occupied GPIO26/27, 4 MB flash.
- **Build fit:** C5VRX `sdkconfig.defaults`, `partitions.csv`, release app
  size, partition arithmetic for 4 MB.
- **FPGA board:** Tang Nano 9K J6/J7 header, pin functions, clock capability.
- **Local implementation:** simulation of NTSC and PAL, synthesis/place and
  route, resource/timing report.

## Source priorities

Primary: C5VRX repository files and issue measurements; Waveshare Zero
documentation/FAQ/schematic; LiteX/Sipeed Tang Nano pin data. Secondary:
vendor product pages. Local artifacts are treated as primary evidence for
build and simulation claims only.

## Out of scope

RF performance, analog DAC calibration, colour decoding, audio, flight
safety, and a physical board test.

## Verification plan

- Re-open every cited URL and check the quoted claim against the source.
- Cross-check the bus numbers against the firmware source and the bench
  comment.
- Cross-check the Zero pinout against the FAQ and schematic; note the
  WS2812 GP29/GPIO27 discrepancy.
- Check the stock partition table against the Zero's 4 MB flash and the
  release app size.
- Flag single-source claims (D3 timing, 4 MB patch, vertical offsets).
- Run the NTSC and PAL simulations and inspect the dumped frames.
- Run Yosys/nextpnr/gowin_pack and record resource use, timing and errors.

## Result

Report: [`VERIFICATION.md`](VERIFICATION.md)
Provenance: [`VERIFICATION.provenance.md`](VERIFICATION.provenance.md)
