# Dashboard validation evidence — issue #76

This record accompanies [the candidate and acceptance runbook](dashboard-acceptance.md).
**The production system has not been accepted.** Owner readability, physical
darkness/restoration, actual keyboard behavior and whole-stack measurements are
pending. No candidate deployment, reboot or production power/service action was
performed during preparation.

## Candidate provenance

- Repository baseline: `990e4cc`, integrated main after PRs #77, #78 and #80.
- Validation branch: `codex/issue-76-dashboard-validation`; the commit containing
  this record is the candidate source revision (record its exact SHA on rollout).
- Locked root nixpkgs: `e5bdc4a41d4c072fe1e3787eaa0320a384741d44`.
- Renderer/collector/launcher: health-dashboard 0.1.0; Ratatui 0.30.2,
  Crossterm 0.29.0, Jiff 0.2.37; Rust/Cargo 1.97.1 in the pinned dev shell.
- Kernel 6.18.44; k3s 1.35.7+k3s1; asusctl 6.3.8; Terminus 4.49.1;
  Glance 0.8.5; blackbox 0.28.0. Discovery VM uses operator 0.74.1,
  matching config-reloader, and vmagent 1.150.0 pinned by OCI digest and Nix hash.
- Lockfile SHA-256: `2e84392c5dfef676595d6f6ba6a997d3187a7d2afd33f0fc1723b5c8c59f7099`.
- Built renderer/collector/launcher package:
  `/nix/store/kficnpp1kj82867mp9k685qyzkp066f1-health-dashboard-0.1.0`.
- Built candidate host closure:
  `/nix/store/agy4kqgicc6dq543325xcwh1bqsg058w-nixos-system-homelab-26.11.20260816.e5bdc4a`.
  Preserve these paths, the exact source revision and lockfile at rollout.

## Automated results

| Evidence | Result |
| --- | --- |
| Stale controller observation (>15s) rejected by real collector; current-boot verification; failed/absent reports | Regression reproduced, corrected and focused test passed |
| Frozen translated night file expires after 15s and reconnects automatically | Regression reproduced, corrected and real renderer PTY test passed |
| Live footer formats summer/winter Oslo 08:00 on a UTC host | Regression reproduced, corrected and real renderer PTY test passed |
| Expanded API cases: empty, 403, missing timestamps, failed scrape, one old required series amid fresh responses | Focused real collector → frame test passed |
| Actual default 5s host / 30s cluster cadence during slow API requests | Focused scheduling test passed |
| Real renderer kill/error, retries/cancellation/relaunch, ignored q/no idle animation and usable canonical shell input | Expanded launcher PTY test passed |
| Deliberate panic after real terminal setup, child and launcher cleanup; production ignores fault input | Separate test-feature build and PTY check passed |
| Render boundaries/layout focused suites | Passed |
| Integrated login/RBAC/expiry/discovery/network/clock VM | Passed all six subtests, 524.34s; no-IP cold startup, real authenticated SSH and reboot included |
| Full flake/Homelab checks, committed manifests and candidate host build | Passed all 17 x86_64-linux checks; manifest regeneration reported no changes; package and host closure built |

The successful integrated check is retained at
`/nix/store/cfcy3pyyldkvfdzy05cj28msx1mnpnlr-vm-test-run-integrated-health-dashboard`.
Its Nix build log records the six production-interface subtests. The final full
flake invocation reused matching successful outputs for all 17 checks; the host
closure was also built separately because flake checking evaluates, but does not
build, the `nixosConfigurations` output. Final `cargo check --all-targets
--all-features` and the four real renderer terminal tests passed. These are
automated results, with no implied physical or performance acceptance.

The console-faithful generator rendered all 15 states plus grown/scrolled,
threshold/compact and tiny examples. Every generated image reported zero missing
glyphs, bright backgrounds or attributes. Normal, mixed ATTENTION and monitoring-
unavailable UNKNOWN images were visually inspected: band, attention hierarchy,
ledger/host alignment and palette correspond to the approved evidence. These are
bitmap/fixture observations, not physical-panel or owner-readability acceptance.
Recreate them with `examples/render_console.rs`; they need not be committed as
duplicate generated binaries.

## Read-only actual-laptop observations

Observed remotely on **1 October 2026, approximately 09:41–09:44 Europe/Oslo**.
The laptop's own command output uses UTC; the times here are converted to Oslo.
These observations use existing system read interfaces and GETs. No observer
was present at the panel, and none of the new controls was actuated.

| Observation | Actual read result | What this establishes |
| --- | --- | --- |
| Booted kernel | 6.18.44 | Current kernel, not candidate rollout |
| Current system | `/nix/store/dkdawj74661jv41qdxmd0fl7r18l11md-nixos-system-homelab-26.11.20260816.e5bdc4a` | Rollback baseline at observation time |
| k3s | v1.35.7+k3s1 | Actual cluster package |
| asusctl executable | `/nix/store/141kwnbh5hvqb5xgc4wq6cnfs59yhnzn-asusctl-6.3.8/bin/asusctl` | Correct effective package baseline |
| Active console / tty1 getty | VT 1; getty active | Current VT/session service, not once-per-boot acceptance |
| Console dimensions | `stty -F /dev/tty1 size`: `50 160` | Geometry readback |
| Loaded font | `showconsolefont --info -C /dev/tty1`: `16x32x256` | Font metadata readback; physical glyph visibility still pending |
| Backlight/device path | `.../0000:07:00.0/drm/card2/card2-eDP-2/amdgpu_bl2` | Current eDP/amdgpu interface |
| Brightness / actual / maximum / power | 3122 / 3084 / 65535 / 0 | Device readbacks; no darkness proof |
| CPU sensor | k10temp, `Tctl`, 90375 milli-°C | A real available CPU/package sensor at the observation time |
| Host root | `/dev/nvme0n1p2`, total 2014587109376 bytes, available 938302382080 bytes | Actual host-root filesystem baseline |
| Added collector/controller/relay/triggerhappy | All reported inactive, MainPID 0 | The candidate host stack is not running; measurements/physical acceptance cannot be inferred |
| Existing AniMe stats | Active, MainPID 1377 | Previous producer baseline only |
| Deployed blackbox | 1/1 ready, 8h old | Live prober existed before candidate host deployment |

Commands included `uname -r`, system/executable `readlink`, `k3s --version`,
`systemctl show`, `fgconsole`, `stty`, `showconsolefont --info`, read-only sysfs
sensor/backlight files, `df -B1 /` and `kubectl get deployment`. The unsupported
`asusctl --version` query was replaced by its effective executable store path;
no version was inferred from that failed command.

### Actual catalog routes

At **09:43:55 Europe/Oslo**, each catalog target was requested through the
existing blackbox service's Kubernetes service proxy using GET `/probe`, the
generated module identity and its actual catalog target. Every response reported
`probe_success 1` and final HTTP 200, with no query errors. This exercises live
prober egress, rather than substituting VM routes or requesting targets from the
SSH host's network namespace.

| Identity | Actual target | Probe / final HTTP |
| --- | --- | --- |
| glance | `http://glance.glance.svc` | 1 / 200 |
| longhorn | `http://longhorn-tailscale.longhorn-system.svc` | 1 / 200 |
| immich | `http://immich-tailscale.immich.svc` | 1 / 200 |
| grafana | `http://grafana-tailscale.victoria-metrics.svc` | 1 / 200 |
| nix-cache | `http://192.168.1.225:8501/nix-cache-info` | 1 / 200 |
| argocd | `http://argocd-tailscale.argocd.svc` | 1 / 200 |
| kodekamp | `http://kodekamp-web.kodekamp.svc:3000` | 1 / 200 |
| paperless-ngx | `http://paperless-tailscale.paperless-ngx.svc` | 1 / 200 |
| bentopdf | `http://bentopdf.bentopdf.svc` | 1 / 200 |
| amp | `http://amp.amp.svc` | 1 / 200 |
| twitchdropsminer | `http://twitchdropsminer.twitchdropsminer.svc` | 1 / 200 |
| ntfy | `http://ntfy.ntfy.svc` | 1 / 200 |
| immich-share | `http://immich-public-proxy.immich.svc:3000` | 1 / 200 |
| changedetection | `http://changedetection-tailscale.changedetection.svc` | 1 / 200 |
| registry | `http://zot.registry.svc:5000/v2/` | 1 / 200 |
| reclip | `http://reclip-tailscale.reclip.svc` | 1 / 200 |

This is point-in-time connectivity evidence, not a soak or credential-lifecycle
test on the candidate. The administrative SSH session performed these read-only
requests; its kubeconfig/token was never given to the renderer. Scoped candidate
credentials are validated separately in the disposable VM and remain a rollout
check on the laptop.

## Acceptance still required

All owner checklist and resource-table entries in `dashboard-acceptance.md`
remain **pending**. In particular, no physical panel/AniMe darkness, real palette
restoration, keyboard chord behavior, one-metre readability, added-stack resource
measurement or soak has been observed. There is no invented resource threshold.
Record failures and fixes here after separately authorized rollout, rerun the
affected checks and retain #76 until those observations and owner acceptance exist.
