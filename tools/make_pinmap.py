#!/usr/bin/env python3
"""Draw docs/pinmap.png: C5VRX digital tap -> Tang Nano 9K wiring.

Target receiver: Waveshare ESP32-C5-Zero, no headers (castellated pads).
The Zero uses the stock C5VRX DAC pin map; the only build change is the
4 MB flash partition table.
"""

from PIL import Image, ImageDraw, ImageFont

W, H = 1600, 1000
BG = (255, 255, 255)
INK = (24, 28, 33)
MUTED = (90, 100, 110)
BLUE = (31, 95, 168)
ORANGE = (217, 119, 6)
GRAY = (110, 110, 110)
GREEN = (22, 128, 80)
RED = (180, 40, 40)
BOX = (246, 248, 250)
EDGE = (190, 198, 206)

F = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

font_title = ImageFont.truetype(FB, 42)
font_sub = ImageFont.truetype(F, 22)
font_box = ImageFont.truetype(FB, 24)
font_pin = ImageFont.truetype(F, 22)
font_small = ImageFont.truetype(F, 18)
font_note = ImageFont.truetype(FB, 20)

img = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(img)

d.text((60, 36), "C5VRX digital tap  →  Tang Nano 9K HDMI VRX", font=font_title, fill=INK)
d.text((62, 92), "Waveshare ESP32-C5-Zero (castellated pads, no headers)  →  Tang Nano 9K",
       font=font_sub, fill=MUTED)

def box(x0, y0, x1, y1):
    d.rounded_rectangle((x0, y0, x1, y1), radius=16, fill=BOX, outline=EDGE, width=2)

box(60, 150, 560, 770)
box(1040, 150, 1540, 770)

d.text((90, 172), "Waveshare ESP32-C5-Zero", font=font_box, fill=INK)
d.text((90, 204), "castellated pads, no headers", font=font_small, fill=MUTED)

d.text((1070, 172), "Tang Nano 9K", font=font_box, fill=INK)
d.text((1070, 204), "J6 header (3.3 V bank)", font=font_small, fill=MUTED)

rows = [
    ("GPIO23   bottom pad", "bit0  (LSB)", "pin 25   cvbs[0]", BLUE),
    ("GPIO24   bottom pad", "bit1",        "pin 26   cvbs[1]", BLUE),
    ("GPIO6    right pad",  "bit2",        "pin 27   cvbs[2]", BLUE),
    ("GPIO12   right pad",  "bit3",        "pin 28   cvbs[3]", BLUE),
    ("GPIO8    right pad",  "bit4",        "pin 29   cvbs[4]", BLUE),
    ("GPIO9    right pad",  "bit5  (MSB)", "pin 30   cvbs[5]", BLUE),
    ("GPIO10   right pad",  "40 MHz clock", "pin 35   cvbs_clk", ORANGE),
    ("GND      left pad",   "ground",      "GND", GRAY),
]

y0 = 255
step = 64
x_left_edge = 560
x_right_edge = 1040

for i, (left, sig, right, color) in enumerate(rows):
    y = y0 + i * step
    d.text((90, y - 14), left, font=font_pin, fill=INK)
    d.text((1070, y - 14), right, font=font_pin, fill=INK)
    d.line((x_left_edge, y, x_right_edge, y), fill=color, width=4)
    d.polygon([(x_right_edge, y), (x_right_edge - 14, y - 6), (x_right_edge - 14, y + 6)], fill=color)
    tw = d.textlength(sig, font=font_small)
    d.rectangle((800 - tw / 2 - 8, y - 26, 800 + tw / 2 + 8, y - 4), fill=BG)
    d.text((800 - tw / 2, y - 25), sig, font=font_small, fill=color)

# Notes
ny = 810
d.text((60, ny),
       "Custom D10 build: bit 2 is on GPIO6 (stock C5VRX D10 uses GPIO7, but its boot-strap load blocked boot).",
       font=font_note, fill=INK)
d.text((60, ny + 34),
       "Zero has 4 MB flash. The stock C5VRX partitions assume 8 MB; apply firmware/esp32-c5-zero-4mb.patch before building.",
       font=font_note, fill=RED)
d.text((60, ny + 70),
       "GPIO7 is left disconnected (strapping pin). GPIO26/27 are antenna/WS2812; GPIO11/12 are UART0 but free.",
       font=font_small, fill=MUTED)
d.text((60, ny + 100),
       "Tap before the resistor DAC. Solder to the castellated pads. All signals 3.3 V; connect a common ground.",
       font=font_small, fill=MUTED)
d.text((60, ny + 130),
       "FPGA: 20 MS/s composite, NTSC/PAL auto-detect, luma decode, 720x480p60 / 720x576p50 HDMI.",
       font=font_small, fill=GREEN)
d.text((60, ny + 160),
       "GPIO6 (bit 2) is non-strapping; the stock C5VRX D10 pin GPIO7 is left unconnected.",
       font=font_small, fill=MUTED)

img.save("docs/pinmap.png")
print("docs/pinmap.png written")
