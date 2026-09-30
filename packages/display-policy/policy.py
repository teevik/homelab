"""Serialized policy boundary; no UI, input, clocks or device access here."""

from dataclasses import asdict, dataclass
from datetime import datetime, time, timedelta
from threading import RLock
from typing import Callable, Protocol
from zoneinfo import ZoneInfo

OSLO = ZoneInfo("Europe/Oslo")
ACTIONS = ("bedtime", "wake", "resume-schedule")


@dataclass
class State:
    bedtime_until: float | None = None
    wake_until: float | None = None
    wake_deadline: float | None = None
    wake_boot: str | None = None

    def clear_wake(self) -> None:
        self.wake_until = self.wake_deadline = self.wake_boot = None


@dataclass(frozen=True)
class Intent:
    screen_on: bool
    anime_on: bool


class Devices(Protocol):
    def apply(self, intent: Intent) -> list[str]: ...


def scheduled_dark(now: float) -> bool:
    local = datetime.fromtimestamp(now, OSLO)
    return local.hour >= 23 or local.hour < 8


def next_morning(local: datetime) -> datetime:
    day = local.date()
    if local.hour >= 8:
        day += timedelta(days=1)
    return datetime.combine(day, time(8), OSLO)


class Controller:
    def __init__(
        self,
        state: State,
        devices: Devices,
        persist: Callable[[State], None] = lambda state: None,
    ):
        self.state = state
        self.devices = devices
        self.lock = RLock()
        self.persist = persist

    def reconcile(
        self, now: float, uptime: float, boot: str, action: str | None = None
    ) -> dict:
        with self.lock:
            local = datetime.fromtimestamp(now, OSLO)
            scheduled = scheduled_dark(now)
            state = self.state
            if state.bedtime_until is not None and now >= state.bedtime_until:
                state.bedtime_until = None
            if state.wake_boot != boot or (
                state.wake_deadline is not None and uptime >= state.wake_deadline
            ):
                state.clear_wake()
            if action == "bedtime":
                morning = next_morning(local)
                state.bedtime_until = morning.timestamp()
                state.clear_wake()
            elif action == "wake":
                if scheduled or state.bedtime_until is not None:
                    state.wake_until = now + 600
                    state.wake_deadline = uptime + 600
                    state.wake_boot = boot
            elif action == "resume-schedule":
                state.bedtime_until = None
                state.clear_wake()
            elif action is not None:
                raise ValueError("unknown fixed action")
            if state.wake_deadline is not None:
                state.wake_until = now + state.wake_deadline - uptime
            dark = scheduled or state.bedtime_until is not None
            schedule_until = (
                next_morning(local)
                if scheduled
                else datetime.combine(local.date(), time(23), OSLO)
            ).timestamp()
            intent = Intent(not dark or state.wake_until is not None, not dark)
            failures = []
            try:
                self.persist(state)
            except OSError as error:
                failures.append(f"policy persistence: {error}")
            failures.extend(self.devices.apply(intent))
            return {
                "version": 1,
                "observed_at": now,
                "boot_id": boot,
                "scheduled_dark": scheduled,
                "schedule_until": schedule_until,
                "bedtime_until": state.bedtime_until,
                "wake_until": state.wake_until,
                "mode": (
                    "wake"
                    if dark and state.wake_until is not None
                    else ("bedtime" if state.bedtime_until is not None else "schedule")
                ),
                "screen_on": intent.screen_on,
                "anime_on": intent.anime_on,
                "application": "failed" if failures else "applied",
                "failures": failures,
                "persisted": asdict(state),
            }
