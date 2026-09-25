# Nix cache monitoring

The **Nix Cache** dashboard lives in Grafana's **Cluster** folder at
`http://grafana/d/nix-cache`. Glance's **Nix Cache** entry checks ncps's
`/nix-cache-info` endpoint and links to this dashboard.

## Metrics path

`kubernetes/nix-cache.nix` adds two `VMStaticScrape` resources to the existing
VictoriaMetrics application:

| Job | Target | Source |
| --- | --- | --- |
| `nix-cache-ncps` | `192.168.1.225:8501/metrics` | ncps's existing Prometheus endpoint |
| `nix-cache-harmonia` | `192.168.1.225:8502/metrics` | Nginx forwards this exact path to `127.0.0.1:5000/metrics` |

Both targets use the reserved node address in `hosts/homelab/configuration.nix`.
vmagent reaches them through the existing trusted CNI interfaces. Port 8502 is
not opened to LAN/public traffic; the trusted Tailscale interface also permits
access. Harmonia's cache listener remains on loopback. The proxy returns 404
for other paths, so it cannot serve NARs or narinfo directly.

Grafana discovers the dashboard through its existing ConfigMap sidecar.
The datasource is selectable, and all cache queries select the jobs above.
Scrapes run every 30 seconds; allow a few scrapes before rates appear.

## What the dashboard measures

- **Scrape status:** whether metrics can be fetched from each service. Glance
  checks ncps's cache-info response. Neither check verifies a complete NAR
  download or that a particular published generation is present.
- **ncps client traffic:** NAR/narinfo request rates, latency and NAR response
  bandwidth. Monitoring and cache-info requests are excluded.
- **ncps upstream traffic:** request rates, p95 latency, HTTP responses and
  transport errors by upstream. These include periodic health checks and
  concurrent upstream races. `127.0.0.1` identifies Harmonia. A cancelled
  losing request does not necessarily indicate a failed client download.
- **Harmonia:** request rates, status codes and latency for requests reaching
  the native store. Warm ncps responses do not reach Harmonia. A 404 is an
  expected lookup miss, not a server failure.
- **Disk headroom:** existing node-exporter metrics for homelab's root
  filesystem, shared by `/nix/store`, `/var/lib/ncps` and other host data.
  The free-space panel turns red below the cache's 300 GiB upload reserve.

The deployed ncps endpoint was inspected when building this dashboard. It
exposes `http_server_request_duration_seconds`,
`http_server_response_body_size_bytes` and
`http_client_request_duration_seconds`. Its server metrics use `http_method`
and `http_route`; its client metrics use `http_request_method`,
`http_response_status_code`, `server_address` and `error_type`.

It does not currently expose custom `ncps_*` counters. Consequently this
dashboard does not claim to measure cache-hit ratio, ncps cache size, retained
closure size or publication/GC freshness. Those require additional metrics;
upstream/client request ratios and total filesystem usage are not substitutes.

The Harmonia views follow the upstream dashboard's request/status/latency
coverage, with local job filters and monitoring traffic excluded:
[Harmonia monitoring](https://github.com/nix-community/harmonia#prometheus-monitoring),
[upstream dashboard](https://github.com/nix-community/harmonia/blob/main/harmonia-cache/harmonia-grafana-dashboard.json).

## Rollout and verification

Deploy the NixOS host configuration to start the metrics proxy (`just deploy`).
Commit and push the source and regenerated manifests through the usual GitOps
workflow so Argo CD provisions the scrapes, dashboard and Glance entry. Do not
apply the manifest tree manually.

After deployment:

```sh
ssh homelab 'curl -fsS http://127.0.0.1:8502/metrics'
ssh homelab 'curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8502/nix-cache-info'
```

The first command should return `harmonia_http_*` metrics and the second 404.
In Grafana, both scrape-status panels should be UP. Traffic can legitimately be
zero while idle, and latency percentiles can be empty without recent requests.
Missing scrape data is displayed as **No data**, not as a healthy result.
