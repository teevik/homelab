"""Pinned native Glance and blackbox requests share the catalog's HTTP semantics."""
import copy
import json
import os
import re
import ssl
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import URLError
from urllib.parse import urlencode
from urllib.request import urlopen


class API(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/slow":
            time.sleep(2)
        status = {"/auth": 401, "/forbidden": 403, "/accepted": 202, "/redirect": 302}.get(self.path, 200)
        self.send_response(status)
        if status == 302:
            self.send_header("Location", "/ok")
        self.end_headers()

    def log_message(self, *_):
        pass


def get(url):
    with urlopen(url, timeout=8) as response:
        return response.read().decode()


def port():
    with ThreadingHTTPServer(("127.0.0.1", 0), API) as server:
        return server.server_port


def ready(process, url):
    for _ in range(100):
        try:
            return get(url)
        except (URLError, ConnectionError):
            assert process.poll() is None, "HTTP consumer died during startup"
            time.sleep(.05)
    raise AssertionError("HTTP consumer did not start")


with tempfile.TemporaryDirectory() as temporary, ThreadingHTTPServer(("127.0.0.1", 0), API) as http, ThreadingHTTPServer(("127.0.0.1", 0), API) as https:
    directory = Path(temporary)
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-keyout", str(directory / "key.pem"), "-out", str(directory / "ca.pem"), "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(directory / "ca.pem", directory / "key.pem")
    https.socket = context.wrap_socket(https.socket, server_side=True)
    for server in [http, https]:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    consumers = json.loads(Path(sys.argv[3]).read_text())
    module = consumers["blackbox"]["modules"]["glance"]
    glance = consumers["glance"][0]
    base = f"http://127.0.0.1:{http.server_port}"
    cases = [("ok", base + "/ok", True, {}), ("redirect", base + "/redirect", True, {}), ("auth", base + "/auth", False, {}), ("forbidden", base + "/forbidden", False, {}), ("unexpected", base + "/accepted", False, {}), ("override", base + "/accepted", True, {"statuses": [200, 202]}), ("timeout", base + "/slow", False, {"timeout": "1s"}), ("tls", f"https://localhost:{https.server_port}/ok", True, {}), ("invalid-tls", f"https://127.0.0.1:{https.server_port}/ok", False, {}), ("untrusted", f"https://localhost:{https.server_port}/ok", False, {"untrusted": True})]
    modules, sites = {}, []
    for name, target, healthy, override in cases:
        m, site = copy.deepcopy(module), copy.deepcopy(glance)
        site.update({"title": name, "url": target, "check-url": target, "icon": "", "alt-status-codes": [code for code in override.get("statuses", [200]) if code != 200]})
        m["http"]["valid_status_codes"] = override.get("statuses", [200])
        if "timeout" in override:
            m["timeout"] = site["timeout"] = override["timeout"]
        if name != "untrusted":
            m["http"]["tls_config"]["ca_file"] = str(directory / "ca.pem")
        modules[name] = m
        if name != "untrusted":
            sites.append(site)
    blackbox_port, glance_port = port(), port()
    (directory / "blackbox.json").write_text(json.dumps({"modules": modules}))
    (directory / "glance.json").write_text(json.dumps({"server": {"host": "127.0.0.1", "port": glance_port}, "pages": [{"name": "Checks", "columns": [{"size": "full", "widgets": [{"type": "monitor", "sites": sites}]}]}]}))
    with (directory / "blackbox.log").open("w+") as bb_log, (directory / "glance.log").open("w+") as gl_log:
        blackbox = subprocess.Popen([sys.argv[2], "--config.file=" + str(directory / "blackbox.json"), "--web.listen-address=127.0.0.1:" + str(blackbox_port)], stdout=bb_log, stderr=bb_log)
        glance_process = subprocess.Popen([sys.argv[1], "--config", str(directory / "glance.json")], env={**os.environ, "SSL_CERT_FILE": str(directory / "ca.pem")}, stdout=gl_log, stderr=gl_log)
        try:
            ready(blackbox, f"http://127.0.0.1:{blackbox_port}/-/healthy")
            ready(glance_process, f"http://127.0.0.1:{glance_port}/api/healthz")
            html = get(f"http://127.0.0.1:{glance_port}/api/pages/checks/content/")
            blocks = html.split('<div class="monitor-site flex items-center gap-15">')[1:]
            assert len(blocks) == len(sites), html
            for (name, target, healthy, _), block in zip(cases[:-1], blocks, strict=True):
                output = get(f"http://127.0.0.1:{blackbox_port}/probe?" + urlencode({"target": target, "module": name}))
                assert re.search(r"^probe_success " + str(int(healthy)) + r"$", output, re.M), (name, output)
                assert ('fill="var(--color-positive)"' in block) == healthy, (name, block)
            invalid = get(f"http://127.0.0.1:{blackbox_port}/probe?" + urlencode({"target": cases[-1][1], "module": "untrusted"}))
            assert re.search(r"^probe_success 0$", invalid, re.M)
            print("pinned Glance/blackbox: GET, redirects, TLS, auth, timeout and overrides passed")
        finally:
            if glance_process.poll() is not None:
                gl_log.seek(0)
                print(gl_log.read())
            if blackbox.poll() is not None:
                bb_log.seek(0)
                print(bb_log.read())
            for process in [glance_process, blackbox]:
                process.terminate()
                process.wait(timeout=5)
