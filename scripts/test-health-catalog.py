"""Generated consumer boundary: preserve production identities and HTTP expectations."""
import json
import sys
from pathlib import Path

outputs = json.loads(Path(sys.argv[1]).read_text())
endpoints = outputs["dashboard"]["endpoints"]
assert [e["name"] for e in endpoints] == [
    "Glance", "Longhorn", "Immich", "Grafana", "Nix Cache", "ArgoCD",
    "KodeKamp", "Paperless-ngx", "BentoPDF", "AMP", "TwitchDropsMiner",
    "ntfy", "Immich Share", "Changedetection", "Registry", "Reclip",
]
by_name = {e["name"]: e for e in endpoints}
assert by_name["Immich Share"]["app"] == "immich"
assert by_name["Grafana"]["app"] == "victoria-metrics"
assert by_name["Nix Cache"]["app"] is None
assert {"amd-device-plugin", "cloudflare-tunnel", "glance-agent", "tailscale-operator"} <= set(outputs["dashboard"]["apps"])
assert "apps" not in outputs["dashboard"]["apps"]
assert "__bootstrap" not in outputs["dashboard"]["apps"]
for endpoint, glance, probe in zip(endpoints, outputs["glance"], outputs["probes"], strict=True):
    identity = endpoint["id"]
    module = outputs["blackbox"]["modules"][identity]
    assert glance["title"] == endpoint["name"]
    assert glance["check-url"] == probe["spec"]["targets"]["staticConfig"]["targets"][0]
    assert probe["spec"]["targets"]["staticConfig"]["labels"]["service_id"] == identity
    assert probe["spec"]["module"] == identity
    assert probe["spec"]["interval"] == "30s"
    assert int(probe["spec"]["scrapeTimeout"][:-1]) > int(module["timeout"][:-1])
    assert module["http"]["method"] == "GET"
    assert module["http"]["follow_redirects"] is True
    assert module["http"]["tls_config"]["insecure_skip_verify"] is False
    assert module["http"]["valid_status_codes"] == [200, *glance["alt-status-codes"]]
    assert glance["allow-insecure"] is False
    assert glance["timeout"] == module["timeout"]
assert outputs["glance"][4]["check-url"] == "http://192.168.1.225:8501/nix-cache-info"
assert outputs["glance"][9]["check-url"] == "http://amp.amp.svc"
variant = outputs["variant"]
assert variant["dashboard"]["apps"] == outputs["dashboard"]["apps"]
assert variant["dashboard"]["endpoints"][:-1] == endpoints
assert variant["dashboard"]["endpoints"][-1] == {"id": "fixture", "name": "Fixture", "app": None}
assert variant["glance"][-1]["alt-status-codes"] == [202]
assert variant["glance"][-1]["timeout"] == "4s"
assert variant["blackbox"]["modules"]["fixture"]["http"]["valid_status_codes"] == [200, 202]
assert variant["blackbox"]["modules"]["fixture"]["timeout"] == "4s"
assert variant["probes"][-1]["spec"]["scrapeTimeout"] == "6s"
assert variant["probes"][-1]["spec"]["targets"]["staticConfig"]["labels"] == {"service_id": "fixture"}
print("catalog generation: identities, inventory and HTTP contracts passed")
