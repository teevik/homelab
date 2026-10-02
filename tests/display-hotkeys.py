"""Exercise the production relay and triggerhappy via a disposable uinput keyboard."""

import json
import select
import time

import evdev
from evdev import ecodes as E


def status():
    return json.load(open("/run/homelab-display-policy/status.json"))


def until(predicate):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.1)
    raise AssertionError("hotkey action did not recover")


keys = [
    E.KEY_A,
    E.KEY_C,
    E.KEY_LEFTCTRL,
    E.KEY_LEFTALT,
    E.KEY_HOME,
    E.KEY_END,
    E.KEY_INSERT,
    E.KEY_F2,
]
with evdev.UInput({E.EV_KEY: keys}, name="acceptance-keyboard") as source:
    relay = None
    deadline = time.monotonic() + 10
    while relay is None and time.monotonic() < deadline:
        for path in evdev.list_devices():
            candidate = evdev.InputDevice(path)
            if candidate.phys == "homelab-relay/" + source.device.path:
                relay = candidate
                break
            candidate.close()
        time.sleep(0.1)
    assert relay is not None, "ordinary input relay absent"
    # Capture here instead of sending test keystrokes to a login shell.
    relay.grab()
    time.sleep(0.5)

    def emit(code, value):
        source.write(E.EV_KEY, code, value)
        source.syn()
        time.sleep(0.02)

    def chord(code):
        emit(E.KEY_LEFTCTRL, 1)
        emit(E.KEY_LEFTALT, 1)
        emit(code, 1)
        emit(code, 2)  # no second action on autorepeat
        emit(code, 0)
        emit(E.KEY_LEFTALT, 0)
        emit(E.KEY_LEFTCTRL, 0)

    chord(E.KEY_HOME)
    until(lambda: status()["mode"] == "away" and not status()["screen_on"] and not status()["anime_on"])
    chord(E.KEY_END)
    until(lambda: status()["mode"] == "wake")
    expiry = status()["wake_until"]
    time.sleep(0.3)
    # A repeated physical press renews, independently of renderer/session presence.
    chord(E.KEY_END)
    until(lambda: status()["wake_until"] > expiry)
    chord(E.KEY_INSERT)
    until(lambda: status()["mode"] == "schedule" and not status()["screen_on"])
    emit(E.KEY_A, 1)
    emit(E.KEY_A, 0)
    emit(E.KEY_LEFTCTRL, 1)
    emit(E.KEY_C, 1)
    emit(E.KEY_C, 0)
    emit(E.KEY_LEFTCTRL, 0)
    chord(E.KEY_F2)  # VT chord remains ordinary input
    events = []
    while select.select([relay], [], [], 0.5)[0]:
        events.extend(e for e in relay.read() if e.type == E.EV_KEY)
    assert not any(e.code in {E.KEY_HOME, E.KEY_END, E.KEY_INSERT} for e in events)
    assert [
        (e.code, e.value) for e in events if e.code in {E.KEY_A, E.KEY_C, E.KEY_F2}
    ] == [
        (E.KEY_A, 1),
        (E.KEY_A, 0),
        (E.KEY_C, 1),
        (E.KEY_C, 0),
        (E.KEY_F2, 1),
        (E.KEY_F2, 2),
        (E.KEY_F2, 0),
    ]
    relay.close()
