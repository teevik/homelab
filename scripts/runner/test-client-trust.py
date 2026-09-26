"""Replay real upstream-signed metadata against the native client's configuration."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import threading

metadata = Path(__file__).with_name("fixtures").joinpath("numtide.narinfo").read_bytes()
store_path = next(line.split(": ", 1)[1] for line in metadata.decode().splitlines()
                  if line.startswith("StorePath: "))


class Handler(BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        if self.path == "/nix-cache-info":
            body = b"StoreDir: /nix/store\nWantMassQuery: 1\nPriority: 20\n"
        elif self.path == "/" + Path(store_path).name[:32] + ".narinfo":
            body = metadata
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command == "GET":
            self.wfile.write(body)

    def log_message(self, *_):
        pass


with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    try:
        # This is the same verification used after native cache publication.
        # ncps preserves upstream signatures, so trusting only Harmonia fails.
        subprocess.run([
            "nix", "store", "verify", "--store", f"http://127.0.0.1:{server.server_port}",
            "--no-contents", "--sigs-needed", "1", "--option", "extra-trusted-public-keys",
            "homelab-cache-1:e0A0wubKr+XqKPA/MeUY5ixaG+1HvBBImTkPzrNJT4s=", store_path,
        ], check=True)
    finally:
        server.shutdown()
        worker.join()
