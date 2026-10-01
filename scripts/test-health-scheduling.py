"""Real default 5s host / 30s cluster scheduling, with a slow API boundary."""
import json
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

polls = []


class API(BaseHTTPRequestHandler):
    def do_GET(self):
        query = parse_qs(urlsplit(self.path).query).get('query', [''])[0]
        if query.startswith('{'):
            polls.append(time.monotonic())
        # Each of the four requests waits, through curl, while host sampling runs.
        time.sleep(2)
        body = [] if self.path.startswith('/alerts') else {'status': 'success', 'data': {'resultType': 'vector', 'result': []}}
        self.send_response(200)
        self.end_headers()
        self.wfile.write(json.dumps(body).encode())

    def log_message(self, *_):
        pass


with tempfile.TemporaryDirectory() as temporary, ThreadingHTTPServer(('127.0.0.1', 0), API) as api:
    threading.Thread(target=api.serve_forever, daemon=True).start()
    root = Path(temporary)
    (root / 'catalog.json').write_text(json.dumps({'version': 1, 'endpoints': [], 'apps': []}))
    (root / 'credential.json').write_text(json.dumps({'token': 'disposable'}))
    (root / 'config.json').write_text(json.dumps({
        **{name: str(root / (name + '.json')) for name in ['catalog', 'credential', 'snapshot', 'state']},
        'metrics_url': f'http://127.0.0.1:{api.server_port}/query',
        'alerts_url': f'http://127.0.0.1:{api.server_port}/alerts', 'namespaces': {},
        # Deliberately omit both sampling settings: test the production defaults.
    }))
    process = subprocess.Popen([sys.argv[1], '--config', str(root / 'config.json')], stderr=subprocess.PIPE)
    samples = []
    cpu = []
    until = time.monotonic() + 50
    try:
        while time.monotonic() < until and len(polls) < 2:
            assert process.poll() is None, process.stderr.read().decode() if process.poll() is not None else ''
            try:
                snapshot = json.loads((root / 'snapshot.json').read_text())
                stamp = snapshot['sources']['host']['newest_sample_at']
                if stamp and (not samples or stamp != samples[-1]):
                    samples.append(stamp)
                    cpu.append(snapshot['host']['cpu_percent'])
            except (FileNotFoundError, json.JSONDecodeError):
                pass
            time.sleep(.02)
        assert len(polls) == 2, polls
        assert 29.5 <= polls[1] - polls[0] < 45, polls
        assert len(samples) >= 5, samples
        intervals = [(datetime.fromisoformat(b) - datetime.fromisoformat(a)).total_seconds() for a, b in zip(samples, samples[1:])]
        assert all(4.9 <= interval < 10 for interval in intervals), intervals
        assert cpu[0] is None and all(value is not None for value in cpu[1:]), cpu
        print('production 5s host / 30s cluster scheduling and independent slow-API sampling passed')
    finally:
        process.terminate()
        process.wait(timeout=5)
