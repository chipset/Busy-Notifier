import time

import board
import digitalio
import neopixel_write
import usb_cdc

from protocol import Controller, safe_brightness, scale

LED_PIN = board.GP0   # WS2812 data line
LED_COUNT = 10
BRIGHTNESS = 0.4      # requested; capped so the strip stays within the USB current budget

brightness = safe_brightness(LED_COUNT, BRIGHTNESS)
pin = digitalio.DigitalInOut(LED_PIN)
pin.direction = digitalio.Direction.OUTPUT
serial = usb_cdc.data
controller = Controller(time.monotonic())
buffer = bytearray()
last_color = None
last_write = 0.0


def show(color):
    red, green, blue = scale(color, brightness)
    neopixel_write.neopixel_write(pin, bytearray([green, red, blue] * LED_COUNT))  # WS2812 is GRB


while True:
    now = time.monotonic()
    if serial is not None and serial.in_waiting:
        buffer.extend(serial.read(serial.in_waiting))
        if len(buffer) > 256:
            buffer = bytearray()
        while b"\n" in buffer:
            raw, _, rest = bytes(buffer).partition(b"\n")
            buffer = bytearray(rest)
            try:
                reply = controller.handle(raw.decode("utf-8"), now)
            except UnicodeError:
                reply = None
            if reply:
                serial.write((reply + "\n").encode("utf-8"))
    color = controller.color(now)
    if color != last_color or now - last_write > 1.0:
        show(color)
        last_color, last_write = color, now
    time.sleep(0.02)
