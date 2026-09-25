"""Credential-free, bounded publication API on a permission-restricted Unix socket."""

import importlib.util
import json
import os
from pathlib import Path
import sys
import time


def handle(cache, config, request, pending):
    operation = request.get("operation")
    if operation == "publish":
        return cache.publish(config, request["host"], request["generation"], request["path"])
    if operation == "retain":
        return cache.retain_dependencies(config, request["group"], request["generation"], request["paths"])
    if operation == "flush":
        # Only the CI daemon can enqueue paths. Never accept a queue directory,
        # command, configuration, environment or arbitrary filename from clients.
        paths = sorted(p for p in pending.iterdir() if p.is_symlink())
        count = 0
        for offset in range(0, len(paths), 256):
            batch = paths[offset:offset + 256]
            cache.retain_dependencies(config, "bootstrap", time.strftime("native-%Y-%m-%d"),
                                      [os.readlink(path) for path in batch])
            for path in batch:
                path.unlink(missing_ok=True)
            count += len(batch)
        return {"retainedOutputs": count}
    raise ValueError("Unsupported local cache operation")


def main():
    spec = importlib.util.spec_from_file_location("cache", sys.argv[1])
    cache = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cache)
    config = json.loads(Path(sys.argv[2]).read_text())
    for name in list(os.environ):
        if name.startswith("NIX_"):
            del os.environ[name]
    os.environ["NIX_REMOTE"] = "daemon"
    try:
        payload = sys.stdin.buffer.read(8 * 1024 * 1024 + 1)
        if len(payload) > 8 * 1024 * 1024:
            raise ValueError("Request too large")
        result = handle(cache, config, json.loads(payload), Path(sys.argv[3]))
        print(json.dumps({"result": result}), flush=True)
    except Exception:
        # Requests may contain attacker-controlled strings; don't echo them or
        # subprocess diagnostics into an HTTP-style response or public job log.
        print(json.dumps({"error": "Local cache request failed"}), flush=True)
        raise


if __name__ == "__main__":
    main()
