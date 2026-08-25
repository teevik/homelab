# Nightly Nix binary cache

Status: implementation in progress. The manually dispatched pipeline and laptop
client are live; automatic nightly scheduling is still tracked by
[homelab#37](https://github.com/teevik/homelab/issues/37). The parent
[specification](https://github.com/teevik/homelab/issues/28) remains open until
that final ticket is accepted.

## Recommendation: GitHub Actions and Cachix

Build the exact `flake.lock` proposed for the next update on standard
GitHub-hosted runners, push the resulting Nix store paths to Cachix, and only
then open or refresh one rolling update pull request. The laptop pulls the
merged lock and substitutes the already-built paths from Cachix.

This design is the best fit because:

- `teevik/Config` is public, so standard GitHub-hosted runners are free and do
  not consume a private-repository minutes allowance.
- Cachix does not store paths already available from `cache.nixos.org`, which
  preserves the free cache for custom paths, and removes least-recently-used
  entries at the storage limit.
- The hosted runner and cache keep the homelab out of the critical path: there
  is no new service, credential, exposed endpoint, disk budget, or garbage
  collection policy to operate at home.
- One update job produces one lock artifact for every host build and the pull
  request. The laptop therefore uses the same input revisions that CI built,
  instead of independently resolving whatever `nixos-unstable` exposes later.

The landed implementation is linked rather than duplicated here:

- [GitHub Actions cache workflow](https://github.com/teevik/Config/blob/main/.github/workflows/nix-cache-tracer.yml)
- [Laptop Nix substituter and trusted-key settings](https://github.com/teevik/Config/blob/main/modules/nixos/minimal/default.nix#L70-L92)

The intended routine is: let the workflow update and build, merge the rolling
pull request, pull `main`, and rebuild. Do not run a separate local
`nix flake update`; doing so would select a lock that the pipeline did not
build. Cachix is an accelerator rather than a dependency: the laptop enables
Nix fallback and uses a short connection timeout, so an unavailable cache falls
back to local builds.

## One-time setup checklist

Run [`scripts/nightly-nix-cache-setup.sh`](../../scripts/nightly-nix-cache-setup.sh)
from the homelab repository root. It walks through these steps and records only
non-secret decisions under the ignored `.scratch/nightly-nix-cache/` directory:

- Create the public Cachix cache and record its URL and public signing key.
- Store a write-capable Cachix token in `teevik/Config` as the
  `CACHIX_AUTH_TOKEN` Actions secret.
- Create read-only deploy keys for the private `teevik/marble-shell` and
  `teevik/astal` flake inputs, then store their private halves in
  `teevik/Config` as `MARBLE_SHELL_DEPLOY_KEY` and `ASTAL_DEPLOY_KEY`.
- Keep the Cachix cache public but exclude `marble` and `astal` outputs from
  uploads. This `push-filter` decision avoids making build outputs from private
  inputs publicly downloadable while still caching the rest of each host
  closure.
- Allow GitHub Actions in `teevik/Config` to create pull requests using the
  repository-scoped `GITHUB_TOKEN`.
- Confirm the nightly x86_64 host list (`desktop` and `zenbook`).

The current cache is `https://teevik.cachix.org`, with public key
`teevik.cachix.org-1:lh2jXPvLIaTNsL8e8gvrI2abYe83tKhV0PmxQOGlitQ=`.
Secrets themselves are never written to the setup file.

## Why lock synchronisation is the crux

A binary cache is keyed by exact Nix store paths, which include the complete
derivation inputs. Two independent `nix flake update` runs can resolve different
revisions even on the same day, so a locally updated laptop can miss every path
that CI just built. Building all hosts from one uploaded `flake.lock` artifact
and committing that same artifact in the rolling pull request removes this
race.

Building a full NixOS toplevel also matters: it realizes the custom packages,
overlays, and small system-specific derivations that `cache.nixos.org` cannot
provide. The accepted matrix run showed that the `desktop` and `zenbook`
closures fit after runner disk cleanup; subsequent runs reuse cached paths.

## Optional: LAN cache on the homelab

A LAN cache remains useful if hosted-cache latency, capacity, or pricing becomes
a problem. It is an optional speed upgrade, not part of the nightly pipeline.
It does not replace lock synchronisation: the laptop must still consume the
same lock whose outputs were built into the cache.

### Harmonia

[Harmonia](https://github.com/nix-community/harmonia) is the simpler Nix-native
choice for serving signed paths already present in a machine's Nix store. A
homelab deployment would need a builder to realize each updated host closure
into that store, a signing key, an HTTP endpoint reachable by clients, and a GC
policy that retains useful paths. Its appeal is a small moving-parts count and
LAN-speed substitution; its cost is that the homelab becomes an operated
dependency with credentials, storage, monitoring, and availability concerns.

### Attic

[Attic](https://docs.attic.rs/) is the heavier alternative when multiple caches,
access tokens, content-addressed global deduplication, and configurable garbage
collection are worth running a dedicated cache service and database. Those
features offer more control than Harmonia, but they solve needs this personal
pipeline does not currently have. Reconsider Attic if the cache grows into a
shared or multi-tenant service rather than adding it pre-emptively.

## Sources

- [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- [Cachix pricing and retention behavior](https://www.cachix.org/pricing)
- [Cachix: What is a binary cache?](https://docs.cachix.org/what-is-a-binary-cache)
- [Harmonia repository](https://github.com/nix-community/harmonia)
- [Attic documentation](https://docs.attic.rs/)
