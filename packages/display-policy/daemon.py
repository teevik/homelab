"""Fixed-action Unix socket service. Everything runs on one serialized event loop."""

import argparse
import json
import logging
import math
import os
import pwd
import socket
import struct
import sys
import time
from dataclasses import asdict
from pathlib import Path

from devices import LinuxDevices, atomic_json, atomic_text
from policy import ACTIONS, Controller, State, scheduled_dark


class NoDevices:
    def apply(self, intent):
        return []


def clock(config: dict) -> tuple[float, float, str]:
    return (
        time.time(),
        time.clock_gettime(time.CLOCK_BOOTTIME),
        Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
    )


def state_path(config: dict) -> Path:
    return Path(config["state_dir"]) / "policy.json"


def load_state(config: dict) -> State:
    try:
        data = json.loads(state_path(config).read_text())
    except FileNotFoundError:
        return State()
    state = State(**data)
    if not isinstance(state.away, bool):
        raise ValueError("invalid persisted away mode")
    for value in (state.bedtime_until, state.wake_until, state.wake_deadline):
        if value is not None and (
            not isinstance(value, (float, int)) or not math.isfinite(value)
        ):
            raise ValueError("invalid persisted policy timestamp")
    if (state.wake_until is None) != (state.wake_deadline is None):
        raise ValueError("incomplete persisted wake")
    return state


def producer_permitted(config: dict) -> bool:
    """ExecCondition rechecks schedule/time/boot even if the controller is absent."""
    now, uptime, boot = clock(config)
    permission = Path(config["run_dir"]) / "producer-permit"
    if not permission.exists() or not 0 <= now - permission.stat().st_mtime < 15:
        return False
    status = Controller(load_state(config), NoDevices()).reconcile(now, uptime, boot)
    return status["anime_on"] and LinuxDevices(config).anime_permitted()


def request(config: dict, action: str) -> dict:
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(45)
        client.connect(str(Path(config["run_dir"]) / "control.sock"))
        client.sendall((action + "\n").encode())
        chunks = []
        while chunk := client.recv(65536):
            chunks.append(chunk)
        result = json.loads(b"".join(chunks))
        if "error" in result:
            raise RuntimeError(result["error"])
        return result


def notify_ready() -> None:
    """Release systemd startup ordering only once requests can be served."""
    endpoint = os.environ.get("NOTIFY_SOCKET")
    if endpoint is None:
        return
    # systemd also supports Linux abstract Unix sockets, written with an @ prefix.
    if endpoint.startswith("@"):
        endpoint = "\0" + endpoint[1:]
    with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as notification:
        notification.connect(endpoint)
        notification.sendall(b"READY=1")


def serve(config: dict) -> None:
    run = Path(config["run_dir"])
    run.mkdir(parents=True, exist_ok=True)
    # A single systemd-owned daemon is the only state writer. Never overlap daemons.
    import fcntl

    lock = (Path(config["state_dir"]) / "controller.lock").open("a")
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    authorized_uid = pwd.getpwnam(config["authorized_user"]).pw_uid
    errors = []
    try:
        state = load_state(config)
    except (OSError, ValueError, TypeError) as error:
        errors.append(f"persisted policy unreadable: {error}; darkness until repaired")
        state = State(bedtime_until=253402214400.0)

    def persist(state: State) -> None:
        if not errors:
            existing = state_path(config)
            data = asdict(state)
            if not existing.exists() or json.loads(existing.read_text()) != data:
                atomic_json(existing, data)

    devices = LinuxDevices(config)
    controller = Controller(state, devices, persist)
    previous_failures = None

    def reconcile(action: str | None = None) -> dict:
        nonlocal previous_failures
        if errors and action is not None:
            raise RuntimeError(
                "persisted policy unreadable; repair state before overriding darkness"
            )
        status = controller.reconcile(*clock(config), action)
        status["failures"].extend(errors)
        if status["failures"]:
            status["application"] = "failed"
        atomic_json(run / "status.json", status, 0o644)
        now = status["observed_at"]
        atomic_text(
            Path(config["metrics_dir"]) / "display-policy.prom",
            f'homelab_display_policy_failure {int(bool(status["failures"]))}\n'
            f"homelab_display_policy_reconciled_seconds {now}\n",
        )
        if previous_failures != status["failures"]:
            (
                logging.error("device application failures: %s", status["failures"])
                if status["failures"]
                else logging.info("device controls applied")
            )
            previous_failures = list(status["failures"])
        return status

    endpoint = run / "control.sock"
    endpoint.unlink(missing_ok=True)
    with socket.socket(socket.AF_UNIX) as server:
        server.bind(str(endpoint))
        # Auth uses kernel peer uid, not client-provided names or JSON.
        endpoint.chmod(0o666)
        server.listen(16)
        server.settimeout(0.5)
        reconcile()
        last = time.monotonic()
        signature = None
        status = json.loads((run / "status.json").read_text())
        notify_ready()
        while True:
            # Fast active-VT detection; periodic full recovery also handles missed lid/AC events.
            try:
                active = (devices.sys / "class/tty/tty0/active").read_text().strip()
            except OSError:
                active = None
            lid_paths = Path(config.get("proc", "/proc")).glob(
                "acpi/button/lid/*/state"
            )
            power_paths = (devices.sys / "class/power_supply").glob("*/online")
            events = [active]
            for path in [*lid_paths, *power_paths]:
                try:
                    events.append(path.read_text())
                except OSError:
                    events.append(None)
            now, uptime, boot = clock(config)
            due = (
                state.wake_deadline is not None and uptime >= state.wake_deadline
            ) or (state.bedtime_until is not None and now >= state.bedtime_until)
            schedule_changed = scheduled_dark(now) != status["scheduled_dark"]
            if (
                events != signature
                or due
                or schedule_changed
                or time.monotonic() - last >= 5
            ):
                status = reconcile()
                signature = events
                last = time.monotonic()
            try:
                connection, _ = server.accept()
            except TimeoutError:
                continue
            with connection:
                connection.settimeout(1)
                try:
                    _, uid, _ = struct.unpack(
                        "3i",
                        connection.getsockopt(
                            socket.SOL_SOCKET, socket.SO_PEERCRED, 12
                        ),
                    )
                    action = connection.recv(64).decode().strip()
                    if uid not in [0, authorized_uid]:
                        raise PermissionError("unauthorized peer uid")
                    if action == "reconcile" and uid == 0:
                        result = reconcile()
                    elif action in ACTIONS:
                        result = reconcile(action)
                    else:
                        raise ValueError(
                            "only away, bedtime, wake and resume-schedule are authorized"
                        )
                except (OSError, ValueError, RuntimeError) as error:
                    result = {"error": str(error)}
                if "error" not in result:
                    status = result
                try:
                    connection.sendall((json.dumps(result) + "\n").encode())
                except OSError:
                    logging.info("request peer disconnected before receiving status")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="/etc/homelab/display-policy.json")
    parser.add_argument("action", choices=(*ACTIONS, "serve", "reconcile", "gate"))
    args = parser.parse_args()
    config = json.loads(Path(args.config).read_text())
    logging.basicConfig(level=logging.INFO)
    if args.action == "serve":
        serve(config)
    elif args.action == "gate":
        try:
            sys.exit(0 if producer_permitted(config) else 1)
        except (OSError, ValueError, TypeError, RuntimeError):
            sys.exit(1)
    else:
        print(json.dumps(request(config, args.action)))


if __name__ == "__main__":
    main()
