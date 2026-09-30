"""THROWAWAY: serve only this fixture-only display study on loopback."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

folder = Path(__file__).resolve().parent
print("Display studies: http://127.0.0.1:8765/?variant=A", flush=True)
ThreadingHTTPServer(("127.0.0.1", 8765), partial(SimpleHTTPRequestHandler, directory=folder)).serve_forever()
