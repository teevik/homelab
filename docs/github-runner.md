# Config nightly runner

`github-runner-config-nightly.service` runs natively on homelab as the dedicated,
unprivileged `config-runner` user. Its only GitHub label is
`homelab-config-nightly`. The Config nightly workflow prepares shared dependencies
first, then builds desktop and zenbook sequentially on this one runner. Lint/PR
checks, the weekly security workflow, and opening the update PR stay on GitHub.

The CI Nix daemon uses the existing `/nix/store` and database. Existing outputs
need no download or rebuild. Missing paths use ncps at `10.254.254.1:8501`, then
public upstream caches or a local build. ncps's compressed archive storage is
separate from `/nix/store`.

## Boundaries

- Labels alone do not authorize workflows. The runner package has a small,
  fail-closed policy in `scripts/runner/HomelabJobPolicy.cs`. It checks GitHub's
  authenticated job message before job initialization, action downloads or any
  steps, including `always()` steps. It admits only repository ID `908743957`,
  owner ID `9365365`, the Config nightly workflow on `main`, a scheduled/manual
  event, and the reusable `nix-build.yml` workflow. It does not trust job-provided
  environment variables or rely on an ordinary job-start hook.
- The account is neither wheel nor a trusted Nix user. There is no sudo,
  Docker/containerd socket, host Nix socket, Kubernetes credential, home directory,
  Tailscale socket, signing key or SSH upload key available to jobs.
- The service has no capabilities, `NoNewPrivileges`, a read-only system view,
  hidden other-user processes, private temporary files, and a private network
  namespace. The namespace admits public egress and only port 8501 on the host;
  LAN, tailnet, cluster and metadata networks are blocked. It accepts no forwarded
  inbound connections except replies. DNS uses Cloudflare's public resolvers.
- Runner processes and workspace are discarded after each job. Root restores
  registration state from an inaccessible backup before starting the next job,
  so job-written `.env`, `.path` and altered credentials cannot persist.
- The native jobs receive no cache secrets and use a read-only repository token.
  Opening the PR happens separately on GitHub. The receiving job validates the
  artifact against its own package catalog, rejecting extra files and symlinks
  before copying anything into its checkout.

This remains a native shared-kernel service, not a VM isolation boundary. An
accepted job can read the shared Nix store and contact the public internet.
Compromised upstream tools or a Nix/kernel/runner vulnerability remain risks.
Never place plaintext credentials in the Nix store or approve arbitrary workflows
for this runner. GitHub's general guidance favors private repositories for
self-hosted runners; this public repository needs the additional runner-side gate.

## Resource and cache policy

The runner, its Nix daemon and retention workers share `config-ci.slice`: six
logical CPUs of quota, 14 GiB memory high threshold, 16 GiB memory maximum, no
swap, and low CPU/I/O priority. Nix builds at most two derivations with four cores
each. Limiting only the runner service would not limit daemon-spawned builds.

The daemon has fixed pre/post-build hooks. Before a build it checks for 300 GiB
free disk space. Successful outputs are rooted under
`/nix/var/nix/gcroots/config-ci-pending` before completion is acknowledged, including
when a later build fails. CI's periodic/final flush asks an unprivileged local
socket service to move these into the existing 14-day/250-GiB dependency policy.
Failed publication leaves pending roots protected. Complete host closures keep
the existing 14-generation retention and HTTP signature/archive checks.

The Unix API only permits retaining existing outputs, publishing a recognized
host system, and flushing the fixed pending directory. It cannot execute a
command, import unsigned paths, read keys or choose a different root directory.
Harmonia signs cache metadata using its own protected key; CI does not sign or
copy paths already in this store.

If repeated failures leave pending roots, inspect the cache worker journal and
fix publication before manually removing roots. The disk headroom check applies
before builds, not as a hard filesystem quota during one large build.

## Operations

Initial setup (also needed if changing registration fields or replacing the
registered identity):

```sh
python3 scripts/runner/register.py
just deploy
```

The helper captures a one-hour GitHub registration token using the already
authenticated `gh` CLI and sends it directly to a root-only file on homelab. It
does not print it, write it into Git/Nix, or install a long-lived GitHub PAT. The
established runner registration survives token expiry, restarts and reboots.
Changes to registration fields require a fresh token; normal package/service
updates preserve the registered identity.

```sh
ssh homelab sudo systemctl status github-runner-config-nightly config-ci-nix
ssh homelab sudo journalctl -u github-runner-config-nightly -u config-ci-nix
ssh homelab sudo systemctl status config-ci-cache.socket
ssh homelab sudo systemd-cgtop
```

Keep the runner release current. `runner-nixpkgs` is an independent flake input
so this does not require updating the Kubernetes host's package set:

```sh
nix flake update runner-nixpkgs
nix build .#config-github-runner
just deploy
```

The runner's Nix build runs upstream tests plus the authorization tests. GitHub
requires self-hosted runners with automatic updates disabled to be updated within
30 days of a new release. The service currently uses upstream `--once` to recycle
each job without a persistent registration PAT; upstream warns that this option
will be deprecated. If it is removed, migrate to ephemeral registration backed by
a narrowly scoped GitHub App, preserving the policy and process cleanup.

## Verified on 2026-09-25

- Runner 2.337.0: 1,090 tests passed, including the nightly allowlist and rejection
  of PRs, `pull_request_target`, other refs, repositories and workflows.
- Config's security/workflow check passed, including native publication and
  artifact injection tests. The existing cache tests and new local API tests pass.
- In the running service's mount/network namespaces, as its UID with no new
  privileges: credential/admin socket reads fail; GitHub and ncps work; cluster,
  host SSH and LAN connections fail. The service has no Linux capabilities.
- The untrusted client cannot disable Nix's sandbox. A real sandboxed build took
  5.93 seconds, a repeat took 0.05 seconds, and local output retention succeeded.
- Kubernetes' admin kubeconfig was world-readable (`0644`). It is now `0640`,
  root:wheel, configured persistently; the runner cannot read it.
- A redacted gitleaks scan of Config's published `main` history (379 commits)
  found no credentials. Homelab history contains old generated secret material;
  flagged values did not match current SOPS secrets or the live Argo CD secret.
  The old flagged VictoriaMetrics webhook secret no longer exists in the cluster.
  These checks do not establish that every historical third-party credential has
  been revoked, and do not cover unpublished local checkpoint/log contents.

Sources: [GitHub self-hosted runners](https://docs.github.com/en/actions/concepts/runners/self-hosted-runners),
[security guidance](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions),
[runner job initialization](https://github.com/actions/runner/blob/v2.337.0/src/Runner.Worker/JobExtension.cs),
[runner updates](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/monitor-and-troubleshoot).
