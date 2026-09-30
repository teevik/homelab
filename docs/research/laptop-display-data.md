# Laptop display: custom runtimes and health data

Research for [Identify viable custom dashboard runtimes and health data](https://github.com/teevik/homelab/issues/63), within [Design a distinctive laptop health display](https://github.com/teevik/homelab/issues/62).

Investigated 2026-09-30 against repository commit `13103fe` and primary upstream sources. This is configuration/source research, **not a live host or sensor inspection**. No production changes or physical display operations were performed. User-owned changes in the main worktree were excluded from this research snapshot.

## Finding

Both a bespoke GUI and a custom terminal dashboard are feasible without using Grafana as the display or replacing monitoring. Reuse the existing VictoriaMetrics queries and Alertmanager API. Keep a small host-local data reader/UI able to start before Kubernetes, so cluster outages can be displayed truthfully. The visual prototype should compare these two directions with the same healthy, degraded, and unavailable fixtures; the owner still selects the appearance.

A visually rich TUI should provision a graphical terminal, rather than assume the Linux virtual console has equivalent colors and fonts. There is no research prerequisite blocking that comparison. Actual sensor labels, display resolution, and route/credential verification belong in implementation acceptance checks unless a later design makes a currently unverified sensor mandatory.

## Runtime options

| Option | Feasible implementation | Constraints and useful distinction |
|---|---|---|
| Custom terminal instrument panel | Go application using Bubble Tea for events/rendering and Lip Gloss for layout, hosted full-screen in Alacritty under a minimal Wayland compositor | Own typography, spacing, sparklines and hierarchy within a cell grid. Alacritty supports Wayland, explicit fonts and full-screen startup. Existing repository Go packaging is a useful precedent. Runtime and power control still include a graphical session. |
| Custom graphical instrument panel | Locally bundled HTML/CSS/SVG and a small JSON endpoint, viewed full-screen in a browser under the chosen compositor | Arbitrary typography, large health summaries and charts; easiest route to a distinctive non-template composition. More runtime components than a console application; actual CPU/GPU/RAM cost needs measurement. Bundle fonts/assets locally so network failure does not prevent rendering. |
| True Linux virtual console | A deliberately restricted TUI on a dedicated VT | No graphical terminal required, but console escape-code support maps richer requested colors into its limited palette. Validate glyphs and font sizes on the actual console; do not use a rich terminal screenshot as proof of VT compatibility. Screen power behavior is a separate feasibility question. |

Sources: [Bubble Tea](https://github.com/charmbracelet/bubbletea), [Lip Gloss](https://github.com/charmbracelet/lipgloss), [Alacritty Wayland build support](https://github.com/alacritty/alacritty/blob/master/INSTALL.md), [Alacritty window/font configuration](https://alacritty.org/config-alacritty.html), [Linux console escape-code behavior](https://man7.org/linux/man-pages/man4/console_codes.4.html), [Cage's single-application Wayland model](https://github.com/cage-kiosk/cage). These establish available building blocks; the layout, compositor choice and performance claims above are engineering proposals, not measured outcomes. The repository's [Go stats package](../../packages/anime-matrix-stats/go.mod) and [NixOS unit](../../modules/nixos/anime-matrix.nix) demonstrate existing packaging conventions.

**Glance is useful as source material, not a necessary runtime dependency.** This repo already customizes its HTML/CSS and queries, but the pinned Glance v0.8.5 explicitly refreshes data on page loads rather than automatically polling. Its cards cache for one minute. Adapting it for an unattended display therefore needs page reload management and a distinct layout. Starting a bespoke view avoids inheriting those interaction and refresh assumptions. Sources: [pinned Glance FAQ](https://github.com/glanceapp/glance/blob/v0.8.5/README.md#faq), [local configuration](../../kubernetes/glance.nix), [widget definitions](../../kubernetes/glance/widgets.nix), [local CSS](../../kubernetes/glance/dashboard.css).

## Existing data and what it means

The current [widget definitions](../../kubernetes/glance/widgets.nix) already contain useful query/error semantics. The [overview queries](../../kubernetes/dashboards/homelab-overview.json) provide further metric examples; reusing them does not require showing Grafana.

| Display content | Existing source / representative query | Meaning and limitation |
|---|---|---|
| Deployment health | `max by(name, health_status, sync_status) (argocd_app_info)` | Desired deployment health/synchronization, not an end-to-end application request. Current attention card considers non-Healthy or non-Synced applications noteworthy. |
| Workloads needing attention | `kube_pod_status_phase`, `kube_pod_status_ready`, `kube_pod_container_status_restarts_total` | Reuse the existing exclusion of completed pods and one-hour restart query. Missing kube-state-metrics inventory is unknown, not no problems. |
| Reachability | Glance's configured `check-url` inventory | These are HTTP checks made inside Kubernetes. They are not stored Prometheus health series in the inspected configuration. A new UI can reuse the inventory, but must deliberately implement checks from its chosen network location. Do not imply `up` is application availability: it is exporter scrape health. |
| Alerts | Alertmanager `GET /api/v2/alerts` | Existing request uses `active=true`, `silenced=false`, `inhibited=false`, and `filter=alertname!~"Watchdog\|InfoInhibitor"`. Preserve these semantics or explicitly decide otherwise. Empty results are meaningful only when the alert and monitoring paths are working. |
| CPU and RAM | `100 * (1 - avg(rate(node_cpu_seconds_total{job="node-exporter",mode="idle"}[5m])))`; memory from `MemAvailable` / `MemTotal` | These are already configured. CPU is a five-minute utilization average; do not label it instantaneous load. Select the laptop instance when adding more nodes. |
| Root storage | `node_filesystem_avail_bytes` / `node_filesystem_size_bytes`, selecting `mountpoint="/",fstype!="rootfs"` | Existing overview uses this. Keep host root capacity distinct from Longhorn's logical volume/storage metrics. |
| Network activity | `rate(node_network_receive_bytes_total[5m])` and transmit counterpart | Supported by node-exporter's netdev collector; select the physical uplink rather than summing bridge/veth/Tailscale interfaces and double counting traffic. Actual interface labels remain unverified. |
| Temperatures | `node_hwmon_temp_celsius`, joined with `node_hwmon_chip_names` / `node_hwmon_sensor_label` when present | The default hwmon collector reads exposed kernel sensors. Select a named CPU/package sensor, not the maximum of every unrelated chip. Sensor availability and labeling require inspection. |
| Fans / GPU | `node_hwmon_fan_rpm` or GPU hwmon temperatures, if exported | Optional. The ASUS WMI chip is explicitly excluded from node-exporter because of duplicate PWM metrics. There is no dedicated GPU utilization exporter configured in the inspected modules. The AMD device plugin advertises GPU resources; it is not evidence of utilization telemetry. |

Local evidence: [Glance service inventory](../../kubernetes/glance.nix), [attention queries](../../kubernetes/glance/widgets.nix), [node-exporter args and hwmon exclusion](../../kubernetes/victoriametrics.nix), [host-mounted exporter manifest](../../manifests/homelab/victoria-metrics/DaemonSet-vm-prometheus-node-exporter.yaml), [AMD plugin](../../kubernetes/amd-device-plugin.nix). Upstream: [node-exporter collectors](https://github.com/prometheus/node_exporter), [hwmon metric names in pinned exporter source](https://github.com/prometheus/node_exporter/blob/v1.11.1/collector/hwmon_linux.go), [kernel sensor interface](https://docs.kernel.org/hwmon/sysfs-interface.html), [Alertmanager API schema](https://github.com/prometheus/alertmanager/blob/main/api/v2/openapi.yaml).

The repo's [runner history](../github-runner.md) records prior CPU temperature observations. That supports temperatures having been available in earlier work; this session has not verified the current sensor, query, or hardware mapping.

### Glance Agent is optional, with two important caveats

The configured host-networked [Glance Agent](../../kubernetes/glance-agent.nix) listens on port `27973`, with no token configured. Its pinned API is `GET /api/sysinfo/all`; it exposes availability flags, CPU load averages, a CPU temperature if detected, memory and mountpoints. `load1_percent` / `load15_percent` are load indicators, not the utilization query above. Requests can use bearer authentication if a token is later configured. [Pinned agent API documentation](https://github.com/glanceapp/agent/blob/v0.1.0/README.md#api).

Its [server source](https://github.com/glanceapp/agent/blob/v0.1.0/internal/agent/server.go) caches collection for one second and calls the API unversioned with no compatibility guarantee. Honor each availability flag. The current DaemonSet config names `/` as Root **without a host-root volume mount**; upstream requires the intended host mountpoints to be mounted into a container. Do not promote that reported root value to authoritative host storage without checking/fixing the mapping. Node-exporter already has explicit host mounts. Glance Agent is also a Kubernetes workload, so it cannot by itself supply a host-health fallback when Kubernetes is down. [Pinned mountpoint guidance](https://github.com/glanceapp/agent/blob/v0.1.0/README.md#configuration), [local agent manifest source](../../kubernetes/glance-agent.nix).

## API access from a host-local display

The existing in-cluster URLs are:

- Metrics: `http://vmsingle-vm-victoria-metrics-k8s-stack.victoria-metrics.svc:8428/api/v1/query` and the corresponding `/api/v1/query_range` for history.
- Alerts: `http://vmalertmanager-vm-victoria-metrics-k8s-stack.victoria-metrics.svc:9093/api/v2/alerts`.

The query APIs accept a query expression and return Prometheus-compatible JSON; range queries also accept start/end/step. Sources: [local widget endpoints](../../kubernetes/glance/widgets.nix), [VictoriaMetrics API examples](https://docs.victoriametrics.com/victoriametrics/url-examples/).

**Do not assume those `.svc` names resolve from the laptop's host session.** Kubernetes configures service DNS for pods, while the host's inspected Ethernet config uses the router as DNS. Successful access from Glance is not proof of host-session access. Sources: [Kubernetes service DNS](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/), [host network configuration](../../hosts/homelab/configuration.nix).

A concrete feasible route is a host-local collector using the Kubernetes API's service proxy with dedicated, narrowly scoped credentials. Its metrics URL would have the form:

```text
https://<k3s-api>/api/v1/namespaces/victoria-metrics/services/vmsingle-vm-victoria-metrics-k8s-stack:8428/proxy/api/v1/query?query=<encoded-query>
```

Use the analogous Alertmanager service proxy. Kubernetes documents service-name/port proxy paths and RBAC subresource/name restrictions. Limit permitted requests and keep credentials in the local collector, not in browser assets; do not hand the kiosk the administrator kubeconfig. The exact proxy resource names, GET authorization, certificate/token lifecycle and denial of unrelated operations need a focused implementation check. An explicitly exposed read-only aggregation endpoint is an alternative if credential lifecycle makes the API proxy unattractive. Neither access path exists as a dashboard facility today. Sources: [service proxy URL rules](https://kubernetes.io/docs/tasks/access-application-cluster/access-cluster-services/), [RBAC subresources and named resources](https://kubernetes.io/docs/reference/access-authn-authz/rbac/).

For the GUI, serve bundled assets and normalized JSON through one loopback origin. For the TUI, use the same collector/data model in process or over a local socket. These are proposed boundaries, not additional infrastructure already present. They let the later design choose presentation independently of API credentials and query details.

## Freshness and outage constraints

The generated monitoring configuration sets a **20-second scrape interval** and **20-second alert evaluation interval**, though individual scrapes/rules can override them. Polling dashboards faster cannot make those upstream samples newer. Existing Glance widgets use a one-minute cache and reject expected monitoring sources with samples older than three minutes. Sources: [VMAgent](../../manifests/homelab/victoria-metrics/VMAgent-vm-victoria-metrics-k8s-stack.yaml), [VMAlert](../../manifests/homelab/victoria-metrics/VMAlert-vm-victoria-metrics-k8s-stack.yaml), [widget freshness guard](../../kubernetes/glance/widgets.nix).

Recommended starting contract for the later behavior decision:

- Poll cluster snapshots every 20–30 seconds with bounded timeouts; fetch history less often. Record source sample time separately from successful HTTP receipt time.
- Preserve expected source inventory and scrape success checks. Use `timestamp(metric)` / `time() - timestamp(metric)` for actual sample age; a query evaluation timestamp alone does not prove a fresh scrape. Validate required metric series as well as exporter `up`, since a working scrape can omit a sensor or fail one collector. [MetricsQL timestamp semantics](https://docs.victoriametrics.com/victoriametrics/metricsql/#timestamp).
- Represent healthy, unhealthy, missing/unsupported and stale separately. A failed request, empty required inventory or unavailable temperature must never become zero or healthy. Last known values, if retained, need their age and unavailable state carried alongside them. The current [CSS](../../kubernetes/glance/dashboard.css) already hides stale cached “all clear” after transport errors.
- Start the host reader and view without waiting for the cluster or tailnet. Render a local starting/unavailable state, retry independently, and let local CPU/RAM/root statistics continue from `/proc` and the filesystem. The [existing stats program](../../packages/anime-matrix-stats/main.go) demonstrates such local collection; reuse the approach after reviewing sampling semantics, not its AniMe Matrix side effects.
- Avoid presenting “no alerts” as “everything healthy.” Include monitoring/evaluator availability alongside the alert result; agreement on exactly what constitutes an all-clear belongs to the behavior ticket.
- Keep rendering/session lifetime separate from the accepted night policy. Turning the display off should not require stopping cluster monitoring. The power-control research owns exact screen and lid-LED handling.

These are feasible semantics for prototypes and design discussion, not a resolution of the owner's remaining interaction choices.

## Next decision and acceptance checks

The visual ticket can now compare a custom terminal layout with a bespoke graphical layout at the same apparent laptop-screen scale. Use the same truthful fixture states, and omit/fade fan and GPU fields when unsupported. Do not add a separate research ticket merely to pick libraries.

The behavior/design ticket should select the UI runtime, the concrete collector access path, which health signals earn the headline, and what retained data looks like during failures. Actual resolution/scale, temperature labels, uplink selection, root-filesystem identity, permissions, cold boot with Kubernetes unavailable, and resource cost are implementation acceptance checks. If the owner makes true-VT operation, fan speed or GPU utilization mandatory, its unverified hardware/runtime support becomes a decision prerequisite; otherwise it need not delay choosing a design.
