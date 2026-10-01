"""Real apiserver authorization, using only the disposable VM's scoped token."""
import json
import ssl
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

credential = json.loads(Path('/run/homelab-health-credentials/credential.json').read_text())
context = ssl.create_default_context(cafile=credential['ca'])
base = 'https://127.0.0.1:6443'


def status(path, method='GET', token=credential['token']):
    request = Request(base + path, headers={'Authorization': 'Bearer ' + token}, method=method)
    try:
        with urlopen(request, context=context, timeout=5) as response:
            return response.status
    except HTTPError as error:
        print(method, path, error.code, error.read().decode())
        return error.code


metrics = '/api/v1/namespaces/victoria-metrics/services/http:vmsingle-vm-victoria-metrics-k8s-stack:8428/proxy/api/v1/query'
alerts = '/api/v1/namespaces/victoria-metrics/services/http:vmalertmanager-vm-victoria-metrics-k8s-stack:9093/proxy/api/v2/alerts'
metrics_status = status(metrics)
assert metrics_status == 200, metrics_status
alerts_status = status(alerts)
assert alerts_status == 200, alerts_status
for method in ['POST', 'PUT', 'PATCH', 'DELETE']:
    assert status(metrics, method) == 403, method
for path in ['/api/v1/secrets', '/api/v1/nodes', '/api/v1/pods', '/api/v1/namespaces/victoria-metrics/secrets',
             '/api/v1/namespaces/amp/services/http:amp:80/proxy/',
             '/api/v1/namespaces/victoria-metrics/services/http:dashboard-blackbox:9115/proxy/']:
    assert status(path) == 403, path
assert status(metrics, token='invalid-expired-fixture') == 401
assert status(metrics, token='') in [401, 403]
print('real k3s service-proxy GET restrictions and unrelated-operation denials passed')
