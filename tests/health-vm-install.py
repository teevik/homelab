"""Install production discovery/RBAC/policies into a disposable k3s only.

Only external API/device/app data is synthetic. Do not run on the homelab.
"""
import json
import subprocess
from pathlib import Path

import yaml

root = Path('/etc/health-production')


def install(resources):
    subprocess.run(['kubectl', 'apply', '-f', '-'], input=json.dumps({
        'apiVersion': 'v1', 'kind': 'List', 'items': resources,
    }), text=True, check=True)


def read(namespace, filename):
    return yaml.safe_load((root / namespace / filename).read_text())


def resource(kind, name, namespace, spec=None, **extra):
    result = {'apiVersion': 'v1', 'kind': kind, 'metadata': {'name': name, 'namespace': namespace}, **extra}
    if spec is not None:
        result['spec'] = spec
    return result


install([resource('Namespace', name, name) for name in ['victoria-metrics', 'kodekamp', 'amp']])
install([yaml.safe_load(path.read_text()) for path in (root / 'victoria-metrics').glob('CustomResourceDefinition-*.yaml')])
operator = [read('victoria-metrics', f'{kind}-vm-victoria-metrics-operator.yaml')
            for kind in ['ServiceAccount', 'ClusterRole', 'ClusterRoleBinding', 'Role', 'RoleBinding', 'Service', 'Deployment']]
# Avoid mutable pulls; only the exact preloaded artifacts can start.
operator[-1]['spec']['template']['spec']['containers'][0]['imagePullPolicy'] = 'Never'
install(operator)
install([read('victoria-metrics', f'{kind}-dashboard-collector.yaml') for kind in ['ServiceAccount', 'Role', 'RoleBinding']])

# The service-proxy API requires a Pod targetRef, even for a host endpoint.
# These host-network pods identify the external API boundary running on the VM.
for namespace in ['victoria-metrics', 'amp']:
    install([resource('Pod', 'health-api', namespace, {
        'hostNetwork': True,
        'containers': [{'name': 'boundary', 'image': 'test.local/health-client:local',
                        'imagePullPolicy': 'Never', 'command': ['/bin/sleep', 'infinity'],
                        'ports': [{'containerPort': port} for port in [8428, 8088, 8501]]}],
    })])

services = []
for namespace, name, service_port, target_port in [
    ('victoria-metrics', 'vmsingle-vm-victoria-metrics-k8s-stack', 8428, 8428),
    ('victoria-metrics', 'vmalertmanager-vm-victoria-metrics-k8s-stack', 9093, 8428),
    ('amp', 'amp', 80, 8088),
]:
    services.extend([
        resource('Service', name, namespace, {'ports': [{'name': 'http', 'port': service_port, 'targetPort': target_port}]}),
        resource('Endpoints', name, namespace, subsets=[{
            'addresses': [{'ip': '192.168.1.225', 'targetRef': {
                'kind': 'Pod', 'name': 'health-api', 'namespace': namespace,
            }}],
            'ports': [{'name': 'http', 'port': target_port}],
        }]),
    ])
services.append(resource('Service', 'kodekamp-web', 'kodekamp', {
    'selector': {'app': 'kodekamp-web'}, 'ports': [{'port': 3000, 'targetPort': 3000}],
}))
install(services)
server = resource('Pod', 'web', 'kodekamp', {'containers': [{
    'name': 'web', 'image': 'test.local/health-client:local', 'imagePullPolicy': 'Never',
    'command': ['/bin/sh', '-c', 'mkdir /www; echo synthetic-web > /www/index.html; exec httpd -f -p 3000 -h /www'],
}]})
server['metadata']['labels'] = {'app': 'kodekamp-web'}
install([server, read('kodekamp', 'NetworkPolicy-web.yaml')])

prober = [read('victoria-metrics', f'{kind}-dashboard-blackbox.yaml') for kind in ['ConfigMap', 'Service', 'NetworkPolicy', 'Deployment']]
container = prober[-1]['spec']['template']['spec']['containers'][0]
assert container['image'].endswith('@sha256:e753ff9f3fc458d02cca5eddab5a77e1c175eee484a8925ac7d524f04366c2fc')
# Docker airgap archives carry tags; the fixed-output input pins the original digest.
container['image'] = container['image'].split('@')[0]
container['imagePullPolicy'] = 'Never'
install(prober)
probes = [yaml.safe_load(p.read_text()) for p in sorted((root / 'victoria-metrics').glob('VMProbe-dashboard-*.yaml'))]
assert len(probes) == 16
for probe in probes:
    identity = probe['spec']['targets']['staticConfig']['labels']['service_id']
    if identity not in ['kodekamp', 'amp', 'nix-cache']:
        probe['spec']['targets']['staticConfig']['targets'] = ['http://kodekamp-web.kodekamp.svc:3000']
install(probes)
agent = read('victoria-metrics', 'VMAgent-vm-victoria-metrics-k8s-stack.yaml')
assert agent['spec']['probeSelector'] == {'matchLabels': {'homelab.teevik.dev/dashboard': 'true'}}
assert agent['spec']['probeNamespaceSelector'] == {'matchLabels': {'kubernetes.io/metadata.name': 'victoria-metrics'}}
assert agent['spec']['image']['tag'].endswith('@sha256:3eff5874d59292714878dcb6aee14f048bf19b7312b727860ba5e7d29e2e0c07')
agent['spec']['image']['tag'] = 'v1.150.0'
agent['spec']['image']['pullPolicy'] = 'Never'
# Select only the production probes; avoid unrelated exporters in this fixture.
agent['spec']['selectAllByDefault'] = False
agent['spec']['useVMConfigReloader'] = True
install([agent])
for name, labels in [('allowed', {'app.kubernetes.io/name': 'vmagent'}), ('denied', {})]:
    client = resource('Pod', name, 'victoria-metrics', {'containers': [{
        'name': 'client', 'image': 'test.local/health-client:local', 'imagePullPolicy': 'Never', 'command': ['/bin/sleep', 'infinity'],
    }]})
    client['metadata']['labels'] = labels
    install([client])
