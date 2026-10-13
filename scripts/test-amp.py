#!/usr/bin/env python3
"""Exercise AMP's supervisor with real signals and a fixture instance manager."""

import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest


ENTRYPOINT = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else Path('images/amp/entrypoint.py')

# The external manager fixture starts a detached game whose unsaved state only
# reaches disk during a graceful stop. No production AMP data or licence is used.
MANAGER = '''#!/usr/bin/env python3
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

root = Path(os.environ['AMP_TEST_ROOT'])
operation = next(arg for arg in sys.argv[1:] if not arg.startswith('--'))
if operation == 'QuickStart':
    signal.signal(signal.SIGTERM, lambda *_: None)
    (root / 'manager-running').touch()
    time.sleep(0.5)
    game = subprocess.Popen([sys.executable, str(root / 'game.py')],
                            cwd=root / 'instances' / 'Minecraft01', start_new_session=True)
    if (root / 'stop-started').exists():
        (root / 'created-after-stop').touch()
    (root / 'game.pid').write_text(str(game.pid))
elif operation == 'UpgradeInstance':
    if os.environ.get('AMP_TEST_UPGRADE_FAIL') == '1':
        print('password=fixture-secret')
        sys.exit(37)
    (root / 'controller-upgraded').touch()
elif operation == 'StartBoot':
    game = subprocess.Popen([sys.executable, str(root / 'game.py')],
                            cwd=root / 'instances' / 'Minecraft01',
                            start_new_session=True)
    (root / 'game.pid').write_text(str(game.pid))
    while not (root / 'game-running').exists():
        time.sleep(0.01)
    (root / 'manager-running').touch()
    if os.environ.get('AMP_TEST_BUSY') == '1':
        if os.environ.get('AMP_TEST_RESISTANT_CHILD') == '1':
            child = subprocess.Popen([sys.executable, '-c',
                'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)'])
            (root / 'maintenance.pid').write_text(str(child.pid))
            time.sleep(0.1)
        while True:
            time.sleep(1)
elif operation == 'StopAll':
    (root / 'stop-started').touch()
    if not (root / 'game.pid').exists():
        sys.exit(0)
    pid = int((root / 'game.pid').read_text())
    os.kill(pid, signal.SIGTERM)
    if os.environ.get('AMP_TEST_STOP_EARLY') != '1':
        while not (root / 'world').exists():
            time.sleep(0.01)
'''

GAME = '''import os
from pathlib import Path
import signal
import time

root = Path(os.environ['AMP_TEST_ROOT'])
def stop(*_):
    if os.environ.get('AMP_TEST_HANG_GAME') == '1':
        return
    time.sleep(float(os.environ.get('AMP_TEST_SAVE_DELAY', '0.1')))
    (root / 'world').write_text('saved block at 12,64,9')
    raise SystemExit(0)
signal.signal(signal.SIGTERM, stop)
(root / 'game-running').touch()
while True:
    time.sleep(1)
'''

RUNNER = '''import importlib.util
from pathlib import Path
import os
import sys

spec = importlib.util.spec_from_file_location('amp_entrypoint', sys.argv[1])
amp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(amp)
root = Path(os.environ['AMP_TEST_ROOT'])
# Redirect only filesystem boundaries; all supervisor logic runs unchanged.
amp.STATE = root / 'state'
amp.READY = root / 'ready'
amp.SECRETS = root / 'secrets'
amp.INSTANCES = root / 'instances'
amp.API.__init__.__defaults__ = (os.environ['AMP_TEST_API_URL'], None)
try:
    amp.main()
except Exception as error:
    print(amp.safe_error(error), file=sys.stderr)
    sys.exit(1)
'''


class ShutdownTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='amp-shutdown-')
        self.root = Path(self.directory.name)
        self.addCleanup(self.directory.cleanup)
        (self.root / 'instances' / 'Minecraft01').mkdir(parents=True)
        (self.root / 'state').mkdir()
        for marker in ['standalone', 'licensed', 'ads-shutdown-fixes']:
            (self.root / 'state' / marker).touch()
        # Existing-controller check in the production startup path.
        (self.root / 'instances' / 'ADS01').mkdir()
        (self.root / 'instances' / 'ADS01' / 'AMPConfig.conf').touch()
        (self.root / 'secrets').mkdir()
        (self.root / 'secrets' / 'AMP_ADMIN_PASSWORD').write_text('fixture-secret')
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        manager = self.bin / 'ampinstmgr'
        manager.write_text(MANAGER.replace('#!/usr/bin/env python3', '#!' + sys.executable))
        manager.chmod(0o755)
        (self.root / 'game.py').write_text(GAME)
        (self.root / 'runner.py').write_text(RUNNER)
        root = self.root

        class APIHandler(BaseHTTPRequestHandler):
            def do_POST(self):
                self.rfile.read(int(self.headers['Content-Length']))
                result = True
                if self.path.endswith('/Core/Login'):
                    result = {'sessionID': 'fixture' if (root / 'game-running').exists() else None}
                self.send_response(200)
                self.end_headers()
                self.wfile.write(json.dumps(result).encode())

            def log_message(self, *_):
                pass

        self.api = ThreadingHTTPServer(('127.0.0.1', 0), APIHandler)
        threading.Thread(target=self.api.serve_forever, daemon=True).start()
        self.addCleanup(self.api.server_close)
        self.addCleanup(self.api.shutdown)
        self.process = None
        self.addCleanup(self.cleanup_processes)

    def cleanup_processes(self):
        if self.process and self.process.poll() is None:
            os.killpg(self.process.pid, signal.SIGKILL)
            self.process.wait()
        if self.process:
            self.process.communicate()
        for name in ['game.pid', 'maintenance.pid']:
            pidfile = self.root / name
            if pidfile.exists():
                try:
                    os.kill(int(pidfile.read_text()), signal.SIGKILL)
                except ProcessLookupError:
                    pass

    def start(self, wait=True, **environment):
        self.process = subprocess.Popen(
            [sys.executable, '-u', str(self.root / 'runner.py'), str(ENTRYPOINT.resolve())],
            env={**os.environ, 'PATH': str(self.bin) + ':' + os.environ['PATH'],
                 'AMP_TEST_ROOT': str(self.root),
                 'AMP_TEST_API_URL': f'http://127.0.0.1:{self.api.server_port}/', **environment},
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            start_new_session=True,
        )
        if wait:
            self.wait_for('manager-running')

    def wait_for(self, name, timeout=3):
        deadline = time.monotonic() + timeout
        while not (self.root / name).exists():
            if time.monotonic() >= deadline:
                self.fail(f'{name} was not reached before the deadline')
            time.sleep(0.01)

    def test_busy_startup_does_not_delay_saving_on_termination(self):
        self.start(AMP_TEST_BUSY='1')
        self.process.send_signal(signal.SIGTERM)
        self.wait_for('stop-started', timeout=2)
        output, _ = self.process.communicate(timeout=3)
        self.assertEqual(self.process.returncode, 0, output)
        self.assertIn('no instance processes remain', output)
        self.assertEqual((self.root / 'world').read_text(), 'saved block at 12,64,9')

    def test_stopall_returning_early_does_not_discard_an_in_progress_save(self):
        self.start(AMP_TEST_STOP_EARLY='1', AMP_TEST_SAVE_DELAY='0.5',
                   AMP_SHUTDOWN_TIMEOUT_SECONDS='2')
        self.wait_for('ready')
        self.process.send_signal(signal.SIGTERM)
        output, _ = self.process.communicate(timeout=3)
        self.assertEqual(self.process.returncode, 0, output)
        self.assertTrue((self.root / 'world').exists(), output)

    def test_failed_controller_upgrade_does_not_start_games_or_mark_completion(self):
        (self.root / 'state' / 'ads-shutdown-fixes').unlink()
        self.start(wait=False, AMP_TEST_UPGRADE_FAIL='1')
        output, _ = self.process.communicate(timeout=3)
        self.assertEqual(self.process.returncode, 1, output)
        self.assertFalse((self.root / 'state' / 'ads-shutdown-fixes').exists())
        self.assertFalse((self.root / 'game-running').exists())
        self.assertNotIn('fixture-secret', output)
        self.assertIn('exit code 37', output)

    def test_repeated_termination_signals_do_not_abort_a_slow_save(self):
        self.start(AMP_TEST_SAVE_DELAY='0.8', AMP_SHUTDOWN_TIMEOUT_SECONDS='2')
        self.wait_for('ready')
        self.process.send_signal(signal.SIGTERM)
        self.wait_for('stop-started')
        self.process.send_signal(signal.SIGTERM)
        output, _ = self.process.communicate(timeout=3)
        self.assertEqual(self.process.returncode, 0, output)
        self.assertEqual((self.root / 'world').read_text(), 'saved block at 12,64,9')

    def test_a_stuck_game_reports_failure_at_the_shutdown_deadline(self):
        self.start(AMP_TEST_HANG_GAME='1', AMP_TEST_STOP_EARLY='1',
                   AMP_SHUTDOWN_TIMEOUT_SECONDS='0.5')
        self.wait_for('ready')
        self.process.send_signal(signal.SIGTERM)
        output, _ = self.process.communicate(timeout=3)
        self.assertEqual(self.process.returncode, 1, output)
        self.assertIn('instance process(es) remain', output)
        self.assertNotIn('shutdown completed', output)
        self.assertFalse((self.root / 'world').exists())

    def test_existing_controller_is_upgraded_once_before_instances_start(self):
        (self.root / 'state' / 'ads-shutdown-fixes').unlink()
        self.start()
        self.assertTrue((self.root / 'controller-upgraded').exists())
        self.wait_for('ready')
        self.process.send_signal(signal.SIGTERM)
        output, _ = self.process.communicate(timeout=3)
        self.assertEqual(self.process.returncode, 0, output)

        # An ordinary restart must not download/upgrade ADS again.
        (self.root / 'controller-upgraded').unlink()
        (self.root / 'manager-running').unlink()
        self.start(AMP_TEST_UPGRADE_FAIL='1')
        self.wait_for('ready')
        self.process.send_signal(signal.SIGTERM)
        output, _ = self.process.communicate(timeout=3)
        self.assertEqual(self.process.returncode, 0, output)
        self.assertFalse((self.root / 'controller-upgraded').exists())

    def test_cold_start_cancellation_cannot_create_a_game_after_stopall(self):
        (self.root / 'instances' / 'ADS01' / 'AMPConfig.conf').unlink()
        (self.root / 'state' / 'standalone').unlink()
        self.start()
        self.process.send_signal(signal.SIGTERM)
        output, _ = self.process.communicate(timeout=5)
        self.assertEqual(self.process.returncode, 0, output)
        self.assertFalse((self.root / 'created-after-stop').exists(), output)
        if (self.root / 'game.pid').exists():
            self.assertTrue((self.root / 'world').exists(), output)

    def test_cancelling_a_manager_reaps_its_resistant_command_child(self):
        self.start(AMP_TEST_BUSY='1', AMP_TEST_RESISTANT_CHILD='1')
        self.wait_for('maintenance.pid')
        time.sleep(0.2)
        self.process.send_signal(signal.SIGTERM)
        output, _ = self.process.communicate(timeout=5)
        self.assertEqual(self.process.returncode, 0, output)
        pid = int((self.root / 'maintenance.pid').read_text())
        try:
            state = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()[0]
        except FileNotFoundError:
            return
        self.assertEqual(state, 'Z', 'maintenance child survived command cancellation')


if __name__ == '__main__':
    unittest.main()
