#!/usr/bin/env bash
# Build the Tang Nano 9K bitstream with the open-source Gowin flow.
#
# Override the toolchain location with OSS_CAD_SUITE=/path/to/oss-cad-suite.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OSS="${OSS_CAD_SUITE:-/home/aukusti/oss-cad-suite-linux-x64-20261018/oss-cad-suite}"
if [ ! -x "$OSS/bin/yosys" ]; then
    echo "error: OSS-CAD-Suite not found at $OSS" >&2
    echo "       set OSS_CAD_SUITE=/path/to/oss-cad-suite" >&2
    exit 1
fi

FILES="rtl/top.v rtl/cvbs_capture.v rtl/line_buffer.v rtl/video_out.v rtl/svo_tmds.v rtl/gowin_rpll.v"

echo "==> yosys (synth_gowin)"
"$OSS/bin/yosys" -p "read_verilog $FILES; synth_gowin -top top -json fpga_esp_rx.json"

echo "==> nextpnr-himbaechel"
"$OSS/bin/nextpnr-himbaechel" \
    --json fpga_esp_rx.json \
    --write fpga_esp_rx_pnr.json \
    --freq 27 \
    --device GW1NR-LV9QN88PC6/I5 \
    --vopt family=GW1N-9C \
    --vopt cst=tangnano9k.cst \
    --chipdb "$OSS/share/nextpnr/himbaechel/gowin/chipdb-GW1N-9C.bin"

echo "==> gowin_pack"
"$OSS/bin/gowin_pack" -d GW1N-9C -o fpga_esp_rx.fs fpga_esp_rx_pnr.json

echo "Built fpga_esp_rx.fs"
echo "Program (RAM):        openFPGALoader -b tangnano9k fpga_esp_rx.fs"
echo "Program (persistent): openFPGALoader -b tangnano9k -f fpga_esp_rx.fs"
