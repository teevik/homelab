# Private Config binary cache

The native NixOS module `modules/nixos/nix-cache.nix` runs Harmonia against the
homelab's Nix store. The existing ncps proxy serves clients at
`http://homelab.tail84b6c.ts.net:8501`, using loopback Harmonia as another
upstream. Tailscale encrypts and controls access to this endpoint. There is no
public ingress or new public firewall opening.

## Upload and retention

Config's reusable `nix-build.yml` workflow builds a NixOS toplevel, signs its
entire runtime closure, then copies it over SSH to port 2224. This includes
private packages, manuals and outputs built before the main build step.
Build-only outputs have separate bounded retention. Config's fast post-build
hook roots completed outputs locally while a background uploader signs and
copies batches. The updater and shared Nix/plugin bootstrap use this same path.
The bootstrap is published once before the parallel desktop/zenbook jobs.

The `nix-cache` account is an untrusted Nix daemon user. Its dedicated SSH key
can invoke only the forced dispatcher: Nix store transfer, space preflight,
validated generation publication for desktop or zenbook, and `cache-retain`
for allowlisted dependency groups (bootstrap, updater, desktop, zenbook, seed). The underlying
Nix serve protocol also supports sandboxed build operations; this is not an
upload-only protocol. Shell commands, forwarding and PTYs are disabled.
Imported input-addressed paths require trusted signatures.

After import, publication registers the toplevel beneath
`/nix/var/nix/gcroots/config-cache/HOST/GENERATION`. Nix protects every runtime
dependency of that root. Publication verifies the closure and updates `latest`
before pruning old roots. Failed imports or verification leave the previous
latest generation protected. Publication and pruning are serialized.

Retention is the latest **14 successful publications per host**, including the
latest one. Identical store paths are shared between hosts and generations.
The settings in the module are:

| Setting | Purpose |
| --- | --- |
| 500 GiB retained closure budget | Warn in the CI upload log; not a hard cap |
| 250 GiB dependency closure budget | Evict oldest dependency batches to stay within this separate cap |
| 14-day dependency lifetime | Expire batches during publication and before daily GC |
| 300 GiB filesystem headroom | Reject uploads/publications below this reserve |
| 200 GB ncps cache | Existing compressed, disposable proxy storage |
| Daily 05:45 Nix GC | Collect paths no longer protected by any root |
| Automatic Nix optimisation | Hardlink identical files in the store |

Preflight conservatively subtracts the whole incoming closure, even if some
paths already exist. The reserve is an admission check, not a disk quota;
concurrent uploads and other services can consume space after the check.
Never delete a latest root to make a failed upload appear successful. Review
superseded generations and other disk consumers when headroom runs low.

`cache-retain GROUP GENERATION` accepts a bounded JSON list of store outputs on
stdin. Derivation roots are rejected, and missing outputs never trigger builds.
Each batch is registered beneath `config-cache/dependencies/GROUP/GENERATION/DIGEST`
before inspecting its closure. Receipts include a digest and count of the entire
closure. Retries refresh an existing batch. Failed validation removes only roots
created by that request. Dependency budget accounting deduplicates shared paths;
old dependency roots can be evicted even within a generation. System-generation
roots remain independent. A batch larger than 250 GiB is rejected before evicting
other batches. The daily GC prunes expired dependency roots as `nix-cache` first.

Eviction from ncps does not delete retained Nix paths. Harmonia can serve them
again. Complete closure retention, not ncps's object LRU, provides durability.

## Credentials and network policy

Public keys are under `hosts/homelab/cache/`. SOPS `secrets.yaml` contains:

| Entry | Use |
| --- | --- |
| `nix_cache_signing_key` | Harmonia response key; only this secret is deployed |
| `nix_cache_ci_signing_key` | Encrypted backup of GitHub `NIX_CACHE_SIGNING_KEY` |
| `nix_cache_upload_key` | Encrypted backup of GitHub `NIX_CACHE_SSH_KEY` |

CI joins the tailnet with an ephemeral OIDC identity using
`tag:config-cache-ci`. Its grant permits only TCP 2224 and 8501 on
`100.80.229.65`. Broad existing grants must exclude this tag. Policy tests deny
normal SSH, HTTPS and the Kubernetes API on the homelab. Human machines keep
their existing tailnet access. The dedicated SSH listener pins the homelab's
existing Ed25519 host key in Config's `.github/cache/known_hosts`.

The OIDC credential matches subject
`repo:teevik/Config:ref:refs/heads/main` and custom `job_workflow_ref`
`teevik/Config/.github/workflows/nix-build.yml@refs/heads/main`. Repository
variables `NIX_CACHE_TS_CLIENT_ID`, `NIX_CACHE_TS_AUDIENCE` and
`NIX_CACHE_POLICY_READY=true` are required. The two cache secrets are already
configured in GitHub; policy/identity setup requires a Tailscale administrator.

For key rotation, update the encrypted secret and corresponding public key.
Deploy a new CI verification key before changing its GitHub signing secret;
replace the authorized SSH key alongside its GitHub secret. A Harmonia key
rotation also needs the new public key trusted in Config clients/workflows
before removing the old one. Update `known_hosts` if the host key changes.

## Operations

Deploy from this repository:

```sh
nixos-rebuild switch --flake .#homelab --target-host homelab --sudo --no-reexec
```

Inspect without changing retention:

```sh
ssh homelab 'systemctl status harmonia.socket harmonia.service ncps nix-cache-sshd'
ssh homelab 'sudo ls -l /nix/var/nix/gcroots/config-cache/{desktop,zenbook}'
ssh homelab 'df -h /nix/store; systemctl list-timers nix-cache-gc.timer'
ssh homelab 'sudo journalctl -u nix-cache-sshd -u harmonia -u ncps -n 60'
```

Run publication boundary and retention tests:

```sh
nix build .#checks.x86_64-linux.private-nix-cache --no-link --print-build-logs
```

The Config publisher additionally compares the remote closure digest/count,
cryptographically verifies cache signatures for every member, and requests
each NAR with HEAD before letting the nightly PR proceed.

## Deployment verification (2026-09-22)

The homelab configuration was built and activated. A four-path test system
with a separate manual output and private dependency was signed, uploaded,
rooted and verified through ncps. Unsigned imports and shell commands were
rejected. An empty isolated store downloaded all four paths, verified their
signatures and contents, and retained them through a GC pass. The homelab
daemon also reported the publication's actual GC roots. Test roots were then
removed.

This verifies the service and publication path. The first real desktop and
zenbook nightly run still needs the Tailscale admin setup and the Config
workflow changes on main; that run supplies the full production closures.

## Dependency retention deployment (2026-09-23)

The dependency retention endpoint and pre-GC expiration were built, tested and
activated. Live single- and multiple-root publications passed signed cache
verification, and the daemon reported their actual GC roots. An empty isolated
store downloaded and content-verified the fixture, retaining it through GC. Config now prepares the updater/bootstrap within the existing
OIDC-bound reusable workflow, so no Tailscale credential changes are needed.
Desktop seeding uses the encrypted CI upload/signing backups and copies existing
paths only; it does not compile on the homelab.

The desktop seed completed with 17,847 retained outputs (88.6 GiB), all verified
through the private HTTP cache. About 1.3 TiB remained free after import.
