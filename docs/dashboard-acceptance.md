# Integrated laptop dashboard acceptance

Validation for [#76](https://github.com/teevik/homelab/issues/76), against the
approved [#72](https://github.com/teevik/homelab/issues/72) spec. The render,
collection/startup and night-control implementations are already integrated in
main through PRs #78, #80 and #77. The validation baseline is `990e4cc`.

**Owner decision on 1 October 2026:** close #76 and #72, leave the deployed
dashboard running, and check it remotely through the next morning. Remaining
physical acceptance checks below are deferred, not passed. The authorized rollout,
completed initial one-hour capture and observation limits are recorded in
[the evidence record](dashboard-evidence.md). Preparing or building another
candidate alone does not authorize new production actions.
The completed design maps and approved hierarchy remain unchanged.

## Reproduce the candidate

From the validation commit with a clean worktree and the committed lockfile:

```sh
git status --short
nix develop --no-update-lock-file --command nixidy switch .#homelab
git diff --exit-code -- manifests
nix flake check -L --no-update-lock-file --max-jobs 2 --cores 2
nix build --no-update-lock-file --out-link result-dashboard .#health-dashboard
nix build --no-update-lock-file --out-link result-candidate \
  .#nixosConfigurations.homelab.config.system.build.toplevel
git rev-parse HEAD
nix path-info ./result-dashboard ./result-candidate
sha256sum flake.lock
```

Keep the commit, lockfile hash, both store paths and full validation logs in the
acceptance record. These identify a concrete build, independent of a moving
branch name. The candidate's host closure and renderer/collector/launcher package
are reproducible Nix outputs; mutable application image downloads are subject to
the existing [image-build limitations](testing.md).

The manifest command renders files only. Never manually apply the production
manifest tree. On pushed main Argo CD owns cluster reconciliation, including
PreSync hook ordering. No new application image build contexts change here.

## Automated evidence

| Requirement | Public boundary and check |
| --- | --- |
| All 15 approved states, signal/gap counts, shared-app deduplication, tier/catalog order, onset, overflow, optional sensor | `packages/health-dashboard/tests/scenarios.rs`, snapshot → derivation → frame |
| Exact 3m versus older, failed refresh, host failure, required entry absence/age, retention, source return, 15m recovery expiry | `tests/boundaries.rs` at that same renderer seam; real collector fixture API checks |
| 160×50, growth, long text, compact thresholds and tiny sizes, fixed band, scroll bounds/cues, 16 foreground/8 background slots, no attributes | `tests/layout.rs`, `examples/render_console.rs` |
| Actual default 5s host / 30s cluster scheduling with slow APIs and independent host sampling | `scripts/test-health-scheduling.py`, `health-collector` check |
| Malformed/empty/missing/stale data, missing true timestamps, failed scrape, timeout, 401/403, retained failures, automatic return, atomic credential replacement | `scripts/test-health-collector.py`, real collector → snapshot → renderer |
| Frozen evaluator despite fresh API responses, bounded history and recovery expiry under clock jumps | `health-dashboard-vm`, actual collector and API boundary |
| Changed catalog entries produce consistent ordered Glance/probe/TUI identities and expectations; separate expected app inventory | `health-catalog` check |
| Pinned Glance and blackbox GET, redirects/final status, auth rejection, TLS verification, timeout and central overrides | `health-http` check; Glance's monitor calls its targets without a metrics dependency |
| Scoped service-proxy GET, unrelated-operation denials, absent/expired credentials, renewal/restart | `health-dashboard-vm`, real k3s apiserver and production RBAC/renewal service |
| VMProbe discovery and policy routes | `health-dashboard-vm`, deployed operator/vmagent/blackbox versions, generated CRDs/VMProbes and production network policies |
| Ctrl+C, ignored q, relaunch, error, panic, kill, retry exhaustion/cancellation, real shell echo/canonical input, cursor/screen/palette reset | `tests/terminal.rs` and `scripts/test-dashboard-launcher.py`, `TERM=linux` PTYs; panic uses an explicitly separate test-feature build |
| tty1 once per boot; full logout/password authentication; later tty1 launch; SSH/other-VT/nested-shell exclusions; cold startup | `health-dashboard-vm`, actual NixOS login and shell hook |
| Schedule edges, both Oslo DST transitions, clock/missed boundaries, next-morning bedtime, wake/cancellation/resume/expiry, boot persistence, serialization | `display-policy` deterministic policy → recording devices |
| Dark defaults, producer gate, off-before-console transitions, lid/battery/daytime restrictions, device and hotkey/asusd recovery | `display-policy-vm`, production services with simulated device boundaries |
| Controller/collector report absence, failure, wrong boot and age; global requests survive UI exit | Real collector fixtures, renderer PTY heartbeat test and integrated VM |
| Full host/package build, schema/invariant validation and identical complete manifest tree | Full `nix flake check`, including `manifests`, `k3s` and private-cache checks |

The integrated VM stubs metrics/Alertmanager and device/application content, uses
disposable credentials, and preloads the pinned upstream operator/prober images.
Its AMP/Nix Cache/KodeKamp routes are synthetic. The separately recorded **live
blackbox GETs** are actual laptop connectivity evidence. Neither kind proves
physical darkness or readability. No fixture credential or admin kubeconfig is
provided to the renderer.

Focused commands are available without a full host rebuild:

```sh
nix build -L --no-link .#checks.x86_64-linux.health-dashboard-vm
nix build -L --no-link .#checks.x86_64-linux.health-collector
nix build -L --no-link .#checks.x86_64-linux.health-http
nix build -L --no-link .#checks.x86_64-linux.health-catalog
nix build -L --no-link .#checks.x86_64-linux.display-policy-vm
nix develop --command cargo run \
  --manifest-path packages/health-dashboard/Cargo.toml \
  --example render_console -- .scratch/dashboard-renders
```

## Separately authorized rollout and rollback

Before rollout, arrange an owner physically at the laptop and an independent SSH
session. Record the currently booted `/run/current-system` and
`/nix/var/nix/profiles/system` targets, generation list, kernel, package versions,
Argo revision and desired brightness. Save the existing policy state if one
exists; retain the candidate and previous host closures as GC roots. Do not
delete or reset bedtime state as a shortcut to acceptance.

1. Obtain explicit authorization for the exact candidate commit/store path,
   rollout window, reboot and the physical/service fault cases below. Confirm
   SSH stays available while tty1 is dark. Record baseline resources first.
2. Review Argo's current revision and sync result. If cluster configuration needs
   publication, use the repository PR/main/Argo path. No manual production apply.
3. After that authorization, use the normal `just deploy` workflow from the
   pinned candidate checkout (or the agreed deployment of that exact closure).
   Capture rebuild output and `/run/current-system`; verify it equals the built
   candidate. A later authorized reboot verifies the booted kernel and once-per-
   boot login behavior rather than merely a configured kernel/store path.
4. Check SSH, host sampling, scoped renewal, all four sources and controller
   application state. Ctrl+C must yield a usable shell while collection and
   policy continue. Complete the checklist and resource record before acceptance.
5. If a functional or physical check fails, record it, fix the relevant component
   and repeat the affected automated **and** physical checks before recording
   acceptance. The owner elected to close #76 with the remaining physical checks
   deferred on 1 October; that decision does not turn missing results into passes.

For a rollback to a controller predating away mode, first follow the deliberate
[state conversion](display-policy.md#time-state-and-recovery); the older daemon
fails closed on the new state key, including when away mode is false.
For an authorized host rollback, select the recorded previous generation with
the normal NixOS rollback workflow (`nixos-rebuild switch --rollback` only when
that recorded generation is the immediately previous one). Otherwise switch the
system profile to the recorded generation and invoke that generation's
`switch-to-configuration switch`, then separately authorize any needed reboot.
Confirm SSH and the resulting system target. Cluster rollback is a reviewed Git
revert through main and Argo; never mix a host rollback with a manual manifest
apply. The older host has no independent night controller: the owner must account
for that during rollback rather than assuming darkness remains enforced.

## Owner checklist and observation record

For **each case**, record observer, Europe/Oslo timestamp, candidate commit/store
path, booted kernel/packages, geometry/font/brightness, input/action, directly
observed result, supporting logs and pass/fail. A missing observation is deferred under the owner's closure decision.
Successful writes/readbacks, screenshots and VM results cannot pass physical cases.
The entries below retain the complete original checklist; partial completed
observations and the chosen closure scope are recorded in the evidence document.

- [ ] Actual tty1: confirm eDP panel/amdgpu driver, 160×50 console and 256-glyph
  16×32 font. Inspect `! ? ■ ▲ ·`, `─ │ ↑ ↓` and chart symbols on the real panel.
  Exercise ALL CLEAR, ATTENTION, UNKNOWN, partial coverage, long live names,
  compact fallbacks and enlarged scrolling while preserving hierarchy.
- [ ] Owner reads main status and attention from approximately 1m in each verdict;
  reads ledger detail up close. Record viewing distance, ambient light, geometry,
  font, intended/actual brightness and any unreadable text. Bitmap dimensions do
  not establish this result.
- [ ] Actual palette and terminal restoration: ordinary shell colours before and
  after Ctrl+C, relaunch, error/panic/kill and exhausted retry. Confirm echo,
  canonical input, visible cursor, screen restoration and the handoff wording.
- [ ] Full logout reaches authenticated login; password entry precedes the later
  tty1 dashboard. Verify SSH, another VT and a nested shell do not auto-launch.
  After an authorized cold reboot, tty1 launches before networking, Kubernetes
  or credentials are available and host data arrives independently.
- [ ] Observe continuous panel/backlight **and AniMe** darkness after OS control
  is available at 23:00, overnight, at early bedtime, and through morning at 08:00.
  Record firmware/early-boot illumination separately.
- [ ] While dark, random keys/mouse, alerts/refresh, Ctrl+C, shell output, all text
  VTs, lid/AC transitions, producer/controller/hotkey/asusd restart/reload and
  getty/device recovery cause no visible reillumination or flash. Unsupported
  panel-off control fails acceptance. AniMe flashing requires a policy-aware
  daemon fix and retesting; later polling correction is insufficient.
- [ ] Real Ctrl+Alt+Home / End / Insert chords at UI, shell and authenticated
  login while dark, plus the four SSH commands. Verify actual Fn mappings, no
  leaked chord input/actions, no autorepeat renewal and preserved ordinary keys,
  Ctrl+C and VT switching. See [display policy](display-policy.md).
- [ ] Persistent away mode (Ctrl+Alt+Home) remains dark across morning boundaries
  and reboot until Ctrl+Alt+Insert resumes the current schedule.
- [ ] Screen-only ten-minute wake and renewal; bedtime cancels wake; resume at
  night stays dark; expiry across 08:00 recomputes daytime policy. Same-boot
  controller recovery retains the remaining wake; reboot clears wake but retains
  bedtime. Daytime brightness and lid/battery restrictions recover correctly.
- [ ] CPU/package sensor or explicit unavailability and genuine host-root capacity
  match independent readings. Every catalog endpoint and expected app is covered,
  including real AMP, Nix Cache and KodeKamp routes. Verify scoped credentials and
  renewal on the deployed candidate. Observe controlled source failure/return
  without UI restart, no false recovery, and Glance reachability during the outage.
- [ ] Host/cluster/collection/monitoring continue through darkness, shell handoff
  and independent component recovery. Controller failures are reported without
  deliberately illuminating the screen.
- [ ] Whole-stack resources and soak are recorded below and accepted by the owner.

## Resource measurement and soak

Record the **method, sampling interval, elapsed duration and package versions**
before collecting results. Measure baseline with the previous system, then the
same workloads on the candidate; note unrelated application/backup activity.
Choose and record observation/soak durations with the owner. At preparation, no
CPU/RAM budget or soak duration was approved. The authorized 1 October rollout
uses three-minute phase samples and an initial 60-minute soak; no numeric resource
budget was approved. Measurements still require owner judgment. The completed initial capture and
partial physical results are recorded in [the evidence record](dashboard-evidence.md).

Include renderer, launcher, transient curl/console helpers, collector, policy,
relay, triggerhappy, AniMe producer and blackbox probes; record incremental
vmagent/monitoring overhead too. `pidstat -u -r -p ALL <interval> <count>` captures
per-process CPU/RSS. Sample service cgroups' `cpu.stat`, `memory.current`,
`memory.peak` and `cgroup.procs` to include transient children and detect leaks;
identify the blackbox pod's cgroup with the container runtime. Record PSS from
`smaps_rollup` when comparing shared memory instead of summing RSS blindly.

For renderer redraw frequency, first confirm an event count in a fixture PTY;
on the candidate record terminal-write bursts with an explicitly identified
measurement tool, including its overhead. For example an authorized short
`strace -tt -e write,writev -p <renderer-pid>` run observes writes; group bursts
into frames and distinguish input/resize/5s host changes from idle clock updates.
Write counts alone are not frame counts. Never infer resource use from language.

| Phase | Baseline/candidate, duration | CPU/core time | RSS/PSS/cgroup memory | Redraws/triggers | Process/history growth | Owner result |
| --- | --- | --- | --- | --- | --- | --- |
| Idle, normal host/cluster sampling | Previous/candidate, 180s each | Recorded in evidence | Recorded in evidence | Separate 60s write-burst capture | Recorded in evidence | No numeric budget set |
| Successful refresh | Candidate, 180.03s | Recorded in evidence | Recorded in evidence | Normal source advancement | Recorded in evidence | No numeric budget set |
| Failed/partial source and automatic return | Candidate credential withdrawal, 180s | Recorded in evidence | Recorded in evidence | Automatic return observed | Recorded in evidence | No numeric budget set |
| Ctrl+C and sustained shell handoff | Ctrl+C observed; sustained window deferred | Deferred | Deferred | UI absent after Ctrl+C | Deferred | Partial owner observation in evidence |
| Quiet hours/bedtime and screen-only wake | Deferred | Deferred | Deferred | Deferred | Deferred | Deferred |
| Sustained soak, catalog failures and recoveries | Initial 60 minutes complete; longer soak deferred | Recorded in evidence | Recorded in evidence | Transient Argo source failure and affirmative recovery recorded | History 20→80; recoveries 0→1; one UI/collector per sample | Owner chose continued operation; no numeric budget set |

During the soak, sample temperature-history length (bounded to 90 minutes),
recovery count (at most 128, entries expire at 15m) and process/cgroup membership.
Check trends over time, not just one final value. Record unresolved physical,
readability, resource or recovery results honestly and retest before claiming
complete acceptance. The owner's closure decision defers the remaining checks;
the hourly read-only follow-up does not replace physical observation.
