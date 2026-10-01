"""Run the real collector against fixture HTTP APIs; consume its public snapshot."""
import json
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

mode = "multiple-evaluators"
evaluator_value = 1
stamp = time.time()
boot_id = Path("/proc/sys/kernel/random/boot_id").read_text().strip()


def row(metric_name, value, **labels):
    return {"metric": {"__name__": metric_name, **labels}, "value": [time.time(), str(value)]}


def metrics():
    rows = [row("up", 1, job=job) for job in ["kube-state-metrics", "argocd-application-controller-metrics", "vmalert-vm-victoria-metrics-k8s-stack"]]
    if mode == "multiple-evaluators":
        rows += [row("vmalert_iteration_total", evaluator_value, group=group) for group in ["first", "second"]]
    else:
        rows += [row("vmalert_iteration_total", 10 + int(time.time()), group="test")]
    for identity in ["immich", "immich-share", "nix-cache"]:
        failed = mode == "failure" and identity == "immich"
        rows += [row("up", 0 if mode == "failed-scrape" and identity == "immich" else 1, job="dashboard-http", service_id=identity), row("probe_success", int(not failed), service_id=identity), row("probe_duration_seconds", .04, service_id=identity), row("probe_http_status_code", 503 if failed else 200, service_id=identity)]
    for app in ["immich", "cloudflare-tunnel"]:
        rows += [row("argocd_app_info", 1, name=app, sync_status="Synced", health_status="Degraded" if mode == "degraded" and app == "immich" else "Healthy")]
    rows += [row("kube_pod_info", 1, namespace="immich", pod="server"), row("kube_pod_status_phase", 1, namespace="immich", pod="server", phase="Succeeded" if mode == "completed" else "Running"), row("kube_pod_status_ready", 1, namespace="immich", pod="server", condition="false" if mode in ["workloads", "completed"] else "true"), row("kube_pod_container_status_restarts_total", 2 if mode in ["workloads", "completed"] else 0, namespace="immich", pod="server", container="server")]
    if mode == "empty":
        return []
    return [r for r in rows if mode != "missing" or r["metric"]["__name__"] != "probe_success"]


class API(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.headers.get("Authorization") != "Bearer disposable":
            self.send_response(401)
            self.end_headers()
            return
        if mode in ["offline", "forbidden"]:
            self.send_response(403 if mode == "forbidden" else 503)
            self.end_headers()
            return
        if mode == "timeout":
            time.sleep(5)
        query = parse_qs(urlsplit(self.path).query).get("query", [""])[0]
        rows = metrics()
        if query.startswith("timestamp("):
            for r in rows:
                r["value"][1] = str(stamp if mode == "stale" or (mode == "one-old-series" and r["metric"]["__name__"] == "probe_duration_seconds" and r["metric"].get("service_id") == "immich") else time.time())
            if mode == "missing-timestamp":
                rows = [r for r in rows if r["metric"]["__name__"] != "probe_duration_seconds"]
        elif query.startswith("round("):
            rows = [] if mode == "missing-restarts" else [row("restarts", 2 if mode in ["workloads", "completed"] else 0, namespace="immich", pod="server", container="server")]
        alerts = []
        if mode == "alerts":
            for name, namespace, state in [("StorageDown", "immich", "active"), ("ClusterAlert", "kube-system", "active"), ("Watchdog", "immich", "active"), ("InfoInhibitor", "immich", "active"), ("Silenced", "immich", "suppressed")]:
                alerts.append({"labels": {"alertname": name, "namespace": namespace}, "status": {"state": state, "silencedBy": [], "inhibitedBy": []}, "startsAt": datetime.fromtimestamp(time.time() - 30, timezone.utc).isoformat(), "endsAt": datetime.fromtimestamp(time.time() + 300, timezone.utc).isoformat()})
        body = alerts if "/alerts" in self.path else {"status": "success", "data": {"resultType": "vector", "result": rows}}
        if mode == "malformed":
            body = {"wrong": "contract"}
        self.send_response(200)
        self.end_headers()
        try:
            self.wfile.write(json.dumps(body).encode())
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, *_):
        pass


with ThreadingHTTPServer(("127.0.0.1", 0), API) as api, tempfile.TemporaryDirectory() as temporary:
    threading.Thread(target=api.serve_forever, daemon=True).start()
    directory = Path(temporary)
    credential = directory / "credential.json"
    credential.write_text(json.dumps({"token": "disposable"}))
    (directory / "catalog.json").write_text(json.dumps({"version": 1, "endpoints": [{"id": "immich", "name": "Immich", "app": "immich"}, {"id": "immich-share", "name": "Immich Share", "app": "immich"}, {"id": "nix-cache", "name": "Nix Cache"}], "apps": ["immich", "cloudflare-tunnel"]}))
    policy = directory / "policy.json"
    config = {"catalog": str(directory / "catalog.json"), "snapshot": str(directory / "snapshot.json"), "state": str(directory / "state.json"), "credential": str(credential), "metrics_url": f"http://127.0.0.1:{api.server_port}/query", "alerts_url": f"http://127.0.0.1:{api.server_port}/alerts", "host_interval_ms": 250, "cluster_interval_ms": 200, "namespaces": {"immich": "immich", "cloudflare-tunnel": "cloudflare-tunnel"}, "controller_report": str(policy), "night": str(directory / "night.json")}
    (directory / "config.json").write_text(json.dumps(config))
    process = subprocess.Popen([sys.argv[1], "--config", str(directory / "config.json")], stderr=subprocess.PIPE)

    def wait(predicate):
        until = time.monotonic() + 8
        while time.monotonic() < until:
            if process.poll() is not None:
                raise AssertionError(process.stderr.read().decode())
            try:
                snapshot = json.loads((directory / "snapshot.json").read_text())
                if predicate(snapshot):
                    return snapshot
            except (FileNotFoundError, json.JSONDecodeError):
                pass
            time.sleep(.05)
        raise AssertionError(json.dumps(snapshot, indent=2))

    def frontend(status, signals=None):
        if len(sys.argv) > 2:
            view = json.loads(subprocess.check_output([sys.argv[2], str(directory / "catalog.json"), str(directory / "snapshot.json")]))
            assert view["status"] == status, view
            assert "Immich" in view["frame"]
            if signals is not None:
                assert view["signals"] == signals, view

    def replace_credential(token):
        replacement = credential.with_suffix(".new")
        replacement.write_text(json.dumps({"token": token}))
        replacement.replace(credential)

    try:
        initial = wait(lambda s: s["sources"]["host"]["newest_sample_at"] is not None)
        assert initial["host"]["cpu_percent"] is None, "CPU must await the second real sample"
        wait(lambda s: "waiting for observed evaluator progress" in (s["sources"]["alerts"]["failure"] or {}).get("reason", ""))
        # Both groups advance once after the same first observation. Collection
        # must not require another evaluation from a group it skipped at startup.
        evaluator_value = 2
        healthy = wait(lambda s: s["endpoints"].get("immich", {}).get("result") == "ok" and s["host"]["cpu_percent"] is not None and s["sources"]["alerts"]["failure"] is None and s["sources"]["alerts"]["newest_sample_at"] is not None)
        frontend("all-clear")
        mode = "healthy"
        assert healthy["host"]["root"]["total_bytes"] > 0
        policy.write_text(json.dumps({"version": 1, "boot_id": boot_id, "observed_at": time.time(), "schedule_until": time.time() + 3600, "bedtime_until": None, "wake_until": None, "scheduled_dark": False, "application": "applied", "failures": []}))
        wait(lambda s: (directory / "night.json").exists())
        assert json.loads((directory / "night.json").read_text())["mode"] == "day"
        report = json.loads(policy.read_text())
        report["observed_at"] = time.time() - 16
        policy.write_text(json.dumps(report))
        wait(lambda s: not (directory / "night.json").exists())
        report["observed_at"] = time.time()
        report["boot_id"] = "previous-boot"
        policy.write_text(json.dumps(report))
        wait(lambda s: not (directory / "night.json").exists())
        report["boot_id"] = boot_id
        report["application"] = "failed"
        report["failures"] = ["panel control unavailable"]
        policy.write_text(json.dumps(report))
        wait(lambda s: (directory / "night.json").exists())
        assert json.loads((directory / "night.json").read_text())["failure"]["reason"] == "panel control unavailable"
        policy.unlink()
        wait(lambda s: not (directory / "night.json").exists())
        for invalid in ["empty", "forbidden", "missing-timestamp", "failed-scrape", "one-old-series"]:
            mode = invalid
            stamp = time.time() - 240
            broken = wait(lambda s: s["sources"]["http"]["failure"] is not None or s["endpoints"]["immich"]["observed_at"] < healthy["endpoints"]["immich"]["observed_at"])
            frontend("unknown")
            assert not broken["recoveries"], "missing evidence must not manufacture recovery"
            mode = "healthy"
            wait(lambda s: s["sources"]["http"]["failure"] is None and s["endpoints"]["immich"]["observed_at"] > healthy["endpoints"]["immich"]["observed_at"])
        mode = "failure"
        failed = wait(lambda s: s["endpoints"]["immich"]["result"] == "fail")
        frontend("attention")
        mode = "offline"
        outage = wait(lambda s: s["sources"]["http"]["failure"] is not None)
        assert outage["endpoints"]["immich"]["result"] == "fail"
        assert not outage["recoveries"]
        frontend("attention")
        host_time = outage["sources"]["host"]["newest_sample_at"]
        wait(lambda s: s["sources"]["host"]["newest_sample_at"] != host_time)
        # Collector restart retains a known signal/onset outside the renderer lifetime.
        process.terminate()
        process.wait(timeout=5)
        process = subprocess.Popen([sys.argv[1], "--config", str(directory / "config.json")], stderr=subprocess.PIPE)
        restarted = wait(lambda s: s["collector_started_at"] != failed["collector_started_at"])
        assert restarted["endpoints"]["immich"]["since"] == failed["endpoints"]["immich"]["since"]
        mode = "healthy"
        returned = wait(lambda s: s["sources"]["http"]["failure"] is None and bool(s["recoveries"]))
        assert returned["recoveries"][0]["service"] == "immich"
        credential.write_text(json.dumps({"token": "expired"}))
        wait(lambda s: s["sources"]["argo"]["failure"] is not None)
        frontend("unknown")
        replace_credential("disposable")
        wait(lambda s: s["sources"]["argo"]["failure"] is None)
        mode = "degraded"
        wait(lambda s: s["apps"]["immich"]["health"] == "Degraded")
        frontend("attention", 1)  # shared app counted once, host-only endpoint independent
        mode = "workloads"
        wait(lambda s: len(s["workloads"]) == 2)
        frontend("attention", 2)
        mode = "missing-restarts"
        wait(lambda s: "one-hour restart observation absent" in (s["sources"]["argo"]["failure"] or {}).get("reason", ""))
        assert any(w["problem"] == "restarts" for w in json.loads((directory / "snapshot.json").read_text())["workloads"])
        frontend("attention", 2)
        mode = "completed"
        wait(lambda s: not s["workloads"])
        frontend("all-clear", 0)
        mode = "alerts"
        active = wait(lambda s: len(s["alerts"]) == 2)
        assert {a["name"] for a in active["alerts"]} == {"StorageDown", "ClusterAlert"}
        assert any(a["label"] == "kube-system" for a in active["alerts"])
        frontend("attention", 2)
        mode = "healthy"
        wait(lambda s: not s["alerts"])
        mode = "malformed"
        wait(lambda s: s["sources"]["argo"]["failure"] is not None)
        frontend("unknown")
        mode = "healthy"
        wait(lambda s: s["sources"]["argo"]["failure"] is None)
        credential.unlink()
        wait(lambda s: "credential unavailable" in (s["sources"]["argo"]["failure"] or {}).get("reason", ""))
        replace_credential("disposable")
        wait(lambda s: s["sources"]["argo"]["failure"] is None)
        mode = "timeout"
        wait(lambda s: s["sources"]["argo"]["failure"] is not None)
        host_time = json.loads((directory / "snapshot.json").read_text())["sources"]["host"]["newest_sample_at"]
        wait(lambda s: s["sources"]["host"]["newest_sample_at"] != host_time)
        mode = "healthy"
        wait(lambda s: s["sources"]["argo"]["failure"] is None)
        mode = "missing"
        wait(lambda s: s["sources"]["http"]["failure"] is not None)
        frontend("unknown")
        mode = "stale"
        stamp = time.time() - 240
        wait(lambda s: s["sources"]["http"]["failure"] is None and s["endpoints"]["immich"]["observed_at"] < healthy["endpoints"]["immich"]["observed_at"])
        frontend("unknown")
        assert "disposable" not in (directory / "snapshot.json").read_text()
        print("collector API/snapshot: retention, recovery, renewal, age and local continuity passed")
    finally:
        process.terminate()
        process.wait(timeout=5)
