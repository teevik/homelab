"""Approved time/action/persisted-state -> reported policy/device-effects seam."""

import unittest
from threading import Event, Thread
from datetime import datetime

from policy import Controller, State


class RecordingDevices:
    def __init__(self):
        self.effects = []
        self.failure = None

    def apply(self, intent):
        self.effects.append(intent)
        return [self.failure] if self.failure else []


def at(value):
    return datetime.fromisoformat(value).timestamp()


class PolicyTests(unittest.TestCase):
    def test_away_survives_mornings_reboots_and_temporary_wake_until_resume(self):
        c = Controller(State(), RecordingDevices())
        start = at("2026-10-02T11:00:00+02:00")
        status = c.reconcile(start, 100, "a", "away")
        self.assertEqual(status["mode"], "away")
        self.assertFalse(status["screen_on"])
        self.assertFalse(status["anime_on"])
        # Restoring persisted state on a new boot must not restore either display.
        c = Controller(State(**status["persisted"]), RecordingDevices())
        morning = at("2026-10-05T08:00:00+02:00")
        status = c.reconcile(morning, 10, "b")
        self.assertEqual(status["mode"], "away")
        self.assertFalse(status["screen_on"])
        self.assertFalse(status["anime_on"])
        status = c.reconcile(morning, 10, "b", "wake")
        self.assertTrue(status["screen_on"])
        self.assertFalse(status["anime_on"])
        status = c.reconcile(morning + 600, 610, "b")
        self.assertEqual(status["mode"], "away")
        self.assertFalse(status["screen_on"])
        # A bedtime request cannot silently shorten the persistent override.
        status = c.reconcile(morning + 600, 610, "b", "bedtime")
        status = c.reconcile(at("2026-10-06T08:00:00+02:00"), 87010, "b")
        self.assertFalse(status["screen_on"])
        status = c.reconcile(at("2026-10-06T08:00:00+02:00"), 87010, "b", "resume-schedule")
        self.assertEqual(status["mode"], "schedule")
        self.assertTrue(status["screen_on"])
        self.assertTrue(status["anime_on"])

    def test_bedtime_dst_restart_and_latest_request_wins(self):
        for evening, morning in [
            ("2026-03-28T22:00:00+01:00", "2026-03-29T08:00:00+02:00"),
            ("2026-10-24T22:00:00+02:00", "2026-10-25T08:00:00+01:00"),
            ("2026-09-30T07:59:00+02:00", "2026-09-30T08:00:00+02:00"),
            ("2026-09-30T08:00:00+02:00", "2026-10-01T08:00:00+02:00"),
        ]:
            with self.subTest(evening=evening):
                c = Controller(State(), RecordingDevices())
                status = c.reconcile(at(evening), 100, "a", "bedtime")
                self.assertEqual(status["bedtime_until"], at(morning))
                if at(morning) - at(evening) < 600:
                    continue
                c = Controller(State(**status["persisted"]), RecordingDevices())
                status = c.reconcile(at(evening) + 60, 160, "a", "wake")
                self.assertEqual(status["mode"], "wake")
                status = c.reconcile(at(evening) + 120, 220, "a", "bedtime")
                self.assertFalse(status["screen_on"])
                self.assertIsNone(status["wake_until"])
                c = Controller(State(**status["persisted"]), RecordingDevices())
                status = c.reconcile(at(evening) + 180, 10, "new-boot")
                self.assertFalse(status["screen_on"])
                status = c.reconcile(at(morning), 100000, "new-boot")
                self.assertTrue(status["screen_on"])
                self.assertIsNone(status["bedtime_until"])

    def test_wake_renewal_clock_correction_and_same_boot_recovery(self):
        c = Controller(State(), RecordingDevices())
        start = at("2026-10-01T02:00:00+02:00")
        status = c.reconcile(start, 100, "a", "wake")
        c = Controller(State(**status["persisted"]), RecordingDevices())
        status = c.reconcile(start - 3600, 400, "a")
        self.assertTrue(status["screen_on"])
        self.assertEqual(status["wake_until"], start - 3300)
        status = c.reconcile(start - 3500, 500, "a", "wake")
        self.assertEqual(status["wake_until"], start - 2900)
        status = c.reconcile(start - 2901, 1099, "a")
        self.assertTrue(status["screen_on"])
        status = c.reconcile(start - 2900, 1100, "a")
        self.assertFalse(status["screen_on"])
        status = c.reconcile(start, 1200, "a", "wake")
        c = Controller(State(**status["persisted"]), RecordingDevices())
        status = c.reconcile(start + 1, 1, "b")
        self.assertFalse(status["screen_on"])
        self.assertIsNone(status["wake_until"])

    def test_persistence_precedes_effects_and_failures_are_reported(self):
        effects = []
        devices = RecordingDevices()
        original = devices.apply

        def apply(intent):
            self.assertEqual(effects[-1], "persist")
            return original(intent)

        devices.apply = apply
        c = Controller(
            State(), devices, persist=lambda state: effects.append("persist")
        )
        devices.failure = "panel power unavailable"
        status = c.reconcile(at("2026-09-30T02:00:00+02:00"), 100, "a", "bedtime")
        self.assertEqual(status["application"], "failed")
        self.assertEqual(status["failures"], ["panel power unavailable"])
        self.assertFalse(status["screen_on"])

    def test_resume_at_night_and_morning_expiry(self):
        c = Controller(State(), RecordingDevices())
        now = at("2026-09-30T07:55:00+02:00")
        c.reconcile(now, 100, "a", "bedtime")
        status = c.reconcile(now, 100, "a", "wake")
        self.assertFalse(status["anime_on"])
        status = c.reconcile(now + 600, 700, "a")
        self.assertTrue(status["screen_on"])
        self.assertTrue(status["anime_on"])
        now = at("2026-10-01T02:00:00+02:00")
        c.reconcile(now, 800, "a", "wake")
        status = c.reconcile(now, 801, "a", "resume-schedule")
        self.assertFalse(status["screen_on"])
        self.assertIsNone(status["wake_until"])
        self.assertIsNone(status["bedtime_until"])
        # Ordinary device/time notifications carry no explicit action.
        for elapsed in range(10):
            self.assertFalse(
                c.reconcile(now + elapsed, 802 + elapsed, "a")["screen_on"]
            )
        with self.assertRaises(ValueError):
            c.reconcile(now, 900, "a", "input")

    def test_requests_serialize_effects_and_latest_explicit_request_wins(self):
        entered, release = Event(), Event()
        effects = []

        class BlockingDevices:
            def apply(self, intent):
                effects.append(intent)
                if len(effects) == 1:
                    entered.set()
                    self_released = release.wait(5)
                    if not self_released:
                        raise RuntimeError("test effect did not release")
                return []

        c = Controller(State(), BlockingDevices())
        now = at("2026-10-01T02:00:00+02:00")
        results = []
        first = Thread(
            target=lambda: results.append(c.reconcile(now, 100, "a", "wake"))
        )
        first.start()
        self.assertTrue(entered.wait(5))
        second = Thread(
            target=lambda: results.append(c.reconcile(now, 101, "a", "bedtime"))
        )
        second.start()
        self.assertEqual(len(effects), 1)
        release.set()
        first.join(5)
        second.join(5)
        self.assertEqual(len(results), 2)
        self.assertTrue(effects[0].screen_on)
        self.assertFalse(effects[1].screen_on)
        final = c.reconcile(now, 102, "a")
        self.assertEqual(final["mode"], "bedtime")
        self.assertIsNone(final["wake_until"])

    def test_missed_boundaries_and_both_dst_transitions_use_oslo_calendar(self):
        c = Controller(State(), RecordingDevices())
        for moment, morning in [
            ("2026-03-29T01:59:59+01:00", "2026-03-29T08:00:00+02:00"),
            ("2026-03-29T03:00:00+02:00", "2026-03-29T08:00:00+02:00"),
            ("2026-10-25T02:30:00+02:00", "2026-10-25T08:00:00+01:00"),
            ("2026-10-25T02:30:00+01:00", "2026-10-25T08:00:00+01:00"),
        ]:
            status = c.reconcile(at(moment), 100, "a")
            self.assertFalse(status["screen_on"])
            self.assertEqual(status["schedule_until"], at(morning))
        status = c.reconcile(at("2026-10-25T12:00:00+01:00"), 50000, "a")
        self.assertTrue(status["screen_on"])
        self.assertEqual(status["schedule_until"], at("2026-10-25T23:00:00+01:00"))

    def test_oslo_schedule_edges_and_screen_only_wake(self):
        devices = RecordingDevices()
        controller = Controller(State(), devices)
        status = controller.reconcile(at("2026-09-30T22:59:59+02:00"), 100, "boot-a")
        self.assertTrue(status["screen_on"])
        self.assertTrue(status["anime_on"])
        status = controller.reconcile(at("2026-09-30T23:00:00+02:00"), 101, "boot-a")
        self.assertFalse(status["screen_on"])
        self.assertFalse(status["anime_on"])
        status = controller.reconcile(
            at("2026-09-30T23:01:00+02:00"), 161, "boot-a", "wake"
        )
        self.assertTrue(status["screen_on"])
        self.assertFalse(status["anime_on"])
        self.assertEqual(status["wake_until"], at("2026-09-30T23:11:00+02:00"))
        status = controller.reconcile(at("2026-10-01T08:00:00+02:00"), 32501, "boot-a")
        self.assertTrue(status["screen_on"])
        self.assertTrue(status["anime_on"])


if __name__ == "__main__":
    unittest.main()
