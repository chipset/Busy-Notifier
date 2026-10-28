import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import protocol  # noqa: E402
from protocol import Controller  # noqa: E402


class ProtocolTests(unittest.TestCase):
    def test_hello_replies_without_lighting(self):
        c = Controller(0)
        self.assertEqual(c.handle("HELLO", 1), protocol.HELLO_REPLY)
        self.assertEqual(c.color(1), (0, 0, 0))

    def test_states_and_heartbeat_timeout(self):
        c = Controller(0)
        c.handle("STATE busy", 1)
        self.assertEqual(c.color(2), (255, 0, 0))
        self.assertEqual(c.color(1 + protocol.TIMEOUT - 0.1), (255, 0, 0))
        self.assertEqual(c.color(1 + protocol.TIMEOUT + 0.1), (0, 0, 0))
        c.handle("STATE busy", 20)  # heartbeat revives the same state
        self.assertEqual(c.color(21), (255, 0, 0))

    def test_attention_flashes_slowly(self):
        c = Controller(0)
        c.handle("STATE attention", 0)
        self.assertEqual(c.color(0.5), (255, 90, 0))
        self.assertEqual(c.color(1.5), (0, 0, 0))
        self.assertEqual(c.color(2.5), (255, 90, 0))
        c.handle("STATE attention", 1.5)  # heartbeat must not restart the flash
        self.assertEqual(c.color(1.6), (0, 0, 0))

    def test_invalid_input_is_ignored(self):
        c = Controller(0)
        for line in ["", "STATE", "STATE purple", "STATE busy extra", "state busy", "\x00\xff", "A" * 300]:
            self.assertIsNone(c.handle(line, 1))
        self.assertEqual(c.color(1), (0, 0, 0))

    def test_brightness_cap_protects_usb_budget(self):
        self.assertAlmostEqual(protocol.safe_brightness(10, 1.0), 400 / 600)
        self.assertEqual(protocol.safe_brightness(10, 0.4), 0.4)
        self.assertLess(10 * 60 * protocol.safe_brightness(10, 1.0), 500)
        self.assertEqual(protocol.scale((255, 180, 0), 0.4), (102, 72, 0))


if __name__ == "__main__":
    unittest.main()
