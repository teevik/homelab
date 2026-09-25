# Private cache for the Config nightly builds

Researched: 2026-09-22. Recommendation only; no services, tailnet policy,
credentials, or workflows were changed by this research.

The subsequent implementation and deployment are documented in
[Private Config binary cache](../private-nix-cache.md).

## Recommendation

Use **Harmonia on the homelab, with uploads through a restricted SSH account
over Tailscale and complete NixOS closures retained as Nix GC roots**. Keep
ncps as the existing disposable proxy for public caches. This is the best fit
when the primary requirement is that the latest successful desktop and zenbook
systems remain completely available after CI merges an update.

Harmonia serves an existing Nix store, signs cache responses, compresses
downloads with zstd, and has a native NixOS module. Nix already knows how to copy
complete closures over SSH. Its GC roots protect the toplevel **and every
dependency**, which is the important distinction from retaining recently
accessed individual cache objects. This recommendation is an assessment of
those mechanisms, not a measured performance comparison.
([Harmonia](https://github.com/nix-community/harmonia),
[Nix copy](https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-copy.html),
[Nix GC roots](https://nix.dev/manual/nix/2.35/package-management/garbage-collector-roots))

**Attic is the strongest alternative** if compressed storage, content-defined
deduplication and separate application tokens matter more than exact retention
of complete generations. It needs no S3 deployment: a single native service
with SQLite and local files is supported. Its built-in GC, however, does not
pin a complete system closure. See the retention distinction below before
choosing it.
([Attic NixOS module](https://github.com/zhaofengli/attic/blob/7a19204df10d606c5070e6bb72615c3461900c05/nixos/atticd.nix),
[Attic GC implementation](https://github.com/zhaofengli/attic/blob/7a19204df10d606c5070e6bb72615c3461900c05/server/src/gc.rs))

The previous [Cachix recommendation](nix-binary-cache.md) optimized for avoiding
another operated service and keeping the homelab out of the nightly path.
The requirements now include private Marble/Astal outputs, complete system
closures, and operator-controlled retention. Those requirements justify a
private cache at home. The shared lockfile and build-before-merge design remain
essential.

## Available storage and existing deployment

Read-only SSH measurements on 2026-09-22 found:

| Item | Observation |
| --- | --- |
| Root filesystem | ext4 on the approximately 2 TB NVMe |
| Total | 2,014,587,109,376 bytes, about 1.83 TiB |
| Used | 406,264,905,728 bytes, about 378 GiB |
| Available | 1,505,911,300,096 bytes, about 1.37 TiB |
| `/var/lib/ncps` | about 80 GiB |
| Longhorn data | about 102 GiB |
| `/nix/store` | about 19 GiB |
| Services | ncps, tailscaled and k3s active |

The currently activated desktop runtime closure measured **41.3 GiB** with
`nix path-info --closure-size --human-readable /run/current-system`. This is
one representative existing desktop generation, not a measurement of the new
lockfile, the zenbook, or the unique space required by 14 generations. Shared
dependencies mean generation sizes cannot simply be added together.

There is ample room for a materially larger cache. Start with an operational
budget around **400–500 GiB for retained build outputs**, in addition to the
existing **200 GB ncps limit**. These are proposed budgets, not measured closure
sizes or an automatic Harmonia/Attic byte quota. Preserve at least 300 GiB of
filesystem headroom for Longhorn, uploads, system rebuilds and other growth.
Measure unique added bytes across several nightly runs before expanding it.

The current ncps service is native systemd, uses SQLite and local files, has
CDC disabled, preserves upstream signatures, and disallows PUT/DELETE. Its
endpoint is `http://homelab.tail84b6c.ts.net:8501`. See
[the deployed configuration](../../hosts/homelab/configuration.nix) and
[the earlier ncps analysis](ncps.md). Keeping the new service native avoids
putting Kubernetes and Longhorn in the cache's startup and storage path.

## Project comparison

| Project | Upload and access | Storage and retention | Assessment here |
| --- | --- | --- | --- |
| **Harmonia + Nix** | `nix copy` over SSH; private reads through Tailscale; signed HTTP substitutions | Native store plus real GC roots; zstd on the wire; Nix file deduplication | Best for reliable complete generations with the existing NixOS host |
| **Attic** | `attic push`; scoped pull/push JWTs; private caches | SQLite/local files supported; compressed chunks with deduplication; object-age GC | Best dedicated artifact-cache experience, but closure retention needs extra design |
| **ncps rc17** | `nix copy` HTTP PUT supported; read token and upload signature checking | Compressed local cache; size-based LRU; advertised closure pins have a concrete bug | Retain as proxy; do not depend on stock pins for authoritative CI storage |
| **niks3** | Upload API tokens or OIDC; direct S3 uploads; optional private read proxy | S3 plus PostgreSQL, transactional closure upload and reference-tracking GC | Strong semantics, more infrastructure than necessary on this one local disk |

Sources: [Harmonia configuration](https://github.com/nix-community/harmonia/blob/main/README.md),
[Attic tutorial](https://docs.attic.rs/tutorial.html),
[ncps configuration](https://github.com/kalbasit/ncps/blob/f46d945a61a502827975989b46253ffe66b6db98/config.example.yaml),
[niks3 architecture](https://github.com/Mic92/niks3/blob/main/README.md).

Maintenance was checked against the upstream GitHub APIs on the research date.
Harmonia had released `harmonia-v3.3.0` on September 18 and had commits on
September 20. ncps's latest release was still the `v0.10.0-rc17` prerelease,
with newer main-branch activity on September 21. Attic's latest main commit was
July 6, with no GitHub releases returned; its own documentation still calls it
an early prototype. niks3 had September 22 activity and a September 21
`v1.12.0-beta.3` prerelease. Activity is evidence of maintenance, not a guarantee
of correctness.
([Harmonia releases](https://github.com/nix-community/harmonia/releases),
[ncps releases](https://github.com/kalbasit/ncps/releases),
[Attic commits](https://github.com/zhaofengli/attic/commits/main/),
[Attic status](https://docs.attic.rs/),
[niks3 releases](https://github.com/Mic92/niks3/releases))

## Private connectivity from GitHub Actions

There is no need to expose a public cache endpoint. The official
`tailscale/github-action` can join a GitHub-hosted runner to the existing
tailnet temporarily. The action creates an ephemeral node and logs it out at
job completion. Version 4 supports GitHub OIDC workload identity federation;
the workflow supplies `oauth-client-id`, `audience` and a tag, with
`permissions.id-token: write`. The action documents Tailscale 1.90.1 or later
for this authentication method.
([Official action](https://github.com/tailscale/github-action/blob/main/README.md))

Create a dedicated `tag:config-cache-ci`. Its federated identity should match
the exact `teevik/Config` repository and trusted main-branch workflow, including
the reusable workflow claim where appropriate. Allow only the required
homelab cache ports. The client ID and audience are identifiers, not secrets;
this removes the need for a long-lived Tailscale auth key in GitHub. An SSH key
for restricted import, or an Attic write token, is a separate application
credential and is still required by the selected upload design.
([Tailscale workload identity](https://tailscale.com/docs/features/workload-identity-federation))

Use a grant from the CI tag to a dedicated homelab cache tag/IP and the SSH
import port plus the selected read port. Human machines receive read access.
Review existing broad allow rules: adding a narrow grant does not remove an
existing allow-all grant. Tailnet policy is an access boundary in addition to
the host firewall, even though this host currently trusts `tailscale0`.
([Grants syntax](https://tailscale.com/docs/reference/syntax/grants),
[Grant examples](https://tailscale.com/docs/reference/examples/grants))

If a public endpoint is later preferred, use HTTPS and application-level
authentication for **both** reads and writes. Attic has the clearest native
token model for that topology. Cloudflare's proxied request-size limits can
reject large single-NAR uploads: Free and Pro currently allow 100 MB per
request, Business 200 MB. Storage chunk deduplication does not by itself make
the client's HTTP upload smaller. Tailscale avoids this ingress constraint.
([Cloudflare request limits](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/4xx-client-error/error-413/),
[Attic upload implementation](https://github.com/zhaofengli/attic/blob/7a19204df10d606c5070e6bb72615c3461900c05/client/src/push.rs))

## Proposed Harmonia implementation

1. Run Harmonia on the host with a server-only signing key, bound to loopback
   if ncps fronts it, or a Tailscale-reachable address if clients use it
   directly. Keep the current Nix daemon; a replacement daemon is unnecessary.
2. Add a dedicated SSH import account/key. Restrict its command to Nix store
   import and a narrowly validated root-registration operation; disable shell,
   forwarding, agent forwarding and PTYs. Pin the SSH host key in CI.
3. Sign the uploaded closure with a separate CI signing key. Let the server
   accept that public key for imports while keeping the upload account out of
   Nix's general `trusted-users`, but allow it to connect to the Nix daemon.
   Harmonia's response-signing key stays on the server.
4. After building each host, upload its actual output path with `nix copy`.
   Register its complete closure as a GC root before marking that upload
   successful. Keep the latest successful root per host and, initially, the
   last 14 successful generations. Prune older root records deliberately.
5. Make successful upload, root registration and substitution verification
   prerequisites for publishing/merging the lockfile update.

The NixOS `nix.sshServe` module is a useful starting point: it supplies a
dedicated user, forced Nix command and SSH restrictions. It does **not** supply
the generation registration/pruning protocol described above; that is the small
piece of integration work this design needs.
([NixOS SSH store module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/misc/nix-ssh-serve.nix))

Signed imports are compatible with an untrusted daemon user: Nix's import
handler forces signature checking when the connection is untrusted rather than
rejecting all imports. The selected server/client versions should still be
tested together before deployment. The forced `nix-store --serve --write`
command removes arbitrary shell access but also exposes Nix build operations;
it is not a pure upload-only API.
([Daemon import handling](https://github.com/NixOS/nix/blob/master/src/libstore/daemon.cc),
[Serve protocol](https://nix.dev/manual/nix/2.34/command-ref/nix-store/serve.html))

The publication wrapper can run unprivileged with write access only to its
fixed GC-root subdirectory. Accept a fixed host allowlist (`desktop`,
`zenbook`), a validated generation identifier, and a valid `/nix/store` path;
verify the complete closure exists before creating the retained root. Never
evaluate caller-supplied shell text or accept arbitrary destination paths.
Serialize publication/pruning and fail CI if import or root registration
fails. This integration is more work than Attic's upload token, but directly
buys the complete-generation retention needed here.

A `nix copy` of a toplevel includes its runtime closure, including required
manual outputs and private applications. Build-time tools that are absent
from that runtime closure need separate uploads if caching intermediate builds
is also desired. An SSH destination can substitute public dependencies itself
using `--substitute-on-destination`, reducing runner-to-homelab traffic while
still leaving the complete closure on the homelab.
([Nix copy semantics](https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-copy.html))

Nix storage remains unpacked on this ext4 filesystem. Equal store paths are
shared, and `nix store optimise` can hardlink identical files across distinct
paths, but this is not Attic's chunk deduplication or compressed storage.
([Nix store optimisation](https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-store-optimise.html))

The least disruptive client topology adds loopback Harmonia as an ncps
upstream and trusts Harmonia's public signing key on clients. The existing
ncps URL can remain their entry point. ncps eviction then causes a local
re-fetch from the retained Nix store, rather than loss of the only artifact.
This keeps a compressed second copy of warm paths inside ncps's existing
budget. Direct Harmonia substitution avoids that duplicate if storage becomes
more important than preserving the single-proxy setup.

GC-root retention is not a hard disk cap: protected closures cannot be
collected. Alert on free space and unique closure growth, prune only superseded
generations, and fail the cache publication step before exhausting the disk.
Never discard the latest good root simply because a new upload is incomplete.

## Attic retention and complete uploads

Attic's normal push computes the closure but filters paths signed by configured
upstream caches. For a self-contained copy use
`attic push --ignore-upstream-cache-filter config ./result`. Private caches
support separate pull and push permissions; the server manages cache signing.
SQLite and local files are the native NixOS defaults, with zstd compression
and configurable content-defined chunking available.
([Push options](https://github.com/zhaofengli/attic/blob/7a19204df10d606c5070e6bb72615c3461900c05/client/src/command/push.rs),
[Server storage configuration](https://github.com/zhaofengli/attic/blob/7a19204df10d606c5070e6bb72615c3461900c05/server/src/config-template.toml))

Its GC deletes individual objects whose creation and last-access timestamps
are older than the retention window. It does not traverse live system roots.
The missing-paths API only queries presence; pushing an already-present closure
does not refresh every object's access timestamp. Consequently, configuring
“30 days retention” does not guarantee that every dependency of tonight's
toplevel survives for another 30 days.
([GC deletion predicate](https://github.com/zhaofengli/attic/blob/7a19204df10d606c5070e6bb72615c3461900c05/server/src/gc.rs#L104-L128),
[Presence check](https://github.com/zhaofengli/attic/blob/7a19204df10d606c5070e6bb72615c3461900c05/server/src/api/v1/get_missing_paths.rs),
[NAR access timestamp](https://github.com/zhaofengli/attic/blob/7a19204df10d606c5070e6bb72615c3461900c05/server/src/api/binary_cache.rs#L169-L212))

An initial Attic deployment could disable age-based GC and monitor a conservative
budget, but durable long-term retention then needs an explicit generational
cache/pruning design. Do not present an arbitrary 500 GiB target as an Attic
configuration option or promise complete-closure pinning it does not provide.

## Why not simply turn on ncps uploads?

The exact pinned rc17 source supports `nix copy --to
http://host:8501/upload result`, a read bearer token, and trusted signatures on
uploaded narinfos. The `/upload` prefix bypasses upstream checks, which matters
when uploading a complete local copy. Keeping `sign-narinfo=false` would
require CI signatures on private artifacts and their public key on clients.
([ncps upload documentation](https://github.com/kalbasit/ncps/blob/f46d945a61a502827975989b46253ffe66b6db98/docs/docs/User%20Guide/Usage/Cache%20Management.md),
[Upload signature settings](https://github.com/kalbasit/ncps/blob/f46d945a61a502827975989b46253ffe66b6db98/docs/docs/User%20Guide/Configuration/Reference.md))

Two source findings prevent recommending the current version as the sole
authoritative cache:

- **Write authorization is not covered by its read token.** GET/HEAD token
  middleware explicitly bypasses PUT, POST and DELETE. Pin and unpin handlers
  are registered independently and do not check the PUT/DELETE enable flags.
  A reverse proxy with separate authenticated write routes, or a dedicated
  writer-only Tailscale listener, would be needed. A valid narinfo signature is
  also not authorization to upload arbitrary NAR bytes or manipulate pins.
  ([Server routes and middleware](https://github.com/kalbasit/ncps/blob/f46d945a61a502827975989b46253ffe66b6db98/pkg/server/server.go#L111-L254),
  [Pin handlers](https://github.com/kalbasit/ncps/blob/f46d945a61a502827975989b46253ffe66b6db98/pkg/server/server.go#L719-L797))
- **Recursive pinning uses the wrong hash length.** `GetPinnedClosureHashes`
  extracts **52** characters from dependency references. Nix store-path
  digests are 160-bit Nix32 strings, or **32** characters. Short references
  are skipped and long references include part of the package name in the
  lookup key. Thus pinning a toplevel does not correctly protect its normal
  transitive dependencies. The same algorithm was present on upstream main
  when checked. This is a source-grounded finding, not a live GC test.
  ([Exact rc17 algorithm](https://github.com/kalbasit/ncps/blob/f46d945a61a502827975989b46253ffe66b6db98/pkg/cache/cache.go#L10108-L10192),
  [Nix store-path specification](https://nix.dev/manual/nix/2.34/protocols/store-path.html))

The hash issue was reproduced without touching a running cache by extracting
the constant from the checked-out rc17 source and applying its slicing rules:

| Valid-format dependency reference | rc17 protected key |
| --- | --- |
| `00000000000000000000000000000000-bash-5.2p37` | Skipped: total length is less than 52 |
| `11111111111111111111111111111111-determinate-nix-store-test-support-3.22.5` | `11111111111111111111111111111111-determinate-nix-sto` |

Neither result matches the dependency's real 32-character store hash.
The upstream tests checked explicitly pinned roots, not preservation of a
real dependency graph. The pin implementation also only records a root;
despite the pinning guide's wording, it does not download missing dependencies
at pin time.
([Pin insertion](https://github.com/kalbasit/ncps/blob/f46d945a61a502827975989b46253ffe66b6db98/pkg/cache/cache.go#L10047-L10073),
[Current pin tests](https://github.com/kalbasit/ncps/blob/f46d945a61a502827975989b46253ffe66b6db98/pkg/cache/cache_test.go#L4161-L4255))

A future fixed and tested ncps release could change this ranking: it already
has most of the desired pieces and would avoid another cache service. For now,
its existing proxy role remains useful, while relying on its advertised pins
would risk recreating the missing-dependency problem.

## Acceptance criteria for the eventual migration

Build both hosts from the exact lockfile that will merge. Upload their complete
runtime closures, retain their roots, and verify the cache contains every
closure member before publishing that lockfile. Test private paths, manuals,
and a multi-level dependency graph specifically. Prove a separate empty store
can substitute the resulting system with builds disabled; a warm development
machine alone cannot establish cache completeness.

Also verify that an unauthorized node cannot read the cache, CI cannot reach
unrelated homelab services, the upload identity has no unrestricted shell,
and a GC pass preserves both latest host closures. These checks directly test
the privacy and “everything prebuilt” requirements motivating this change.
