# Counter example

The original Tang Nano 9K LED blinker that occupied this folder before the
HDMI receiver design. Kept for reference.

- `counter.v` — 27 MHz clock, six LEDs counting once every 0.5 s.
- `counter.cst`, `counter.lushay.json` — standalone Lushay project.
- `counter_prebuilt.fs`, `counter_ref.fs` — historical bitstreams.

Open `counter.lushay.json` in Lushay Code, or build with the same Yosys /
nextpnr flow as the main project.
