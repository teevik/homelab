# Dashboard validation evidence — issue #76

This record accompanies [the candidate and acceptance runbook](dashboard-acceptance.md).
**The production system has not been accepted.** Remaining physical
darkness/restoration, keyboard and terminal fault checks, sustained measurements
and owner resource acceptance are pending. No candidate deployment, reboot or
production power/service action was performed during preparation.

An authorized actual-laptop rollout began on 1 October 2026; its partial results
are recorded below. Production acceptance and issue #76 remain open.

## Original candidate provenance (merged PR #81)

- Repository baseline: `990e4cc`, integrated main after PRs #77, #78 and #80.
- Validation branch: `codex/issue-76-dashboard-validation`; merged candidate
  revision `ccc42ca37eaf631277e281e2b69cdaebad8ee117`.
- Locked root nixpkgs: `e5bdc4a41d4c072fe1e3787eaa0320a384741d44`.
- Renderer/collector/launcher: health-dashboard 0.1.0; Ratatui 0.30.2,
  Crossterm 0.29.0, Jiff 0.2.37; Rust/Cargo 1.97.1 in the pinned dev shell.
- Kernel 6.18.44; k3s 1.35.7+k3s1; asusctl 6.3.8; Terminus 4.49.1;
  Glance 0.8.5; blackbox 0.28.0. Discovery VM uses operator 0.74.1,
  matching config-reloader, and vmagent 1.150.0 pinned by OCI digest and Nix hash.
- Lockfile SHA-256: `2e84392c5dfef676595d6f6ba6a997d3187a7d2afd33f0fc1723b5c8c59f7099`.
- Built renderer/collector/launcher package:
  `/nix/store/ivbblgw6z3a54r40a87dk8r6vj10xvgq-health-dashboard-0.1.0`.
- Built candidate host closure:
  `/nix/store/nhqa7sqysfyc8c08rllfp6549b4bqcaw-nixos-system-homelab-26.11.20260816.e5bdc4a`.
  Preserve these paths, the exact source revision and lockfile at rollout.

## Original candidate automated results

| Evidence | Result |
| --- | --- |
| Stale controller observation (>15s) rejected by real collector; current-boot verification; failed/absent reports | Regression reproduced, corrected and focused test passed |
| Frozen translated night file expires after 15s and reconnects automatically | Regression reproduced, corrected and real renderer PTY test passed |
| Already-expired or partly-aged night file at launch/relaunch | Both regressions reproduced; real renderer PTY tests pass, rejecting old input immediately and preserving only remaining lifetime |
| Clean k3s exit interrupts a real Secret label transaction | Regression reproduced; all four real k3s VM subtests pass (239.95s), including automatic transaction and reboot recovery |
| Cancelled producer ExecCondition on a slow runner | Deterministic real VM regression passes: zero main/control PIDs, no producer start and dark device state in both inactive and failed/signal outcomes |
| Live footer formats summer/winter Oslo 08:00 on a UTC host | Regression reproduced, corrected and real renderer PTY test passed |
| Expanded API cases: empty, 403, missing timestamps, failed scrape, one old required series amid fresh responses | Focused real collector → frame test passed |
| Actual default 5s host / 30s cluster cadence during slow API requests | Focused scheduling test passed |
| Real renderer kill/error, retries/cancellation/relaunch, ignored q/no idle animation and usable canonical shell input | Expanded launcher PTY test passed |
| Deliberate panic after real terminal setup, child and launcher cleanup; production ignores fault input | Separate test-feature build and PTY check passed |
| Render boundaries/layout focused suites | Passed |
| Integrated login/RBAC/expiry/discovery/network/clock VM | Passed all six subtests, 525.19s; no-IP cold startup, real authenticated SSH and reboot included |
| Full flake/Homelab checks, committed manifests and candidate host build | Passed all 17 x86_64-linux checks; manifest regeneration reported no changes; package and host closure built |

The standalone k3s recovery check is retained at
`/nix/store/7b2z7ffx7x1a4r5rz2lqq862vm2hws9p-vm-test-run-homelab-k3s`.
The successful integrated check is retained at
`/nix/store/fqf6k041wal08hd5ljfry6dxj56lmg4l-vm-test-run-integrated-health-dashboard`.
Its Nix build log records the six production-interface subtests. PR #81's final
full flake invocation passed all 17 checks, rebuilding changed checks and reusing
matching successful outputs for the rest; the host
closure was also built separately because flake checking evaluates, but does not
build, the `nixosConfigurations` output. Final `cargo check --all-targets
--all-features` and all six real renderer terminal tests passed. These are
automated results, with no implied physical or performance acceptance.

The first [PR #81 CI run](https://github.com/teevik/homelab/actions/runs/36835863550)
failed because a cancelled producer gate can leave systemd in `failed/signal`,
while the test required only `inactive`. A held ExecCondition now reproduces
that cancellation deterministically and proves the producer never started;
accepting this stopped state does not weaken the darkness assertions. The
[review finding](https://github.com/teevik/homelab/pull/81#discussion_r4153323668)
about stale reports on relaunch is also reproduced and covered by the startup
file-age and remaining-lifetime terminal regressions.

The next [GitHub run](https://github.com/teevik/homelab/actions/runs/36839832511)
exposed a separate recovery gap in the existing k3s reboot check. k3s shut down
after a transient networking initialization error while a Secret API transaction
was running. In the local reproduction, k3s restarted automatically, but the
failed Secret service stayed failed after API readiness returned. A controlled real label call reproduces
this gap. The shared Secret services now retry failed transactions after five
seconds; the regression verifies automatic service, data, label and traffic
recovery. No production service was actuated.

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

The owner checklist and resource record in `dashboard-acceptance.md` remain open
except for the partial observations below. Physical darkness, global chords,
reboot, fault-case terminal restoration and the sustained soak still require
direct observations. There is no invented resource threshold. Retain #76 until
the remaining observations and owner acceptance exist.

## Authorized rollout — 1 October 2026 (in progress)

The owner authorized rollout, guided physical/service checks and maintenance
reboot while beside the laptop. Times below are **Europe/Oslo**; machine logs use
UTC. The original rollback is generation **97**, retained as a GC root alongside
both candidates. The reboot preflight found 20 healthy attached Longhorn volumes
and an available backup target. No reboot has yet been performed in this record.

- At approximately **12:26**, merged source `ccc42ca` was switched to generation
  **98**, the original candidate closure recorded above. SSH and Kubernetes
  remained available. ASUS 6.3.8's shutdown helper deferred SIGTERM until its
  90-second systemd stop sequence timed out; activation then completed. No forced
  firmware operation was performed.
- Live validation exposed a collector startup regression with **39 evaluator
  groups**: returning on the first waiting group skipped the others' initial
  observations. A two-group API/snapshot regression reproduces this with a single
  simultaneous counter advance; both groups are now observed before reporting a
  failure. Frozen/stale/missing evidence still withholds current alert coverage.
  Type checking, package tests and both code-review axes passed.
- The full flake check at `9ab7c6f` passed all **17** checks, including all six
  integrated VM subtests in **555.07 seconds**. The configuration correction at
  `c2d3222` has the same evaluated host closure as generation 99. Its final full
  flake rerun passed all **17** checks, rebuilding the integrated VM and passing
  all six subtests in **525.69 seconds**.
- At approximately **12:36**, fix `9ab7c6f` was switched to generation **99**:
  `/nix/store/khr5f4rz2isshg4fvjv7c9a4yfx3985i-nixos-system-homelab-26.11.20260816.e5bdc4a`.
  Its package is
  `/nix/store/z5aza98f5mj6zsg39fqq95qg9iisafrs-health-dashboard-0.1.0`.
  The renderer source is unchanged; the owner's existing renderer session
  continued reading the new collector's publications.
- At **12:39–12:40**, all four live sources were current, after the slowest
  evaluator group's next evaluation. The previously observed node-textfile and
  absent-controller alerts cleared automatically. The collector and renderer
  required no manual restart for that source recovery.
- Argo still reports the display-policy VMRule OutOfSync: its CRD defaults
  `record` to an empty string. The generated alert rules now explicitly match
  that default, preserving their expressions and labels. All **374** regenerated
  resources passed schema validation. This cluster correction must be published
  through PR/main/Argo; it has not been manually applied.

### Owner observations and real interfaces

| Case | Observation/result | Remaining qualification |
| --- | --- | --- |
| Existing tty1 password login and dashboard launch | Owner: “Just logged in, everythign seems to be working” | Cold once-per-boot startup and full logout still pending |
| `q`, Ctrl+C, usable shell, normal/mixed/monitoring-down demos | Owner: “All of them worked” after instructions to check status/attention at approximately 1m and ledger up close | These are illustrative inputs rendered on the actual panel; room lighting and explicit glyph inspection still pending |
| Geometry/font/brightness | 160×50, 16×32×256, intended 3122/65535, actual 3084, kernel 6.18.44 | Readbacks support, but do not replace, the owner observations |
| Scoped candidate credential | Metrics/alerts GET 200; Secrets and unrelated proxy GET 403; write access reviews denied; file 0640 root/health-collector and unreadable to unprivileged teevik | Original-token expiry probe is still running; it must actually reach expiry before being accepted |
| Three-minute credential withdrawal and restoration | HTTP/Argo/alert sources reported unavailable while host samples continued; existing OutOfSync signal and recoveries were retained; all four sources returned automatically | No production application outage or manual UI restart was required |
| Glance during collector credential loss | Actual page content returned 16 native monitors, all with positive status icons | This is a collector credential outage, not a claim that the entire metrics service was stopped |
| Physical darkness, wake/chords, service/device recovery | Pending owner result | Device readback is not physical acceptance |

### Initial resource samples

Read `/proc` and service/container cgroup CPU/memory counters every **5 seconds**
for **180 seconds / 37 samples**, recording process CPU ticks, RSS, selected PSS,
`cpu.stat`, `memory.current`, `memory.peak` and membership. CPU percentages below
are of **one core**, on a 16-thread host. The sampler averaged 0.15 seconds per
read; its overhead is separate from the measured service cgroups. Console-helper
children are included in their parent service's cumulative cgroup CPU/memory.

| Component | Previous host baseline CPU | Candidate idle CPU | Candidate memory |
| --- | --- | --- | --- |
| Renderer | Absent | 0.044% | RSS 4.57 MiB; PSS 2.87 MiB |
| Launcher | Absent | 0.000% | RSS 2.50 MiB; PSS needs a later sample |
| Collector and children | Absent | 0.590% | Cgroup 4.87–4.93 MiB |
| Display policy and children | Absent | 1.295% | Cgroup 11.51–12.38 MiB |
| Keyboard relay | Absent | 0.436% | Cgroup 14.49–14.74 MiB |
| Triggerhappy | Absent | 0.001% | Cgroup 0.41 MiB |
| AniMe producer | 0.104% | 0.093% | Cgroup 6.29–7.44 MiB |
| Blackbox | 0.229% | 0.233% | Cgroup 21.59–25.88 MiB |
| vmagent | 4.112% | 3.950% | Cgroup 68.12–104.44 MiB |
| k3s | 40.698% | 37.482% | Cgroup 2335.68–2364.94 MiB |

The previous host already had the cluster probes/monitoring deployed by Argo.
Their absolute costs and paired-window differences are recorded; those
differences are not a causal isolation of the added probe/monitoring overhead.
Unrelated applications and administrative observations continued during these
windows. No numeric resource budget is inferred or accepted on the owner's behalf.

A separate 60-second `strace` attachment counted **15 stdout-write bursts**,
grouping writes within 100ms and retaining no console text (`-s 0`). Most gaps
were approximately five seconds, with additional update/transition bursts; this
is not a per-second animation. The attachment's overhead is not included in the
idle resource window.

During the separate **180-second / 37-sample** missing-credential window, the
collector used **0.226%** of one core and **4.99–5.25 MiB** of cgroup memory;
policy used **1.322% / 11.52–12.95 MiB**, hotkeys **0.441% / 14.49–14.99 MiB**,
and the AniMe producer **0.106% / 7.22–10.29 MiB**. Blackbox used
**0.269% / 21.77–24.86 MiB**, vmagent **4.114% / 67.28–107.15 MiB**, and k3s
**38.185% / 2352.01–2402.36 MiB**. Collection and monitoring remained running.
The same method and attribution limitations apply. Shell/darkness, sustained
history/process growth and owner resource/soak acceptance remain to be completed.
