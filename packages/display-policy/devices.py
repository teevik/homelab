"""Linux boundary: panel sysfs, active console, asusd and systemd producer."""

import json
import os
import re
import subprocess
from pathlib import Path
from typing import Callable

from policy import Intent


def atomic_json(path: Path, value: object, mode: int = 0o600) -> None:
    atomic_text(path, json.dumps(value) + "\n", mode)


def atomic_text(path: Path, text: str, mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    with temporary.open("w") as output:
        os.fchmod(output.fileno(), mode)
        output.write(text)
        output.flush()
        os.fsync(output.fileno())
    temporary.replace(path)
    directory = os.open(path.parent, os.O_DIRECTORY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


class LinuxDevices:
    def __init__(self, config: dict):
        self.config = config
        self.sys = Path(config.get("sys", "/sys"))
        self.dev = Path(config.get("dev", "/dev"))
        self.state_dir = Path(config["state_dir"])
        self.run_dir = Path(config["run_dir"])
        self.brightness_file = self.state_dir / "brightness.json"
        self.console_state: tuple[str, bool] | None = None
        self.anime_state: bool | None = None
        self.anime_generation: str | None = None

    def command(self, *arguments: str) -> str:
        result = subprocess.run(
            arguments, check=True, capture_output=True, text=True, timeout=3
        )
        return result.stdout.strip()

    def panel(self) -> Path:
        candidates = []
        for entry in (self.sys / "class/backlight").glob("*"):
            parent = entry.resolve().parent
            if (
                "-eDP-" in parent.name
                and (parent / "status").read_text().strip() == "connected"
            ):
                candidates.append(entry)
        if len(candidates) != 1:
            raise RuntimeError(
                f"expected one connected eDP backlight, found {len(candidates)}"
            )
        return candidates[0]

    @staticmethod
    def write(path: Path, value: int) -> None:
        path.write_text(str(value))
        if int(path.read_text()) != value:
            raise RuntimeError(f"{path}: write did not stick")

    def panel_off(self, panel: Path) -> None:
        # Save a nonzero intended brightness BEFORE zeroing; keep it across recovery.
        brightness = int((panel / "brightness").read_text())
        failures = []
        if brightness > 0:
            try:
                atomic_json(self.brightness_file, brightness)
            except OSError as error:
                failures.append(f"brightness persistence: {error}")
        # Both controls must succeed. brightness=0 alone is not accepted power control.
        for name, value in [("bl_power", 4), ("brightness", 0)]:
            try:
                self.write(panel / name, value)
            except (OSError, ValueError, RuntimeError) as error:
                failures.append(str(error))
        if failures:
            raise RuntimeError("; ".join(failures))

    def panel_on(self, panel: Path) -> None:
        brightness = self.config["initial_brightness"]
        if self.brightness_file.exists():
            brightness = json.loads(self.brightness_file.read_text())
        maximum = int((panel / "max_brightness").read_text())
        if not isinstance(brightness, int) or not 0 < brightness <= maximum:
            raise RuntimeError("saved daytime brightness outside panel range")
        self.write(panel / "brightness", brightness)
        self.write(panel / "bl_power", 0)

    def console(self, vt: str, screen_on: bool) -> None:
        if not re.fullmatch(r"tty[1-9][0-9]*", vt):
            raise RuntimeError("invalid active console")
        with (self.dev / vt).open("r+b", buffering=0) as console:
            subprocess.run(
                [self.config["setterm"], "--blank", "poke" if screen_on else "force"],
                stdin=console,
                stdout=console,
                stderr=subprocess.PIPE,
                env={**os.environ, "TERM": "linux"},
                check=True,
                timeout=3,
            )

    def anime_off(self) -> None:
        # Separate requests: the 6.3.8 CLI processes display before brightness.
        failures = []
        for arguments in [
            ("anime", "--brightness", "off"),
            ("anime", "--enable-display", "false"),
        ]:
            try:
                self.command(self.config["asusctl"], *arguments)
            except (OSError, subprocess.SubprocessError) as error:
                failures.append(str(error))
        self.anime_state = False if not failures else None
        if failures:
            raise RuntimeError("; ".join(failures))

    def anime_permitted(self) -> bool:
        lid = self.command(
            self.config["busctl"],
            "get-property",
            "org.freedesktop.login1",
            "/org/freedesktop/login1",
            "org.freedesktop.login1.Manager",
            "LidClosed",
        )
        ac = self.command(
            self.config["busctl"],
            "get-property",
            "org.freedesktop.login1",
            "/org/freedesktop/login1",
            "org.freedesktop.login1.Manager",
            "OnExternalPower",
        )
        return lid == "b false" and ac == "b true"

    def apply(self, intent: Intent) -> list[str]:
        failures: list[str] = []

        def attempt(name: str, operation: Callable[[], object]) -> bool:
            try:
                operation()
                return True
            except (
                OSError,
                ValueError,
                RuntimeError,
                subprocess.SubprocessError,
            ) as error:
                failures.append(f"{name}: {error}")
                return False

        # Revoke first; failed starts/restarts cannot obtain yesterday's permission.
        permit = self.run_dir / "producer-permit"
        permit.unlink(missing_ok=True)
        allowed = False
        if intent.anime_on:
            try:
                allowed = self.anime_permitted()
            except (OSError, subprocess.SubprocessError) as error:
                failures.append(f"lid/AC observation: {error}")
        if not allowed:
            attempt(
                "producer stop",
                lambda: self.command(
                    self.config["systemctl"], "stop", "anime-matrix-stats.service"
                ),
            )
            attempt("AniMe off", self.anime_off)

        # Independently enforce panel darkness even if asusd or the producer failed.
        try:
            panel = self.panel()
            vt = (self.sys / "class/tty/tty0/active").read_text().strip()
            changed = self.console_state != (vt, intent.screen_on)
            mismatched = int((panel / "bl_power").read_text()) != (
                0 if intent.screen_on else 4
            )
            if not intent.screen_on or changed or mismatched:
                off_ok = attempt("panel off", lambda: self.panel_off(panel))
                console_ok = (
                    attempt(
                        "active console", lambda: self.console(vt, intent.screen_on)
                    )
                    if off_ok
                    else False
                )
                if off_ok and console_ok:
                    self.console_state = (vt, intent.screen_on)
                    if intent.screen_on:
                        attempt("panel restore", lambda: self.panel_on(panel))
        except (OSError, ValueError, RuntimeError) as error:
            failures.append(f"panel discovery: {error}")

        if allowed and not failures:
            permitted = attempt(
                "producer authorization",
                lambda: atomic_text(permit, "permitted\n", 0o600),
            )
            started = permitted and attempt(
                "producer start",
                lambda: self.command(
                    self.config["systemctl"], "start", "anime-matrix-stats.service"
                ),
            )
            if started:
                # Observe AFTER startup has finished: the previous producer's stop
                # hook must not disable AniMe after a successful restoration.
                try:
                    generation = self.command(
                        self.config["systemctl"],
                        "show",
                        "--property=InvocationID",
                        "--property=ActiveState",
                        "--value",
                        "anime-matrix-stats.service",
                        "asusd.service",
                    )
                    if generation != self.anime_generation:
                        self.anime_state = None
                except (OSError, subprocess.SubprocessError) as error:
                    failures.append(f"AniMe service observation: {error}")
                if not failures and self.anime_state is not True:
                    ready = attempt(
                        "AniMe restore",
                        lambda: self.command(
                            self.config["asusctl"], "anime", "--brightness", "med"
                        ),
                    )
                    if ready:
                        ready = attempt(
                            "AniMe enable",
                            lambda: self.command(
                                self.config["asusctl"],
                                "anime",
                                "--enable-display",
                                "true",
                            ),
                        )
                    self.anime_state = True if ready else None
                if not failures:
                    self.anime_generation = generation
            if failures:
                permit.unlink(missing_ok=True)
                attempt(
                    "producer stop",
                    lambda: self.command(
                        self.config["systemctl"], "stop", "anime-matrix-stats.service"
                    ),
                )
                attempt("AniMe off", self.anime_off)
        return failures
