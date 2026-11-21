#!/usr/bin/env bash
# Simulate the capture -> line buffer -> video output chain.
#
# Usage: ./run.sh [ntsc|pal] [--keep]
#
# The PAL run takes a few minutes because the receiver must detect the
# standard and lock before the frame is dumped.
set -euo pipefail

STD="${1:-ntsc}"
KEEP=0
if [ "${2:-}" = "--keep" ]; then KEEP=1; fi

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

OSS="${OSS_CAD_SUITE:-/home/aukusti/oss-cad-suite-linux-x64-20261018/oss-cad-suite}"
if [ ! -x "$OSS/bin/iverilog" ]; then
    echo "error: OSS-CAD-Suite not found at $OSS" >&2
    echo "       set OSS_CAD_SUITE=/path/to/oss-cad-suite" >&2
    exit 1
fi

case "$STD" in
    ntsc) N=668546;  PIX=345600; ARM=25000000 ;;
    pal)  N=798720;  PIX=414720; ARM=85000000 ;;
    *) echo "usage: $0 [ntsc|pal] [--keep]" >&2; exit 2 ;;
esac

echo "==> generating $STD stimulus"
python3 gen_cvbs.py --std "$STD" --out "$STD.hex"

echo "==> compiling"
"$OSS/bin/iverilog" -g2012 -o tb_core.vvp tb_core.v \
    ../rtl/cvbs_capture.v ../rtl/line_buffer.v ../rtl/video_out.v

echo "==> running ($STD)"
"$OSS/bin/vvp" tb_core.vvp \
    +STIM="$STD.hex" +N="$N" +ARM_NS="$ARM" +PIX="$PIX"

python3 raw_to_png.py frame.raw "frame_$STD.png" "$STD"

if [ "$KEEP" -eq 0 ]; then
    rm -f "$STD.hex" tb_core.vvp frame.raw
fi
