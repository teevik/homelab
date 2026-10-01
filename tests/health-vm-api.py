"""Disposable API boundary behind real k3s service proxies (never production data)."""
import json
import time
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

catalog = json.loads(Path('/etc/homelab/health-catalog.json').read_text())


class API(BaseHTTPRequestHandler):
    def do_GET(self):
        mode = Path('/run/health-fixture-mode').read_text().strip()
        if mode == 'offline':
            self.send_response(503)
            self.end_headers()
            return
        rows = []

        def row(metric_name, value, **labels):
            rows.append({'metric': {'__name__': metric_name, **labels}, 'value': [time.time(), str(value)]})

        for job in ['kube-state-metrics', 'argocd-application-controller-metrics', 'vmalert-vm-victoria-metrics-k8s-stack']:
            row('up', 1, job=job)
        row('vmalert_iteration_total', 100 if mode == 'frozen-evaluator' else int(time.time()), group='fixture')
        for e in catalog['endpoints']:
            failed = mode == 'failure' and e['id'] == 'glance'
            row('up', 1, job='dashboard-http', service_id=e['id'])
            row('probe_success', int(not failed), service_id=e['id'])
            row('probe_duration_seconds', .02, service_id=e['id'])
            row('probe_http_status_code', 503 if failed else 200, service_id=e['id'])
        for app in catalog['apps']:
            row('argocd_app_info', 1, name=app, sync_status='Synced', health_status='Healthy')
        row('kube_pod_info', 1, namespace='glance', pod='fixture')
        row('kube_pod_status_phase', 1, namespace='glance', pod='fixture', phase='Running')
        row('kube_pod_status_ready', 1, namespace='glance', pod='fixture', condition='true')
        row('kube_pod_container_status_restarts_total', 0, namespace='glance', pod='fixture', container='fixture')
        query = parse_qs(urlsplit(self.path).query).get('query', [''])[0]
        if query.startswith('timestamp('):
            for r in rows:
                r['value'][1] = str(time.time())
        elif query.startswith('round('):
            rows = [{'metric': {'namespace': 'glance', 'pod': 'fixture', 'container': 'fixture'}, 'value': [time.time(), '0']}]
        body = [] if '/api/v2/alerts' in self.path else {'status': 'success', 'data': {'resultType': 'vector', 'result': rows}}
        self.send_response(200)
        self.end_headers()
        self.wfile.write(json.dumps(body).encode())

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", "0")))
        self.send_response(204)
        self.end_headers()

    def log_message(self, *_):
        pass


for port in [8088, 8501]:
    server = ThreadingHTTPServer(('0.0.0.0', port), API)
    threading.Thread(target=server.serve_forever, daemon=True).start()
ThreadingHTTPServer(('0.0.0.0', 8428), API).serve_forever()
