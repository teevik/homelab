"""Render the production templates with Glance against controlled API responses."""

import copy
import json
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def sample(value, **labels):
    return {"metric": labels, "value": [time.time(), str(value)]}


def vector(*rows):
    return {"status": "success", "data": {"resultType": "vector", "result": list(rows)}}


now = time.time()
healthy = {
    "0/sources": vector(*(sample(1, job=str(i)) for i in range(3))),
    "0/alerts": [],
    "0/apps": vector(sample(1, name="immich", health_status="Healthy", sync_status="Synced")),
    "0/inventory": vector(sample(10)),
    "0/pods": vector(),
    "0/restarts": vector(),
    "1/sources": vector(sample(1, job="storage"), sample(1, job="inventory")),
    "1/volumes": vector(sample(now - 3600, pvc="immich-library", pvc_namespace="immich")),
    "1/failures": vector(),
    "2/sources": vector(sample(1, job="node"), sample(1, job="containers")),
    "2/cpu": vector(sample(20)),
    "2/memory": vector(sample(40)),
    "2/topCPU": vector(sample(0.5, namespace="amp")),
    "2/topMemory": vector(sample(2147483648, namespace="immich")),
}
responses = copy.deepcopy(healthy)


class API(BaseHTTPRequestHandler):
    def do_GET(self):
        value = responses[self.path.split("?", 1)[0].lstrip("/")]
        self.send_response(503 if value == "offline" else 200)
        self.end_headers()
        try:
            self.wfile.write(b"offline" if value == "offline" else json.dumps(value).encode())
        except (BrokenPipeError, ConnectionResetError):
            # Glance cancels concurrent requests after the simulated outage.
            pass

    def log_message(self, *_):
        pass


def get(url):
    with urllib.request.urlopen(url, timeout=5) as response:
        return response.read().decode()


api = ThreadingHTTPServer(("127.0.0.1", 0), API)
threading.Thread(target=api.serve_forever, daemon=True).start()
config = json.loads(Path(sys.argv[2]).read_text())
widgets = next(column["widgets"] for column in config["pages"][0]["columns"] if column["size"] == "full")
assert [w["title"] for w in widgets] == ["Needs attention", "Backups", "Resource consumers"]
config = {"pages": [{"name": "Test", "columns": [{"size": "full", "widgets": widgets}]}]}
for index, widget in enumerate(widgets):
    widget["cache"] = "1s"
    for name, request in [("sources", widget), *widget["subrequests"].items()]:
        request["url"] = f"http://127.0.0.1:{api.server_port}/{index}/{name}"

try:
    with tempfile.TemporaryDirectory() as directory:
        directory = Path(directory)

        def render(overrides, present=(), absent=(), outage=False):
            responses.clear()
            responses.update(copy.deepcopy(healthy))
            responses.update(overrides)
            # Let the OS choose an available port; release it immediately before launch.
            with ThreadingHTTPServer(("127.0.0.1", 0), API) as port:
                address = port.server_port
            config["server"] = {"host": "127.0.0.1", "port": address}
            path = directory / "config.json"
            path.write_text(json.dumps(config))
            with (directory / "glance.log").open("w+") as log:
                process = subprocess.Popen([sys.argv[1], "--config", str(path)], stdout=log, stderr=log)
                try:
                    url = f"http://127.0.0.1:{address}"
                    for _ in range(100):
                        try:
                            get(url + "/api/healthz")
                            break
                        except (urllib.error.URLError, ConnectionError):
                            if process.poll() is not None:
                                log.seek(0)
                                raise AssertionError(log.read())
                            time.sleep(0.05)
                    html = get(url + "/api/pages/test/content/")
                    for value in present:
                        assert value in html, f"Missing {value!r} in {html}"
                    for value in absent:
                        assert value not in html, f"Unexpected {value!r} in {html}"
                    assert 'widget-error-header' not in html, html
                    if outage:
                        responses["0/alerts"] = "offline"
                        time.sleep(1.1)
                        html = get(url + "/api/pages/test/content/")
                        # Glance keeps cached HTML. Our stylesheet uses this marker
                        # to replace it with the explicit unavailable message.
                        assert 'notice-icon-major' in html, html
                        assert 'homelab-unavailable' in html, html
                finally:
                    process.terminate()
                    process.wait(timeout=5)

        render({}, ["All clear", "1 of 1 backups current", "20% busy", "2.0 GiB"], outage=True)
        render({
            "0/alerts": [{"annotations": {"summary": "Disk <script>full</script>"}, "labels": {"severity": "warning"}, "startsAt": "2026-09-01T00:00:00Z"}],
            "0/apps": vector(sample(1, name="immich", health_status="Degraded", sync_status="OutOfSync")),
            "0/pods": vector(sample(1, namespace="immich", pod="immich-server")),
            "0/restarts": vector(sample(3, namespace="amp", pod="amp-server")),
        }, ["4 items need attention", "Disk &lt;script&gt;full&lt;/script&gt;", "Degraded", "pod is not ready", "3 restarts"], ["All clear"])
        render({
            "1/volumes": vector(sample(-1, pvc="missing"), sample(0, pvc="never"), sample(now - 31 * 3600, pvc="late"), sample(now - 3600, pvc="current")),
            "1/failures": vector(sample(2, pvc="late")),
        }, ["1 of 4 backups current", "Unknown", "Never backed up", "Overdue", "2 failed backup records"])
        render({"1/volumes": vector()}, ["No protected volumes found"], ["backups current"])
        render({"0/sources": vector(), "1/sources": vector(sample(0), sample(1)), "2/memory": vector()},
               ["Health status unavailable", "Backup status unavailable", "Resource usage unavailable"], ["All clear", "backups current", "% busy"])
        render({"0/apps": {"status": "error", "error": "query failed"}, "1/volumes": {"status": "error"}, "2/topCPU": vector()},
               ["Health status unavailable", "Backup status unavailable", "Resource usage unavailable"], ["All clear", "backups current", "% busy"])
        render({"0/alerts": {}}, ["Health status unavailable"], ["All clear"])
        print("Glance: healthy, incident, backup, missing-data, API-error and cached-outage checks passed")
finally:
    api.shutdown()
    api.server_close()
