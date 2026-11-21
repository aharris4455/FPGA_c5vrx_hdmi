#!/usr/bin/env python3
"""Convert a raw 8-bit luma frame from tb_core.v to a PNG."""

import sys

from PIL import Image

raw_path = sys.argv[1] if len(sys.argv) > 1 else "frame.raw"
png_path = sys.argv[2] if len(sys.argv) > 2 else "frame.png"
std = sys.argv[3].lower() if len(sys.argv) > 3 else "ntsc"

w, h = (720, 576) if std == "pal" else (720, 480)
data = open(raw_path, "rb").read()
if len(data) < w * h:
    raise SystemExit(f"{raw_path}: {len(data)} bytes, expected {w * h}")

Image.frombytes("L", (w, h), data[: w * h]).save(png_path)
print(f"{png_path}: {w}x{h}")
