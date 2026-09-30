"""Recording Linux device boundary; successful fake writes are never physical proof."""

import json
import tempfile
import unittest
from pathlib import Path

from devices import LinuxDevices
from policy import Controller, State
from test_policy import at


class RecordingLinux(LinuxDevices):
    def __init__(self, config):
        super().__init__(config)
        self.effects = []
        self.lid_closed = False
        self.ac = True
        self.broken = None
        self.generation = "active producer-a asusd-a"

    def command(self, *args):
        self.effects.append(args)
        if self.broken and self.broken in args:
            raise OSError("simulated device failure")
        if args[0] == "systemctl" and args[1] == "show":
            return self.generation
        if args[0] == "busctl":
            return (
                "b "
                + str(self.lid_closed if args[-1] == "LidClosed" else self.ac).lower()
            )
        return ""

    def console(self, vt, screen_on):
        panel = self.panel()
        self.effects.append(
            (
                "console",
                vt,
                screen_on,
                int((panel / "bl_power").read_text()),
                int((panel / "brightness").read_text()),
            )
        )


class DeviceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        panel = self.root / "sys/devices/card2-eDP-2"
        panel.mkdir(parents=True)
        (panel / "status").write_text("connected")
        self.panel = panel / "amdgpu_bl2"
        self.panel.mkdir()
        for name, value in [
            ("brightness", 1234),
            ("max_brightness", 65535),
            ("bl_power", 0),
        ]:
            (self.panel / name).write_text(str(value))
        links = self.root / "sys/class/backlight"
        links.mkdir(parents=True)
        (links / "amdgpu_bl2").symlink_to(self.panel)
        active = self.root / "sys/class/tty/tty0"
        active.mkdir(parents=True)
        (active / "active").write_text("tty1")
        self.config = {
            "sys": str(self.root / "sys"),
            "state_dir": str(self.root / "state"),
            "run_dir": str(self.root / "run"),
            "initial_brightness": 3122,
            "asusctl": "asusctl",
            "systemctl": "systemctl",
            "busctl": "busctl",
        }
        self.devices = RecordingLinux(self.config)
        self.c = Controller(State(), self.devices)

    def test_dark_wake_vt_transition_and_daytime_brightness_restoration(self):
        night = at("2026-10-01T02:00:00+02:00")
        status = self.c.reconcile(night, 100, "a")
        self.assertEqual(status["failures"], [])
        self.assertIn(
            ("systemctl", "stop", "anime-matrix-stats.service"), self.devices.effects
        )
        self.assertIn(("asusctl", "anime", "--brightness", "off"), self.devices.effects)
        self.assertIn(
            ("asusctl", "anime", "--enable-display", "false"), self.devices.effects
        )
        self.assertIn(("console", "tty1", False, 4, 0), self.devices.effects)
        (self.root / "sys/class/tty/tty0/active").write_text("tty2")
        self.c.reconcile(night + 1, 101, "a")
        self.assertIn(("console", "tty2", False, 4, 0), self.devices.effects)
        self.devices.effects.clear()
        self.c.reconcile(night + 2, 102, "a", "wake")
        self.assertIn(("console", "tty2", True, 4, 0), self.devices.effects)
        self.assertEqual((self.panel / "brightness").read_text(), "1234")
        self.assertNotIn(
            ("asusctl", "anime", "--enable-display", "true"), self.devices.effects
        )
        self.assertFalse((self.root / "run/producer-permit").exists())
        self.devices.effects.clear()
        self.c.reconcile(at("2026-10-01T08:00:00+02:00"), 22000, "a")
        self.assertIn(("asusctl", "anime", "--brightness", "med"), self.devices.effects)
        self.assertIn(
            ("systemctl", "start", "anime-matrix-stats.service"), self.devices.effects
        )
        self.assertTrue((self.root / "run/producer-permit").exists())
        # No unnecessary daytime console transition/flicker on periodic recovery.
        self.devices.effects.clear()
        self.c.reconcile(at("2026-10-01T08:00:05+02:00"), 22005, "a")
        self.assertFalse(any(effect[0] == "console" for effect in self.devices.effects))

    def test_daytime_producer_and_daemon_recovery_restore_anime(self):
        day = at("2026-10-01T12:00:00+02:00")
        self.c.reconcile(day, 100, "a")
        for generation in [
            "inactive producer-a asusd-a",
            "active producer-b asusd-a",
            "active producer-b asusd-b",
        ]:
            self.devices.effects.clear()
            self.devices.generation = generation
            status = self.c.reconcile(day + 5, 105, "a")
            self.assertEqual(status["application"], "applied")
            self.assertIn(
                ("asusctl", "anime", "--enable-display", "true"), self.devices.effects
            )
        self.devices.effects.clear()
        self.c.reconcile(day + 10, 110, "a")
        self.assertNotIn(
            ("asusctl", "anime", "--enable-display", "true"), self.devices.effects
        )

    def test_failures_never_skip_other_off_controls_and_recover(self):
        self.devices.broken = "stop"
        status = self.c.reconcile(at("2026-10-01T02:00:00+02:00"), 100, "a")
        self.assertEqual(status["application"], "failed")
        self.assertEqual((self.panel / "bl_power").read_text(), "4")
        self.assertIn(
            ("asusctl", "anime", "--enable-display", "false"), self.devices.effects
        )
        self.devices.broken = None
        status = self.c.reconcile(at("2026-10-01T02:00:00+02:00"), 101, "a")
        self.assertEqual(status["application"], "applied")
        (self.panel / "bl_power").unlink()
        status = self.c.reconcile(at("2026-10-01T02:00:00+02:00"), 102, "a")
        self.assertEqual(status["application"], "failed")
        self.assertFalse(status["screen_on"])

    def test_lid_and_battery_restrict_daytime_anime_and_restart_stays_gated(self):
        day = at("2026-10-01T12:00:00+02:00")
        self.devices.lid_closed = True
        self.c.reconcile(day, 100, "a")
        self.assertFalse((self.root / "run/producer-permit").exists())
        self.devices.lid_closed = False
        self.devices.ac = False
        self.c.reconcile(day, 101, "a")
        self.assertFalse((self.root / "run/producer-permit").exists())
        self.devices.ac = True
        self.c.reconcile(day, 102, "a")
        self.assertTrue((self.root / "run/producer-permit").exists())
        recovered = RecordingLinux(self.config)
        Controller(self.c.state, recovered).reconcile(
            at("2026-10-01T23:00:00+02:00"), 50000, "a"
        )
        self.assertFalse((self.root / "run/producer-permit").exists())
        self.assertNotIn(
            ("systemctl", "start", "anime-matrix-stats.service"), recovered.effects
        )
        self.assertEqual(
            json.loads((self.root / "state/brightness.json").read_text()), 1234
        )


if __name__ == "__main__":
    unittest.main()
