# Meeting Busy USB light

An optional status light: an RP2040 board (for example an RP2040-Zero) driving a WS2812 ("NeoPixel") strip. Meeting Busy sends it one of five state names over USB serial. No network is involved, and no meeting details are ever sent.

| State | Light |
|---|---|
| `busy` (meeting, Force Busy) | solid red |
| `presenting` | solid yellow |
| `free` (idle, available) | off (edit `PATTERNS["free"]` for a dim green) |
| `attention` (setup needed, extension stopped reporting) | slow amber flash |
| `off` (paused, disabled, app quit, Mac asleep) | off |

If the board hears no `STATE` line for 10 seconds, it turns the light off. Meeting Busy resends the state every few seconds.

## Wiring (10 LEDs)
- Strip 5 V → board 5 V (VBUS), strip GND → board GND, strip data → **GP0** (optionally through a 330 Ω resistor).
- A WS2812 runs 5 V logic; a short 3.3 V data line normally works. Add a level shifter if the strip flickers.
- Current: `LED_COUNT` and `BRIGHTNESS` live at the top of `code.py`. The firmware caps brightness so a full-white strip stays under about 400 mA (USB 2.0 allows 500 mA). For 10 LEDs that cap is about 0.67; the default is 0.4.

## Install (CircuitPython)
1. Flash CircuitPython for your board (hold BOOT while plugging in, copy the UF2 from circuitpython.org). The `RPI-RP2` and `CIRCUITPY` drives only appear during this setup.
2. Copy `boot.py`, `code.py` and `protocol.py` to the `CIRCUITPY` drive. Copy `boot.py` last, then unplug and re-plug the board.
3. `boot.py` then disables the USB drive, the HID keyboard/mouse interfaces and MIDI, and enables a second serial channel for the app. The board shows only as serial devices.
4. In Meeting Busy, turn on **Settings → USB indicator light** and press **Test light**.

## Updating the firmware
The drive is hidden after setup. Connect **GP15 to GND** with a jumper (or a wire) while plugging the board in; the drive appears, edit the files, remove the jumper and re-plug.

## Tests
`python3 -m unittest discover -s Firmware/UsbLight/tests` covers the protocol, flash timing, the timeout and the brightness cap. The hardware parts (`boot.py`, `code.py`) have not been run on a real board in this repository's tests.
