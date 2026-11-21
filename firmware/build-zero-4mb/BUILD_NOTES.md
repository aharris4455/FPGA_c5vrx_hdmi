# C5VRX 4 MB build for the ESP32-C5-Zero

Local test build produced by this project. **Flashed and booted on the
ESP32-C5-Zero.**

| Item | Value |
| --- | --- |
| C5VRX source | `main` @ `8b60fef0f43f` (2026-11-16), with `../esp32-c5-zero-4mb.patch` |
| ESP-IDF | v6.0.2 (`7101770dc6db`), target `esp32c5` |
| App image | `c5vrx5.bin`, 1,255,520 bytes (`0x132860`) |
| App partition | 2.375 MiB (`0x260000`), 1,234,848 bytes free (50%) |
| Merged image | `c5vrx5_zero_merged.bin`, 1,321,056 bytes (`0x142860`) |
| Flash layout | 4 MB, DIO, 80 MHz; bootloader `0x2000`, partition table `0x8000`, app `0x10000` |
| Version / commit | `4mb-zero-test` / `local-test` (test build markers) |

Build command:

```sh
. ~/esp-idf-v6.0.2/export.sh
cd C5VRX
IDF_TARGET=esp32c5 idf.py \
  -DC5VRX5_VERSION="4mb-zero-test" -DC5VRX5_COMMIT="local-test" build
```

## Flash

Merged image at offset `0x0`:

```sh
python -m esptool --chip esp32c5 -p PORT write_flash 0x0 c5vrx5_zero_merged.bin
```

Or use the component files:

```sh
python -m esptool --chip esp32c5 -p PORT write_flash \
    --flash-mode dio --flash-size 4MB --flash-freq 80m \
    0x2000 bootloader.bin 0x8000 partition-table.bin 0x10000 c5vrx5.bin
```

The web flasher can also use the merged image with **Local File** at offset
`0x0`.

## Flash result

Flashed on 2026-11-19 to `/dev/ttyACM0` (ESP32-C5HF4, 4 MB, USB-Serial/JTAG):

- bootloader at `0x2000`: 23,232 bytes, hash verified
- partition table at `0x8000`: 3,072 bytes, hash verified
- app at `0x10000`: 1,255,520 bytes, hash verified

After the write, esptool's RTS hard reset left the USB-Serial/JTAG
unresponsive. Recovery was: BOOT/RESET into ROM, clean erase + reflash with
`--before no-reset --after watchdog-reset`, then a USB power cycle and a
console opened with **DTR asserted**.

The board now boots and reports:

```text
SAMPLE_CLOCK enabled=0 gpio=-1 hz=0 dac_bit2_gpio=11
C5VRX5 4mb-zero-test ready: A1 5865 MHz, D32-R2, ultrafine IQ, gain LEVEL
STATUS channel=A1 freq=5865 ... fw=4mb-zero-test+local-test
```

D10 is still off (`SAMPLE_CLOCK enabled=0`); enable it and move bit 2 to
GPIO7 before using the FPGA tap.

The clean flash erased NVS, so the receiver reports `NOT_CALIBRATED` in
`D`/`RANGE_DIAG`. Run C5VRX's **CALIBRATE** with the VTX off before judging
the picture; that is a wiped-calibration state, not a soldering fault.

### Zero USB console note

The Zero's native USB-Serial/JTAG CDC needs **DTR asserted** for the
console. C5VRX's `tools/flash.py` opens the port with DTR/RTS low (an XIAO
convention) and makes the Zero look silent. Use a normal serial terminal at
115200 with DTR high, or a script with `DTR=True, RTS=False`.

To flash, enter the ROM loader with **BOOT/RESET** and use esptool with
`--before no-reset --after watchdog-reset`. Avoid the RTS hard reset; it
hangs the native USB-JTAG.

## Verified

- The 4 MB partition table parses with the expected 2.375 MiB app and
  1.5 MiB flightlog.
- `flasher_args.json` and `sdkconfig` select 4 MB.
- `idf.py build` completes; the app-size check reports 50% free.
- All three flash regions wrote and verified.
- The board boots the test build and prints the C5VRX startup/status log
  over USB with DTR asserted.

## Not verified

- D10/FPGA capture on the Zero; D10 is still off in the flashed settings.
- The flight-log code's behaviour on the 1.5 MiB partition.

After flashing, enable **EXPERIMENTAL → Clock Pin D10**, move the bit-2
branch/wire from GPIO11 to GPIO7, and reboot. See
[`../../docs/C5VRX-FIRMWARE.md`](../../docs/C5VRX-FIRMWARE.md).
