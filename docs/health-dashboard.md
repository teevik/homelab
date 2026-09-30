# Laptop health dashboard: renderer

`packages/health-dashboard` is the console renderer for the laptop's tty1 health display, the approved A · Instrument ledger ([#70](https://github.com/teevik/homelab/issues/70#issuecomment-5913809638), [#71](https://github.com/teevik/homelab/issues/71#issuecomment-5914148716), built in [#73](https://github.com/teevik/homelab/issues/73)). It reads three local JSON documents and draws them. It never evaluates Nix, loads a kubeconfig, receives credentials or controls device power. The collector, tty1 launcher and night-policy controller are separate programs ([#74](https://github.com/teevik/homelab/issues/74), [#75](https://github.com/teevik/homelab/issues/75)); the renderer can exit or fail without affecting them.

```sh
health-dashboard --catalog PATH --snapshot PATH --night PATH
health-dashboard demo [SCENARIO]        # an ILLUSTRATIVE fixture, labelled as such
health-dashboard demo --json SCENARIO   # that fixture's three inputs, as JSON
```

Ctrl+C is the only exit (`q` is ignored). It exits 0, restores the terminal and prints the shell handoff. A missing or invalid catalog, or bad arguments, fail before the terminal is touched: exit 1 and 2 respectively. The launcher still owns retries and cleanup after a kill.

## Input contracts

The types in `src/contract.rs` are authoritative, and `examples/contract/*.json` shows a complete example of each document. Every document carries `"version": 1`, and any other version is rejected. Times are RFC 3339 instants. Each owner writes its file atomically (write a temporary file, then rename it). The renderer checks the files' metadata once a second and only redraws when their content changed.

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

`failure` reports a known failure to apply the intended state. The footer shows this report verbatim in the approved wording. It reads "night schedule state not reported" when the file is missing or invalid, and "night schedule state out of date" once a reported expiry has passed. It never assumes darkness or wake.

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

The PNGs use the kernel's built-in TER16x32 bitmaps and the VT's colour rules, so they are review evidence for the frame. Neither they nor the PTY test prove real fbcon rendering, readability at one metre, palette behaviour on the real VT or resource use. Those checks belong to actual-laptop acceptance ([#76](https://github.com/teevik/homelab/issues/76)).
