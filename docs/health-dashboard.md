# Laptop health dashboard

`packages/health-dashboard` supplies the renderer, independent collector and foreground launcher for the laptop's tty1 health display, the approved A · Instrument ledger ([#70](https://github.com/teevik/homelab/issues/70#issuecomment-5913809638), [#71](https://github.com/teevik/homelab/issues/71#issuecomment-5914148716), frontend [#73](https://github.com/teevik/homelab/issues/73), production collection [#74](https://github.com/teevik/homelab/issues/74)). The renderer reads three local JSON documents and draws them. It never evaluates Nix, loads a kubeconfig, receives credentials or controls device power. Collection and night policy survive renderer exit or failure.

## Production services and startup

`homelab.healthDashboard.enable` configures `homelab-health-collector` as a dedicated service user. It starts independently of Kubernetes/network/tailnet readiness, samples `/proc/stat` and `MemAvailable` every 5s and uses `statvfs("/")` for authoritative host-root total/available capacity (`f_blocks`/`f_bavail` times `f_frsize`, including reserved capacity in used space). CPU waits for a successive sample; guest ticks are not counted twice. Only `k10temp` Tctl/Tdie or `coretemp` Package id 0 is accepted as a CPU sensor. Missing sensors are neutral; 90 minute readings remain bounded with missing-minute gaps and empty startup history.

The worker polls fixed VictoriaMetrics/Alertmanager service-proxy reads every 30s, independently of host sampling. Each request is bounded to 4s (2s connect) and 8 MiB. Values and `timestamp(...) keep_metric_names` are fetched separately so vector evaluation/receipt time cannot replace the true underlying sample time. Public `collection` metadata records evaluation/receipt times separately. HTTP requires each target's `up`, `probe_success`, duration and final status. Argo requires each configured app and current workload inventory, readiness/phase/restart series; completed pods are excluded. Workload ownership uses explicit configured, unique app namespaces or matching app labels; unmatched evidence remains under its namespace/pod. Active unsilenced/uninhibited alerts exclude Watchdog/InfoInhibitor and require current evaluator scrape plus observed `vmalert_iteration_total` progress. Empty responses alone cannot establish all-clear.

The host credential unit uses administrative provisioning only to mint an expiring one-hour token for `victoria-metrics/dashboard-collector`. Its namespaced Role permits GET solely on the two named `services/proxy` resources; no generic proxy is exposed by the collector. Atomic renewal runs every 15m, with one-minute retry on failure. The collector reopens its credential on every poll, without discovering kubeconfigs. Files under `/run/homelab-health-credentials` are root/collector-only; snapshots under `/run/homelab-health` are read-only to the renderer. The teevik account retains its approved administrative privileges.

The collector persists known observations, signal onsets and its clearance journal privately under `/var/lib/homelab-health`. Source failures preserve known failures; gaps cannot clear journal entries or invent recoveries. Recent recoveries retain for 15m (bounded to 128 entries) across UI and collector restarts. The public heartbeat updates at least every host sample; an unchanged file for 15s makes the renderer unavailable until publication resumes. A recent controller report is translated into the frontend night contract; missing/invalid/old policy data never claims applied darkness or wake.

The pinned NixOS getty implementation autologins teevik only on tty1 once per boot; full logout and other consoles require authentication. The evaluated shell is Bash, guarded by a Nix assertion. Its interactive login hook checks actual user, exact terminal, SSH exclusion and an inherited session marker, then launches a foreground child without replacing the shell. `dashboard` also relaunches manually. The launcher saves full termios, repeats palette/cursor/alternate-screen/color restoration after every child exit (including SIGKILL), and restores input before retry delays. Two retries after 1s/2s yield a prompt; Ctrl+C cancels immediately. Global console colors are ordinary Mocha ANSI; only the renderer installs the dashboard role palette. No UI exit, output or health signal requests wake.

`service-catalog.nix` is the pure shared endpoint catalog. `catalog-lib.nix` generates native Glance requests, dashboard identity/order JSON, blackbox modules and VMProbes. Expected apps and explicit namespace ownership derive separately from enabled nixidy applications. Probes run every 30s with a scrape timeout two seconds longer than their central timeout. Blackbox is pinned to v0.28.0; policies include DNS, backend ports after Service DNAT, KodeKamp ingress and the AMP/Nix Cache host routes. HTTPS verification, GET, redirects and final 200 are defaults; status/positive integer-second timeout overrides live centrally. These are internal unauthenticated reachability checks, without body assertions or browser-path guarantees.

```sh
health-dashboard --catalog PATH --snapshot PATH --night PATH
health-dashboard demo [SCENARIO]        # an ILLUSTRATIVE fixture, labelled as such
health-dashboard demo --json SCENARIO   # that fixture's three inputs, as JSON
```

Ctrl+C is the only exit (`q` is ignored). It exits 0, restores the terminal and prints the shell handoff. A missing or invalid catalog, or bad arguments, fail before the terminal is touched: exit 1 and 2 respectively. The launcher still owns retries and cleanup after a kill.

## Input contracts

The types in `src/contract.rs` are authoritative, and `examples/contract/*.json` shows a complete example of each document. Every document carries `"version": 1`, and any other version is rejected. Times are RFC 3339 instants. Each owner writes its file atomically (write a temporary file, then rename it). The renderer checks the files' metadata once a second and only redraws when their content changed. Both live and illustrative rendering use Europe/Oslo for the clock and policy expiries, including on a host configured for UTC.

### Catalog: generated from the service catalog

- `endpoints`: `{id, name, app?}` in presentation order.
  - `id` is the stable service identity.
  - `app` is the Argo CD app the endpoint belongs to. Endpoints may share an app (Immich Share → `immich`), name a differently named app (Grafana → `victoria-metrics`), or omit it for host-only endpoints (Nix Cache).
- `apps`: the expected Argo CD app inventory, including infrastructure without an endpoint. It is derived separately from the endpoints.

### Snapshot: written by the collector

- `collector_started_at`.
- `sources.{host,http,argo,alerts}`, each with:
  - `newest_sample_at`: the observation time of its newest underlying sample, not the query receipt time.
  - `failure: {since, reason}` while the latest refresh fails.
- `endpoints.<id>`: `{observed_at, result: "ok", latency_ms}` or `{observed_at, result: "fail", reason, since}`, where `since` is the failure's first observation.
- `apps.<id>`: `{observed_at, sync, sync_since?, health, health_since?}`, with Argo CD's own status words.
- `workloads[]`: `{app? | label?, problem: "restarts" | "unready", count, since}`. Restarts cover the last hour.
- `alerts[]`: `{name, app? | label?, since}`. Only active, unsilenced, uninhibited alerts, with Watchdog/InfoInhibitor excluded.
  - For both workloads and alerts, `app` is set only when trustworthy labels or ownership match an app. Otherwise the evidence keeps a `label` (default `cluster`) and gets its own attention row.
- `recoveries[]`: `{service, problem, began_at, cleared_at}`, recorded when valid observations affirmatively clear a service's signals. Losing data must never create one.
- `host`:
  - `cpu_percent` stays `null` until a second sample exists.
  - `cpu_threads`.
  - `memory` and `root`: `{total_bytes, available_bytes}`. `root` is the host root filesystem's available capacity, not a container's.
  - `temperature`: `{state: "waiting"}`, `{state: "reading", celsius, sensor}` or `{state: "unavailable"}` when no verified CPU/package sensor exists.
  - `temperature_history`: `{end, celsius: [..]}`, one real value per minute, oldest first, with `null` for missing minutes. It starts empty.

The collector owns signal onsets, history accumulation and recovery retention. The renderer derives freshness from these times at the current instant, so nothing it shows depends on how long the renderer has been running.

### Night report: written by the controller

`{dark_from, dark_until, mode, failure?}`, where `mode` is one of:
- `day`, with `next_dark_at`.
- `quiet-hours` or `bedtime`, with `until` and an optional `wake_until` while a screen-only wake runs.

`failure` reports a known failure to apply the intended state. The footer shows this report verbatim in the approved wording. It reads "night schedule state not reported" when the file is missing, invalid or has stopped updating for more than 15 seconds, and "night schedule state out of date" once a reported expiry has passed. The collector accepts controller observations only from the current boot and at most 15 seconds old, then atomically rewrites this file with each 5-second host sample. It never assumes darkness or wake.

## Derivation

`health::derive(catalog, snapshot, now)` is the single pure step behind everything drawn:

- Each **source** is *waiting* before its first sample and *current* while its newest sample is at most 3 minutes old. After that it is *stale*, and it is *unavailable* while its refresh fails; a failure takes effect immediately.
- An expected endpoint or app is a **coverage gap** when its current source has no result for it, or when its own result is older than 3 minutes. Gaps withhold ALL CLEAR but are never counted as signals.
- **ATTENTION** applies whenever any **signal** is known, including retained failures from a stale or unavailable source. Otherwise **UNKNOWN** applies while any of the four sources (host included) is not current, or any gap exists. **ALL CLEAR** needs neither. An absent temperature sensor is neutral.
- **Attention rows**:
  - One row per service, ordered by tier (HTTP `■`, alert `!`, deployment `▲`, coverage gap `?`) and then catalog order.
  - A shared app's evidence appears once, on its first endpoint.
  - `since` is the oldest signal's onset.
- The fixed slot shows up to four rows. With more, it shows three rows plus `+n more: names (highlighted below)`. Signal lists end in `+n more` rather than cutting a word.

## Presentation choices made here

- Meters turn warm at 80% and hot at 90%. The temperature turns warm at 70 °C and hot at 80 °C, and the history is scaled over 40–95 °C. These are colours only, never health thresholds or signals. Heat is blue, yellow and peach, never red.
- Live text is sanitised: any character the 256-glyph console font lacks, including control and escape sequences, becomes `?`. Text is fitted at word boundaries with `...`.
- A frame is drawn on new data, input and resize. The next frame is due at the earliest of:
  - the next freshness boundary,
  - a recovery leaving the display,
  - a night-state expiry,
  - the next minute, for the clock.

  There is no animation and no per-second loop.
- **Compact fallback** (below 150×45):
  - The status word at 1×, with the summary beside it or under it.
  - Up to three problem rows (two plus a named `+n more` line when there are more).
  - Endpoints in two columns in catalog order, scrolling with `↑`/`↓`.
  - One apps line and two instrument lines.
- Below 60×20 only the status word and the headline remain.
- `TERM=linux` loads the role palette with `ESC ] P` and resets it with `ESC ] R`. Other terminals use OSC 4/104, for development only. Because the VT has no alternate screen, exit on `TERM=linux` also clears the screen.

## Checking it

`nix build .#health-dashboard` runs every test (`nix flake check` includes it as `pkgs-health-dashboard`). From `packages/health-dashboard` inside `nix develop`:

```sh
cargo test                                          # snapshot -> derived view -> frame, and a PTY run
cargo run --example render_console -- /tmp/renders  # console-faithful PNGs for visual review
cargo run -- demo mixed                             # interactive, in the current terminal
```

The PNGs use the kernel's built-in TER16x32 bitmaps and the VT's colour rules, so they are review evidence for the frame. Neither they nor the PTY test prove real fbcon rendering, readability at one metre, palette behaviour on the real VT or resource use. Those checks belong to actual-laptop acceptance ([#76](https://github.com/teevik/homelab/issues/76)); see the [candidate, rollout/rollback and owner checklist](dashboard-acceptance.md) and [evidence record](dashboard-evidence.md).
