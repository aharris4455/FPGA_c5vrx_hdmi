#!/usr/bin/env python3
"""Generate a synthetic C5VRX six-bit CVBS stream for simulation.

The C5VRX digital tap presents one 20 MS/s unique sample twice at 40 MHz.
This script writes one hex byte per 40 MHz sample, ready for $readmemh.

Levels follow LAP87's bench report (issue #256): sync tip 20, blanking 30,
white 60 in six-bit codes, with a small colour burst on the back porch.
"""

import argparse
import math

SYNC = 20
BLANK = 30
WHITE = 60

BAR_LUMA = [0.00, 0.12, 0.25, 0.38, 0.50, 0.63, 0.78, 1.00]


def q(v):
    return max(0, min(63, int(round(v))))


def burst(freq_hz, samples_after_sync, period_samples, cycles, amp=5.0):
    """Return {index: level} for a colour burst in the back porch."""
    out = {}
    for n in range(int(period_samples * cycles)):
        idx = samples_after_sync + n
        out[idx] = q(BLANK + amp * math.sin(2.0 * math.pi * freq_hz * n / 20.0e6))
    return out


def make_line(unique_len, sync_spans, active_start, active_width, active_luma,
              burst_freq):
    """Build one 20 MS/s line as a list of six-bit codes."""
    line = [BLANK] * unique_len
    for start, width in sync_spans:
        for i in range(start, min(unique_len, start + width)):
            line[i] = SYNC

    if burst_freq:
        # Burst starts 0.6 us after the end of the normal hsync.
        sync_end = 94
        period = 20.0e6 / burst_freq
        cycles = 9 if burst_freq < 4.0e6 else 10
        for idx, level in burst(burst_freq, sync_end + 12, period, cycles).items():
            if idx < unique_len:
                line[idx] = level

    if active_luma is not None:
        for col in range(active_width):
            if col < 4 or col >= active_width - 4:
                luma = 1.0
            else:
                bar = min(7, col * 8 // active_width)
                luma = BAR_LUMA[bar]
            line[active_start + col] = q(BLANK + luma * (WHITE - BLANK))

    return line


def ntsc_field():
    """263-line NTSC field, 240 active lines starting at line 21."""
    lines = []
    unique_len = 1271          # 63.55 us at 20 MS/s
    active_start = 188         # 9.4 us after sync start
    active_width = 1052        # 52.6 us
    burst_freq = 3.579545e6

    for ln in range(263):
        if ln < 3:
            spans = [(0, 46), (636, 46)]              # pre-equalising
            lines.append(make_line(unique_len, spans, active_start,
                                   active_width, None, None))
        elif ln < 6:
            spans = [(0, 540), (636, 540)]            # vertical broad pulses
            lines.append(make_line(unique_len, spans, active_start,
                                   active_width, None, None))
        elif ln < 9:
            spans = [(0, 46), (636, 46)]              # post-equalising
            lines.append(make_line(unique_len, spans, active_start,
                                   active_width, None, None))
        elif 21 <= ln < 261:
            lines.append(make_line(unique_len, [(0, 94)], active_start,
                                   active_width, True, burst_freq))
        else:
            lines.append(make_line(unique_len, [(0, 94)], active_start,
                                   active_width, None, burst_freq))
    return lines, unique_len


def pal_field():
    """312-line PAL field, 288 active lines starting at line 23."""
    lines = []
    unique_len = 1280          # 64.0 us at 20 MS/s
    active_start = 208         # 10.4 us after sync start
    active_width = 1040        # 52.0 us
    burst_freq = 4.43361875e6

    for ln in range(312):
        if ln < 2:
            spans = [(0, 46), (640, 46)]              # pre-equalising
            lines.append(make_line(unique_len, spans, active_start,
                                   active_width, None, None))
        elif ln < 4:
            spans = [(0, 546), (640, 546)]            # vertical broad pulses
            lines.append(make_line(unique_len, spans, active_start,
                                   active_width, None, None))
        elif ln < 6:
            spans = [(0, 46), (640, 46)]              # post-equalising
            lines.append(make_line(unique_len, spans, active_start,
                                   active_width, None, None))
        elif 23 <= ln < 311:
            lines.append(make_line(unique_len, [(0, 94)], active_start,
                                   active_width, True, burst_freq))
        else:
            lines.append(make_line(unique_len, [(0, 94)], active_start,
                                   active_width, None, burst_freq))
    return lines, unique_len


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--std", choices=["ntsc", "pal"], default="ntsc")
    ap.add_argument("--out", required=True)
    ap.add_argument("--fields", type=int, default=1)
    ap.add_argument("--pad-to", type=int, default=1000000,
                    help="pad the hex file to this many samples (tb_core memory size)")
    args = ap.parse_args()

    if args.std == "ntsc":
        lines, unique_len = ntsc_field()
    else:
        lines, unique_len = pal_field()

    # Repeat each 20 MS/s code twice for the 40 MHz bus.
    written = 0
    with open(args.out, "w") as f:
        for _ in range(args.fields):
            for line in lines:
                for sample in line:
                    f.write(f"{sample:02x}\n")
                    f.write(f"{sample:02x}\n")
                    written += 2
        while written < args.pad_to:
            f.write("00\n")
            written += 1

    total = args.fields * len(lines) * unique_len * 2
    print(f"{args.std}: {len(lines)} lines/field, {unique_len} unique samples/line, "
          f"{total} used samples, {written} written -> {args.out}")


if __name__ == "__main__":
    main()
