# Runs once at power-up. Ground GP15 (jumper to GND) while plugging in to get the CIRCUITPY drive back for updates.
import board
import digitalio
import storage
import usb_cdc
import usb_hid
import usb_midi

jumper = digitalio.DigitalInOut(board.GP15)
jumper.switch_to_input(pull=digitalio.Pull.UP)
maintenance = not jumper.value
jumper.deinit()

if not maintenance:
    storage.disable_usb_drive()  # corporate policy: no USB storage
usb_hid.disable()    # no keyboard/mouse interfaces
usb_midi.disable()
usb_cdc.enable(console=True, data=True)  # second serial channel carries the app's commands
