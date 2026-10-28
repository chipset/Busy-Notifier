"""Pure logic for the Meeting Busy USB light, free of hardware imports so it is testable on a Mac.

Protocol (one line per command, UTF-8, newline terminated):
  HELLO          -> replies "MEETINGBUSY 1"; does not change the light
  STATE <name>   -> busy | presenting | free | attention | off; also serves as the heartbeat
Anything else is ignored. If no STATE arrives for TIMEOUT seconds the light turns off.
"""

HELLO_REPLY = "MEETINGBUSY 1"
TIMEOUT = 10.0
MA_PER_LED = 60.0   # worst case: full-white WS2812
USB_BUDGET_MA = 400.0  # stay under the 500 mA USB 2.0 limit

# Edit colours and flash periods here. period 0 = solid, otherwise a full on/off cycle in seconds.
PATTERNS = {
    "busy": ((255, 0, 0), 0),
    "presenting": ((255, 180, 0), 0),
    "free": ((0, 0, 0), 0),          # try (0, 40, 0) for a dim green "available" glow
    "attention": ((255, 90, 0), 2.0),  # slow amber flash
    "off": ((0, 0, 0), 0),
}


def safe_brightness(led_count, requested):
    """Cap brightness so even all-white stays inside the USB current budget."""
    limit = USB_BUDGET_MA / (led_count * MA_PER_LED)
    return max(0.0, min(requested, limit, 1.0))


def scale(color, brightness):
    return tuple(int(channel * brightness) for channel in color)


def parse_line(line):
    """Returns ("hello", None), ("state", name) or (None, None)."""
    parts = line.strip().split()
    if parts == ["HELLO"]:
        return ("hello", None)
    if len(parts) == 2 and parts[0] == "STATE" and parts[1] in PATTERNS:
        return ("state", parts[1])
    return (None, None)


class Controller:
    def __init__(self, now):
        self.state = "off"
        self.changed = now
        self.heard = None

    def handle(self, line, now):
        """Applies a line. Returns text to send back, or None."""
        kind, value = parse_line(line)
        if kind == "hello":
            return HELLO_REPLY
        if kind == "state":
            if value != self.state:
                self.state = value
                self.changed = now
            self.heard = now
        return None

    def color(self, now):
        if self.heard is None or now - self.heard > TIMEOUT:
            return (0, 0, 0)
        rgb, period = PATTERNS[self.state]
        if period and int((now - self.changed) / (period / 2.0)) % 2 == 1:
            return (0, 0, 0)
        return rgb
