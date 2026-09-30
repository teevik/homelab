"""Reserve Ctrl+Alt+Home/End/Insert; relay every other keyboard event unchanged.

Only this host service opens input devices. triggerhappy sees a separate, grabbed
fixed-action device, never the renderer or a stream of shell keystrokes.
"""

import argparse
import logging
import select
import signal
import subprocess
import time
from pathlib import Path

import evdev
from evdev import ecodes as E

CHORDS = {E.KEY_HOME: E.KEY_PROG1, E.KEY_END: E.KEY_PROG2, E.KEY_INSERT: E.KEY_PROG3}
CTRL = {E.KEY_LEFTCTRL, E.KEY_RIGHTCTRL}
ALT = {E.KEY_LEFTALT, E.KEY_RIGHTALT}


class Keyboard:
    def __init__(self, device):
        self.device = device
        self.down = set(device.active_keys())
        self.suppressed = set()
        self.relay = evdev.UInput.from_device(
            device, name="homelab-relay-keyboard", phys="homelab-relay/" + device.path
        )
        device.grab()
        for code in self.down:
            if code in CHORDS and self.down & CTRL and self.down & ALT:
                self.suppressed.add(code)
            else:
                self.relay.write(E.EV_KEY, code, 1)
        self.relay.syn()

    def forward(self, event, actions):
        if event.type == E.EV_SYN and event.code == E.SYN_DROPPED:
            # Recover by rebuilding the relay, releasing all synthetic held keys.
            raise OSError("input buffer overflow")
        if event.type == E.EV_KEY:
            if event.value == 1:
                self.down.add(event.code)
            elif event.value == 0:
                self.down.discard(event.code)
            if event.code in self.suppressed:
                if event.value == 0:
                    self.suppressed.discard(event.code)
                return
            if (
                event.code in CHORDS
                and event.value == 1
                and self.down & CTRL
                and self.down & ALT
            ):
                self.suppressed.add(event.code)
                code = CHORDS[event.code]
                actions.write(E.EV_KEY, code, 1)
                actions.syn()
                actions.write(E.EV_KEY, code, 0)
                actions.syn()
                return
        self.relay.write_event(event)

    def close(self):
        self.relay.close()
        self.device.close()  # kernel releases the exclusive grab


def serve(th_cmd: str, socket_path: str):
    keyboards = {}
    actions = evdev.UInput(
        {E.EV_KEY: list(CHORDS.values())}, name="homelab-display-actions"
    )
    socket_id = None
    scanned = 0.0

    def stop(*_):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, stop)
    try:
        while True:
            try:
                identity = Path(socket_path).stat().st_ino
                if identity != socket_id:
                    subprocess.run(
                        [
                            th_cmd,
                            "--socket",
                            socket_path,
                            "--add",
                            "--grab",
                            actions.device.path,
                        ],
                        check=True,
                        timeout=5,
                    )
                    socket_id = identity
            except (OSError, subprocess.SubprocessError):
                socket_id = None
            if time.monotonic() - scanned >= 1:
                for path in evdev.list_devices():
                    if path in keyboards:
                        continue
                    device = evdev.InputDevice(path)
                    keys = set(device.capabilities().get(E.EV_KEY, []))
                    if (
                        device.name.startswith("homelab-")
                        or not {E.KEY_A, E.KEY_LEFTCTRL, E.KEY_LEFTALT} <= keys
                    ):
                        device.close()
                        continue
                    keyboards[path] = Keyboard(device)
                scanned = time.monotonic()
            if not keyboards:
                time.sleep(0.25)
                continue
            ready, _, _ = select.select(
                [k.device for k in keyboards.values()], [], [], 0.25
            )
            for device in ready:
                keyboard = keyboards[device.path]
                try:
                    for event in device.read():
                        keyboard.forward(event, actions)
                except OSError:
                    keyboard.close()
                    del keyboards[device.path]
    finally:
        for keyboard in keyboards.values():
            keyboard.close()
        actions.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--th-cmd", required=True)
    parser.add_argument("--socket", required=True)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    serve(args.th_cmd, args.socket)
