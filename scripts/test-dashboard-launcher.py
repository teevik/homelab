"""Real foreground launcher in a PTY; forced child death still restores the shell."""
import errno
import fcntl
import os
import pty
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
from pathlib import Path


def run(renderer, args=(), interrupt=False, expect=0, raw_ctrl_c=False, kill_renderer=False, panic=False):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 160, 0, 0))
    before = termios.tcgetattr(slave)

    def session():
        os.setsid()
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)

    process = subprocess.Popen([sys.argv[1], *args], stdin=slave, stdout=slave, stderr=slave, env={**os.environ, "TERM": "linux", "DASHBOARD_RENDERER": renderer, "HEALTH_DASHBOARD_TEST_PANIC": "1" if panic else ""}, preexec_fn=session)
    output = b""
    sent = False
    frame_at = None
    quiet_size = None
    killed = set()
    deadline = time.monotonic() + 10
    try:
        while time.monotonic() < deadline:
            if select.select([master], [], [], .05)[0]:
                try:
                    output += os.read(master, 65536)
                except OSError as e:
                    if e.errno != errno.EIO:
                        raise
            if interrupt and b"Retrying" in output and not sent:
                os.write(master, b"\x03")
                sent = True
            if raw_ctrl_c and b"\x1b]Pfcdd6f4" in output and frame_at is None:
                os.write(master, b"q")
                frame_at = time.monotonic()
            if kill_renderer and b"\x1b]Pfcdd6f4" in output:
                children = Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().split()
                for child_pid in map(int, children):
                    if child_pid not in killed:
                        os.kill(child_pid, signal.SIGKILL)
                        killed.add(child_pid)
            if frame_at is not None and time.monotonic() - frame_at > .3 and quiet_size is None:
                quiet_size = len(output)
            if frame_at is not None and time.monotonic() - frame_at > 2 and not sent:
                assert len(output) == quiet_size, "no per-second animation or redraw for ignored q"

                assert process.poll() is None, "q must leave the actual renderer running"
                os.write(master, b"\x03")
                sent = True
            if process.poll() is not None:
                break
        assert process.poll() is not None, output
        assert process.returncode == expect, (process.returncode, output)
        assert termios.tcgetattr(slave) == before, "entire pre-launch termios must be restored"
        assert b"\x1b]R" in output and b"\x1b[?25h" in output and b"\x1b[?1049l" in output
        # Exercise actual canonical shell input and echo after the handoff.
        shell = subprocess.Popen(["/bin/sh", "-c", "read line; printf 'shell-read:%s\n' \"$line\""], stdin=slave, stdout=slave, stderr=slave)
        os.write(master, b"shell-usable\n")
        shell.wait(timeout=3)
        shell_output = b""
        while select.select([master], [], [], .1)[0]:
            shell_output += os.read(master, 65536)
        assert b"shell-usable" in shell_output and b"shell-read:shell-usable" in shell_output, shell_output
        return output
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
        os.close(slave)


with tempfile.TemporaryDirectory() as directory:
    child = Path(directory) / "broken-renderer"
    child.write_text("#!/bin/sh\nstty -echo -icanon\nprintf '\\033]P0ffffff'\nkill -KILL $$\n")
    child.chmod(0o755)
    exhausted = run(str(child), expect=1)
    assert exhausted.count(b"Retrying") == 2, exhausted
    assert b"Run dashboard to open it again." in exhausted
    cancelled = run(str(child), interrupt=True)
    assert cancelled.count(b"Retrying") == 1, cancelled
    assert b"Dashboard closed." in cancelled
    # The actual renderer's raw Ctrl+C behavior is also checked by tests/terminal.rs.
    clean = Path(directory) / "clean-renderer"
    clean.write_text("#!/bin/sh\nstty -echo -icanon\nexit 0\n")
    clean.chmod(0o755)
    assert b"Dashboard closed." in run(str(clean))
    assert b"Dashboard closed." in run(str(clean)), "manual relaunch"
    if len(sys.argv) > 2:
        runtime_error = run(sys.argv[2], ["--catalog", "/absent", "--snapshot", "/absent", "--night", "/absent"], expect=1)
        assert runtime_error.count(b"Retrying") == 2
        killed_output = run(sys.argv[2], ["demo", "normal"], expect=1, kill_renderer=True)
        assert killed_output.count(b"Retrying") == 2
        for _ in range(2):
            actual = run(sys.argv[2], ["demo", "normal"], raw_ctrl_c=True)
            assert actual.count(b"Dashboard closed.") == 1
            assert b"Retrying" not in actual
    if len(sys.argv) > 3:
        assert b"injected renderer panic" not in run(sys.argv[2], ["demo", "normal"], raw_ctrl_c=True, panic=True)
        panicked = run(sys.argv[3], ["demo", "normal"], expect=1, panic=True)
        assert panicked.count(b"injected renderer panic") == 3, panicked
        assert panicked.count(b"\x1b]R") >= 6, "child panic hook and launcher both reset the palette"
print("launcher PTY: forced kill, bounded retry, cancellation and relaunch passed")
