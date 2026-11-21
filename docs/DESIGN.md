# Design notes

## Block diagram

```
 C5VRX D10 tap                    Tang Nano 9K
 ┌──────────────┐   6-bit CVBS   ┌────────────────────────────────────────┐
 │ ESP32-C5     │   40 MHz clk   │ cvbs_capture (40 MHz / 20 MS/s)        │
 │ PARLIO TX    ├───────────────►│  sample, decimate, sync slicer,        │
 │ 6-bit + clk  │                │  back-porch clamp, luma filter         │
 └──────────────┘                │            │ 2x1024x8 ping-pong        │
                                 │            ▼                           │
                                 │ line_buffer (dual-clock BSRAM)         │
                                 │            │                           │
                                 │            ▼                           │
                                 │ video_out (27 MHz)                     │
                                 │  CEA-861 timing, genlock, resample     │
                                 │            │                           │
                                 │            ▼                           │
                                 │ svo_tmds x3 → OSER10 → ELVDS_OBUF      │
                                 └────────────────────────────────────────┘
                                                  → HDMI connector
```

## Clocks and reset

| Clock | Source | Use |
| --- | --- | --- |
| 27 MHz | board oscillator, pin 52 | pixel clock, HDMI timing, line-buffer read |
| 135 MHz | `Gowin_rPLL` from 27 MHz | `OSER10` 5x serial clock |
| 40 MHz | C5VRX D10, pin 35, through `BUFG` | capture, line-buffer write |

Both input pins are 3.3 V. The 40 MHz path is a separate clock domain; the
line buffer is the only crossing, apart from synchronisers for
`line_toggle`, `last_bank`, `vsync_toggle`, `std_pal` and `locked`.

`Reset_Sync` releases the 27 MHz logic only after the PLL locks. The capture
domain has its own four-bit reset synchroniser inside `cvbs_capture`; if the
receiver is off, that domain simply stays quiet.

## Capture and decimation

The ESP32 outputs one 20 MS/s code as two identical 40 MHz samples (the
bench report calls this `[D,D]`). `phase` toggles every 40 MHz cycle and
`ce` is high on every second cycle, so all downstream logic processes one
sample per code. The input flop is the first register after the pin.

The receiver's levels move with its AFC setting. Measured examples were
sync tip 13..24, blanking 24..32 and white 48..62. The slicer therefore
tracks the minimum code with a leaky integrator:

- attack immediately to a lower sample,
- decay upward by one code about every 51 µs,
- declare "no signal" when the tracked tip is above code 48,
- use hysteresis at `min+3` / `min+6` to avoid chattering.

A normal horizontal sync is 70..140 samples wide at 20 MS/s. Equalising
pulses (about 46 samples) are ignored. A broad vertical pulse is recognised
when the low period reaches 250 samples (12.5 µs). Because NTSC and PAL send
several broad pulses in a row, a 5 ms hold-off keeps one vertical event per
field.

Line lock needs 32 consecutive hsync pulses. A 1 ms gap without a valid
hsync drops lock; this is longer than the vertical blanking gap and shorter
than a visible stall. While unlocked the output shows colour bars.

NTSC/PAL detection measures the field period in 20 MS/s samples:

- NTSC field ≈ 333,600 samples (16.68 ms)
- PAL field ≈ 400,000 samples (20.0 ms)
- threshold 366,000 samples, debounced over three fields

## Luma

The back-porch level is sampled at 8.2 µs after the start of horizontal
sync, after the colour burst and before active video for both standards. It
is subtracted from the filtered composite.

A 7-tap binomial FIR `(1, 6, 15, 20, 15, 6, 1) / 64` suppresses the colour
subcarrier. At 20 MS/s it gives about −9 dB at 3.58 MHz and −14 dB at
4.43 MHz, at the cost of some luma bandwidth. The result is scaled by 8 and
saturated to 255, so a 32-code white-to-blank range maps to full scale. The
filter is built from shifts and adds; no multipliers are used.

The filter has a group delay of three samples, so the first few pixels of a
line can contain a small transient from the back porch. In practice this is
at the left edge of the overscanned picture.

## Line buffer

Each captured line writes 1024 samples. The active window is a 1024-sample
crop of the full active line:

| Standard | Active start | Active width | Capture start | Capture width |
| --- | ---: | ---: | ---: | ---: |
| NTSC | 188 samples (9.4 µs) | 1052 | 198 | 1024 |
| PAL | 208 samples (10.4 µs) | 1040 | 214 | 1024 |

The buffer is one 2048x8 dual-port BSRAM (`DPX9B` after synthesis), split
into two 1024-sample banks. The capture side alternates banks at the end of
each window and publishes `last_bank` plus `line_toggle`. The read side
consumes the completed bank twice, once for each output line of the pair.

## HDMI timing and genlock

The output is a CEA-861 frame at 27.000 MHz:

| | NTSC 480p60 | PAL 576p50 |
| --- | ---: | ---: |
| H total | 858 | 864 |
| H sync / back porch / active / front | 62 / 60 / 720 / 16 | 63 / 69 / 720 / 12 |
| V total | 525 | 625 |
| V sync / back porch / active / front | 6 / 30 / 480 / 9 | 5 / 39 / 576 / 5 |

At each receiver vertical sync, the output vertical counter is reloaded at
the next line boundary to `V_TOTAL − 2` (NTSC) or `V_TOTAL − 1` (PAL), i.e.
`523` and `624`. From there the output takes 38 (NTSC) or 45 (PAL) lines to
reach active video. Those numbers were chosen in simulation so that the
first active input line is the first line the reader consumes; they are
localparams and can be nudged on a real receiver if the camera's vertical
blanking differs.

The read side consumes one completed line per **output line pair**:

- At `x == 0` of an even active line, if a new `line_toggle` is present, the
  `last_bank` is latched and `line_valid` is set.
- The same bank is read again for the odd line of the pair.
- If no new line is available (input slightly slower), the previous bank is
  repeated; if the receiver is unlocked, the read sequence does not advance.
- The 27 MHz horizontal counters free-run, so the HDMI timing stays standard
  even if a line is repeated or the receiver restarts.

Horizontal resampling uses an 18-bit accumulator with step `364/256`
(1024 → 720 pixels). The read address is `acc[17:8]`, and the pixel data is
aligned with one-cycle-delayed `x`/`y` counters before the TMDS encoder.

## Test pattern

When `locked` is low, the output shows eight 75 % colour bars with a white
border. This proves the whole HDMI path (PLL, TMDS serialiser, connector,
monitor) before a receiver is connected. It also makes a missing clock or
miswired bus obvious: bars mean the FPGA and HDMI are alive, not that the
receiver is being decoded.

## Synthesis and timing

Latest build with OSS-CAD-Suite (Yosys 0.70, nextpnr-himbaechel 0.11.1):

| Resource | Used | Available |
| --- | ---: | ---: |
| LUT4 | 1379 | 8640 |
| ALU | 738 | 6480 |
| DFF | 381 | 6480 |
| BSRAM | 1 | 26 |
| BUFG | 1 | 22 |
| rPLL | 1 | 2 |

nextpnr reports 47.17 MHz for the capture clock (`cvbs_clk_g`) and 32.98 MHz
for the 27 MHz read clock, both above their actual rates. The build has no
placement or routing errors.

## Future work

1. **Colour.** The tap preserves the original burst. Add a subcarrier PLL
   locked to the burst, quadrature demodulation, a PAL switch, and a
   YUV→RGB matrix. The 6-bit samples and the 20 MS/s rate are the limiting
   factors; expect visibly noisier colour than the luma.
2. **Vertical detail.** A small frame buffer (external PSRAM or a larger
   FPGA) would avoid line doubling and the field-boundary crop.
3. **Standard-specific filters.** A notch at 3.58 or 4.43 MHz instead of one
   binomial filter would preserve more luma detail.
4. **On-screen diagnostics.** The unused LED/button could switch between
   live video, bars, and a sync/level status screen.
