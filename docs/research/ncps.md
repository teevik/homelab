# ncps settings for the homelab

Status: updated 2026-09-05. The configuration now pins
[`v0.10.0-rc17`](https://github.com/kalbasit/ncps/tree/v0.10.0-rc17), commit
`f46d945a61a502827975989b46253ffe66b6db98`, using upstream's Nix package.
Its own nixpkgs input is retained because it needs Go 1.26.6, while the
homelab's pinned nixpkgs supplies Go 1.26.5. Deployment remains manual.

## rc17 compatibility and rollout

The initial 0.9.4 recommendation below is superseded for package version.
Live rebuilds exposed two incompatibilities in that version:

- Cachix UUID-style NAR URLs returned HTTP 500 `invalid nar hash`.
- Numtide narinfos without optional `FileSize`/`FileHash` fields were rejected,
  producing false cache misses.

Both fixes are present in
[the rc17 source and changelog](https://github.com/kalbasit/ncps/blob/v0.10.0-rc17/CHANGELOG.md).
An isolated instance using the homelab's generated JSON configuration verified
the previously failing Cachix `iasg2pmmi788yhgic9mgq3wfxvpsxsxw` and Numtide
`ik4nra9yn4n6w8salv7v6rq59s214d52` paths: HTTP 200, matching compressed-file
and unpacked NAR hashes, original signatures preserved, and successful warm
downloads. A `cache.nixos.org` path was also verified.

**Do not migrate the existing 0.9.4 SQLite database in place.** A populated
disposable 0.9.4 database lost its signature, reference and NAR-link rows when
upgraded with rc17's `ncps migrate up`, despite the migration completing and
SQLite integrity checks passing. The migrated narinfo was consequently served
without its original signature. A fresh rc17 database passed the same download
and signature checks.

The configuration keeps `/var/lib/ncps`, with its database at
`/var/lib/ncps/db/db.sqlite`. At the user's request, discard the old cache once
before the first rc17 deployment instead of keeping a second state directory.
Stop the old service before clearing its state so it cannot recreate a 0.9.4
database. On the currently deployed unit, `StateDirectory=ncps`, so the manual
reset is `sudo systemctl stop ncps` followed by
`sudo systemctl clean --what=state ncps` on the homelab. This deletes the old
database and cached NARs; they must be fetched again. Do not repeat this cleanup
on normal deployments.

After clearing state, recreate the configured database and temporary directories
with `sudo systemd-tmpfiles --create --prefix=/var/lib/ncps` before starting the
service. An unchanged tmpfiles configuration may not rerun during deployment;
without `/var/lib/ncps/tmp`, the service fails during systemd mount-namespace
setup, before `preStart` can execute. If this already happened, use
`sudo systemctl reset-failed ncps` before starting ncps again.

This one-time reset was completed on 2026-09-05: the old service was stopped
and its 1.6 GB state directory removed before the manual rc17 deployment.

Deploy with `just deploy`, then ensure `ncps` is started. The existing NixOS
module's `preStart` is overridden to use `ncps migrate up`, because rc17 no
longer ships `dbmate-ncps`. It initializes the empty database and preserves the
cache on later starts. No signature-validation settings are relaxed.

To roll back to 0.9.4, stop ncps and use an empty state directory again, restore
the previous package, and remove the `preStart` override so the old module's
dbmate startup runs. Do not open rc17's database with the old binary. No client
rebuild or GitHub Actions change is needed for this server-side upgrade.

The remaining sections document the original 0.9.4 analysis. Version-specific
claims about retry behavior, metrics, database tooling and implementation
details must not be assumed to describe rc17; the network topology, client
trust policy, 200 GB cache limit and conservative concurrency remain in place.

## Recommendation

Run one native NixOS ncps service on the homelab host, reachable only over
Tailscale. Back it with SQLite and a local-filesystem cache under
`/var/lib/ncps` on the host NVMe. Point every non-server Nix client at ncps as
its only substituter and move the six currently configured remote caches behind
ncps. Start with one-second upstream dial and response-header timeouts, retain
Nix's one-hour negative-cache TTL, and reduce the client's unusually high
substitution concurrency while observing the real workload.

This arrangement addresses the expensive part of the previous setup: each
client knew about five distinct system-level remote caches (and a duplicate
spelling of `cache.nixos.org`), while the Config flake added Numtide. ncps now
races the six remote lookups once, caches
positive results and NARs centrally, and lets every machine reuse the warm
result over the approximately 2 ms Tailscale path to the homelab. The managed
client settings are in the
[`teevik/Config` Nix module](https://github.com/teevik/Config/blob/main/modules/nixos/minimal/default.nix#L58-L87);
the proxy is its sole effective substituter after all modules are merged.

The GitHub-hosted nightly workflow is intentionally an exception: it remains
outside the tailnet, queries the same six public caches directly, and pushes
newly built outputs to `teevik.cachix.org`. The portable Config flake does not
advertise the private ncps URL, which prevents accepted flake configuration
from adding an unreachable substituter to CI. Local NixOS configuration owns
the ncps endpoint instead.

The latency-first client configuration is conceptually:

```nix
nix.settings = {
  substituters = lib.mkForce [ "http://homelab.tail84b6c.ts.net:8501" ];
  trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "teevik.cachix.org-1:lh2jXPvLIaTNsL8e8gvrI2abYe83tKhV0PmxQOGlitQ="
    "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
    "cache.flakehub.com-4:Asi8qIv291s0aYLyH6IOnr5Kf6+OF14WVjkE6t3xMio="
    "cache.flakehub.com-5:zB96CRlL7tiPtzA9/WKyPkp3A2vqxqgdgyTVNGShPDU="
    "cache.flakehub.com-6:W4EGFwAGgBj3he7c5fNh9NkOXw0PUVaxygCVKeuvaqU="
    "cache.flakehub.com-7:mvxJ2DZVHn/kRxlIaxYNMuDG1OvMckZu32um1TadOR8="
    "cache.flakehub.com-8:moO+OVS0mnTjBTcOUh2kYLQEd59ExzyoW1QgQ8XAARQ="
    "cache.flakehub.com-9:wChaSeTI6TeCuV/Sg2513ZIM9i0qJaYsF+lZCXg0J6o="
    "cache.flakehub.com-10:2GqeNlIp6AKp4EF2MVbE1kBOp9iBSyo0UPR9KoR0o1Y="
    "nyx-cache.chaotic.cx:dJxTrgMC3V3cFfyIiBQDQorG6k1LsqurH/srpMSq7qk="
    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
  ];

  require-sigs = true;
  fallback = true;
  connect-timeout = 2;
  narinfo-cache-negative-ttl = 3600;
  max-substitution-jobs = 32;
  http-connections = 32;
};
```

`require-sigs` makes Nix reject paths that are not signed by one of those
trusted keys
([Nix setting](https://nix.dev/manual/nix/2.34/command-ref/conf-file.html#conf-require-sigs)).

`lib.mkForce` matters because the current effective settings contain both
`https://cache.nixos.org` and `https://cache.nixos.org/`, introduced through
different modules. The upstream keys remain on the client intentionally; the
v0.9.4 trust limitation below makes ncps's own `/pubkey` inappropriate for this
six-cache configuration.

Keeping `cache.nixos.org` after ncps is a legitimate availability-first
alternative, and is what the upstream client guide demonstrates. It is not the
latency-first choice here: ncps already queries that cache, so falling through
to it after an ncps miss or failure can repeat remote work. With ncps as the
sole substituter, `fallback = true` still permits a local build when a
substitution fails
([Nix `fallback`](https://nix.dev/manual/nix/2.34/command-ref/conf-file.html#conf-fallback)).
If direct-cache outage bypass is more important than miss latency, retain only
`cache.nixos.org` as a second substituter. ncps advertises priority 10, ahead of
the official cache's priority 40
([server source](https://github.com/kalbasit/ncps/blob/v0.9.4/pkg/server/server.go#L37-L55)).

Keep a direct `cache.nixos.org` substituter on the homelab server itself. That
host must still be able to realize or roll back ncps during service bootstrap
and recovery; making ncps its own sole substitute would create a circular
dependency.

## Important v0.9.4 signature constraint

Disable ncps re-signing for this upstream set and keep `require-sigs = true`
with all original public keys on every client. This is a security
workaround for a concrete v0.9.4 implementation limitation, not a general
preference against proxy signing.

When ncps creates an upstream client, it associates a key only if the key name
matches `^<upstream-host>-[0-9]+:`. If no key matches, its fetch path skips
signature validation because the upstream key list is empty
([key-matching source](https://github.com/kalbasit/ncps/blob/v0.9.4/pkg/ncps/serve.go#L733-L773),
[validation condition](https://github.com/kalbasit/ncps/blob/v0.9.4/pkg/cache/upstream/cache.go#L332-L375)).
Three configured caches do not fit that rule:

- `install.determinate.systems` currently returns signatures named
  `cache.flakehub.com-3` and `cache.flakehub.com-4`, so the name does not match
  the upstream hostname
  ([live narinfo](https://install.determinate.systems/4igdp92hi4zdyxxg3wx5hiv4m2m6i3am.narinfo));
- `nyx-cache.chaotic.cx` signs as `nyx-cache.chaotic.cx` without the required
  numeric suffix
  ([live narinfo](https://nyx-cache.chaotic.cx/7r6rbqyi0pqzyjps1yfg6s3k56mpli1k.narinfo)).
- `cache.numtide.com` uses a key named `niks3.numtide.com-1`, which does not
  match the upstream hostname.

With ncps's default re-signing enabled, a client that trusts only ncps could
therefore accept a narinfo that ncps never verified against those three upstream
keys. With `cache.signNarinfo = false`, ncps preserves the upstream signatures,
and Nix verifies them end to end against the keys above; the disabled PUT verb
also prevents clients from injecting objects. The pass-through behavior is
explicit in the pinned NixOS option and v0.9.4 returns without modifying the
signature list when signing is disabled
([NixOS option](https://github.com/NixOS/nixpkgs/blob/e5bdc4a41d4c072fe1e3787eaa0320a384741d44/nixos/modules/services/networking/ncps.nix#L580-L586),
[signing source](https://github.com/kalbasit/ncps/blob/v0.9.4/pkg/cache/cache.go#L3434-L3466)).

Pass-through validation remains sound when ncps normalizes a NAR URL or file
compression metadata: the signed Nix narinfo fingerprint contains only store
path, NAR hash, NAR size and references, not URL, compression, file hash or file
size
([the exact `go-nix` revision used by v0.9.4](https://github.com/nix-community/go-nix/blob/4bdde671e0a1/pkg/narinfo/fingerprint.go#L10-L26)).
CDC should still remain disabled because it is experimental and unnecessary for
one instance, not because it would invalidate the signatures.

## What ncps does during a lookup

For two or more healthy upstreams, v0.9.4 launches a concurrent `HEAD` request
to every cache and returns the first positive response. It cancels the
remaining probes after that response. A complete miss must wait for every
concurrent probe to finish, so miss latency is approximately the slowest
healthy cache or its timeout rather than the sum of all cache latencies. With
exactly one upstream, ncps skips the `HEAD` selection and proceeds directly to
the fetch
([selection source](https://github.com/kalbasit/ncps/blob/v0.9.4/pkg/cache/cache.go#L5427-L5557),
[probe source](https://github.com/kalbasit/ncps/blob/v0.9.4/pkg/cache/upstream/cache.go#L392-L435)).

There is no fan-out concurrency limit in this release: one cold narinfo request
means one outgoing `HEAD` per healthy upstream. Upstream priorities are sorted
before goroutines launch, but all caches are still raced, so the fastest
positive response wins in practice. Priority is not a way to force a preferred
source. Every additional low-value cache increases request volume and can set
the tail latency of a true miss
([selection source](https://github.com/kalbasit/ncps/blob/v0.9.4/pkg/cache/cache.go#L5427-L5557)).

Source inspection also finds no persistent shared negative-result cache in
v0.9.4. ncps stores a successful narinfo, but an all-upstream miss returns
`ErrNotFound` without an absence record; requests for the same hash are only
coalesced while a fetch is in flight. A later request probes the upstreams
again
([miss path](https://github.com/kalbasit/ncps/blob/v0.9.4/pkg/cache/cache.go#L3038-L3077),
[positive storage path](https://github.com/kalbasit/ncps/blob/v0.9.4/pkg/cache/cache.go#L3134-L3160),
[in-flight coordination](https://github.com/kalbasit/ncps/blob/v0.9.4/pkg/cache/cache.go#L4743-L4888)).

Nix's local narinfo cache therefore remains important. Its
`narinfo-cache-negative-ttl` stores a negative result per substituter on disk;
the default is 3,600 seconds and zero forces a refresh. Keep 3,600 initially.
Raising it to six hours would reduce repeated misses further, but a client that
looked up a path just before CI uploaded it could then ignore the new artifact
for six hours
([Nix setting](https://nix.dev/manual/nix/2.34/command-ref/conf-file.html#conf-narinfo-cache-negative-ttl)).

## Upstreams and timeout baseline

Configure these six unique caches behind ncps, with the same public keys the
Nix client currently trusts:

| Upstream | Advertised priority | Reason to retain initially |
| --- | ---: | --- |
| [`cache.nixos.org`](https://cache.nixos.org/nix-cache-info) | 40 | Primary NixOS cache |
| [`teevik.cachix.org`](https://teevik.cachix.org/nix-cache-info) | 41 | Outputs from the existing nightly cache workflow |
| [`hyprland.cachix.org`](https://hyprland.cachix.org/nix-cache-info) | 41 | Hyprland-specific coverage |
| [`install.determinate.systems`](https://install.determinate.systems/nix-cache-info) | 39 | Determinate installer/tooling coverage |
| [`nyx-cache.chaotic.cx`](https://nyx-cache.chaotic.cx/nix-cache-info) | 30 | Chaotic package coverage |
| [`cache.numtide.com`](https://cache.numtide.com/nix-cache-info) | default | Outputs used by the Config flake |

Do not add the trailing-slash duplicate of `cache.nixos.org`. Review the
successful-source metrics after several weeks and remove any optional upstream
that provides no unique hits. Cache order will not materially improve lookup
latency because ncps races the healthy set.

The only relevant v0.9.4 upstream latency controls are global
`dialerTimeout` and `responseHeaderTimeout`, each defaulting to three seconds
([configuration](https://github.com/kalbasit/ncps/blob/v0.9.4/config.example.yaml#L114-L133),
[pinned NixOS options](https://github.com/NixOS/nixpkgs/blob/e5bdc4a41d4c072fe1e3787eaa0320a384741d44/nixos/modules/services/networking/ncps.nix#L589-L624)).
A 404 `HEAD` probe from the homelab on 2026-09-04 put every cache other than
Nyx in roughly the 0.04--0.23 second range; the slower
`nyx-cache.chaotic.cx` had a p95 around 0.27 seconds, a 0.41 second maximum, and
one earlier cold observation of 0.53 seconds. One second leaves useful margin
while reducing the worst-case true miss from about three seconds to about one.

These are separate TCP-connect and response-header timers, not a one-second
end-to-end request deadline
([transport source](https://github.com/kalbasit/ncps/blob/v0.9.4/pkg/cache/upstream/cache.go#L198-L224)).
Moreover, a `HEAD` timeout is treated as “not present”; a timeout that is too
short can cause a false miss when the artifact exists only on the slow cache
([timeout behavior](https://github.com/kalbasit/ncps/blob/v0.9.4/pkg/cache/upstream/cache.go#L420-L435)).
Start at one second, alert on upstream failures and raise both to two seconds if
normal traffic shows false misses or timeouts.

v0.9.4 does not retry ordinary timeouts or connection failures. Its
three-attempt loop retries only an HTTP/2 `GOAWAY`, without backoff
([request source](https://github.com/kalbasit/ncps/blob/v0.9.4/pkg/cache/upstream/cache.go#L256-L302)).
Do not deploy unreleased `main` merely to obtain its broader retry behavior;
wait for a stable release.

## Homelab deployment settings

Deploy ncps as a native NixOS service, not inside K3s. The homelab's pinned
nixpkgs revision already packages ncps 0.9.4 and provides the complete
`services.ncps` module
([package](https://github.com/NixOS/nixpkgs/blob/e5bdc4a41d4c072fe1e3787eaa0320a384741d44/pkgs/by-name/nc/ncps/package.nix#L15-L31),
[module](https://github.com/NixOS/nixpkgs/blob/e5bdc4a41d4c072fe1e3787eaa0320a384741d44/nixos/modules/services/networking/ncps.nix#L171-L224)).
Running directly on the host avoids adding K3s and Longhorn to the cache's
startup and I/O path, and it lets the service use the NVMe filesystem directly.

| Setting | Baseline | Rationale |
| --- | --- | --- |
| Service/package | `services.ncps.enable = true`; pinned nixpkgs `ncps` 0.9.4 | Uses the already-pinned, tested native module |
| Host name | `cache.hostName = "homelab"` | Required module option; signing is disabled, so it is not a client trust identity |
| Storage | `cache.storage.local = "/var/lib/ncps"` | Direct NVMe filesystem; no K3s or Longhorn dependency |
| Cache limit | `cache.maxSize = "200G"` | Large working set while leaving ample room on the 2 TiB NVMe with about 1.5 TiB free |
| Database | `cache.databaseURL = "sqlite:/var/lib/ncps/db/db.sqlite"`; one open connection | Local, single-instance metadata without a network database |
| Temporary data | `cache.tempPath = "/var/lib/ncps/tmp"` | Keeps large in-flight downloads on the same managed filesystem |
| LRU | `cache.lru.schedule = "15 4 * * *"`; `scheduleTimeZone = "Europe/Oslo"` | Reclaim least-recently-used objects daily outside normal use |
| CDC | `cache.cdc.enabled = false` | Experimental and unnecessary for one instance focused on retrieval latency |
| Locks/Redis | Local lock default; no Redis | Distributed locking is only needed for HA |
| PUT/DELETE | `allowPutVerb = false`; `allowDeleteVerb = false` | This instance is a pull-through cache, not an upload target |
| Signing | `cache.signNarinfo = false` | Preserve original signatures because of the v0.9.4 key-matching limitation |
| Upstream timeouts | `dialerTimeout = "1s"`; `responseHeaderTimeout = "1s"` | Bounds the slow-cache tail using the measured latency margin |
| Logging/analytics | `logLevel = "warn"`; analytics reporting disabled | Quiet steady-state operation without anonymous reporting |
| Telemetry | Prometheus enabled; OpenTelemetry disabled initially | Native metrics cover tuning; traces can be added for per-request investigation |

The pinned module maps these NixOS options to ncps's config, creates the state
and temporary directories, migrates the SQLite database before startup, and
runs a hardened systemd service as its own user
([settings mapping](https://github.com/NixOS/nixpkgs/blob/e5bdc4a41d4c072fe1e3787eaa0320a384741d44/nixos/modules/services/networking/ncps.nix#L46-L132),
[systemd service](https://github.com/NixOS/nixpkgs/blob/e5bdc4a41d4c072fe1e3787eaa0320a384741d44/nixos/modules/services/networking/ncps.nix#L651-L812)).
The upstream storage guide specifically recommends SSD for a single-instance
local-filesystem deployment
([local storage guide](https://github.com/kalbasit/ncps/blob/v0.9.4/docs/docs/User%20Guide/Configuration/Storage/Local%20Filesystem%20Storage.md#L3-L70));
the SQLite guide requires a single instance and one database connection
([SQLite guide](https://github.com/kalbasit/ncps/blob/v0.9.4/docs/docs/User%20Guide/Configuration/Database/SQLite%20Configuration.md#L3-L73)).

The 200 GB limit is still conservative against the homelab's approximately
1.5 TiB of free NVMe space. Shrink or grow it after measuring the working set;
cached NARs are replaceable and need not consume most of the disk. Keep SQLite
and local cache storage in the same `/var/lib/ncps` state directory. If backups
are desired, back up the database and NAR storage consistently while ncps is
stopped as the official procedure requires
([backup guide](https://github.com/kalbasit/ncps/blob/v0.9.4/docs/docs/User%20Guide/Operations/Backup%20Restore.md#L7-L110)).

Expose port 8501 only through the host's existing trusted `tailscale0`
interface; do not open it globally in the NixOS firewall. v0.9.4 has switches
for PUT and DELETE but no read-auth setting in its tagged configuration, so
Tailscale is the access boundary
([configuration](https://github.com/kalbasit/ncps/blob/v0.9.4/config.example.yaml#L29-L40)).

## Client concurrency

The current client has both `max-substitution-jobs` and `http-connections` at
128. Those values improve closure throughput, not a single hash lookup. After
consolidation, 128 cold substitution jobs can cause ncps to create as many as
768 concurrent upstream probes across six caches. v0.9.4 exposes no server-side
fan-out limiter, so begin at 32 substitution jobs and 32 HTTP connections, then
increase only if metrics show unused capacity.

Nix defines `max-substitution-jobs` as the maximum simultaneous substitution
jobs and `http-connections` as the maximum parallel HTTP connections
([Nix substitution jobs](https://nix.dev/manual/nix/2.34/command-ref/conf-file.html#conf-max-substitution-jobs),
[Nix HTTP connections](https://nix.dev/manual/nix/2.34/command-ref/conf-file.html#conf-http-connections)).
The 768 figure is a worst-case upper bound, not a prediction of steady-state
traffic: local Nix negative caching, ncps hits, in-flight coalescing and
completed dependencies all reduce it.

Use the full MagicDNS name rather than the single-label `homelab`: Nix's HTTP
resolver timed out on the short name even though curl resolved it, while
`homelab.tail84b6c.ts.net` passed repeated Nix-native checks. Use a client
`connect-timeout` of two seconds for the approximately 2 ms direct Tailscale
path. This setting bounds establishment of the client-to-ncps
connection, not cache query or download duration
([Nix setting](https://nix.dev/manual/nix/2.34/command-ref/conf-file.html#conf-connect-timeout)).

## Observability and rollout checks

Enable ncps Prometheus export and have the in-cluster VictoriaMetrics stack
scrape the Tailscale-reachable `homelab.tail84b6c.ts.net:8501/metrics` target.
The deployed v0.9.4 endpoint exposes generic OpenTelemetry HTTP metrics, but
not the custom `ncps_*` instruments declared in the source. Watch at least:

- `http_client_request_duration_seconds_count` grouped by `server_address`,
  method and status; all six upstreams should have recent health-check
  `GET` responses with status 200;
- `http_client_request_duration_seconds` buckets for upstream p95/p99 latency;
- `request_duration_millis_milliseconds` and response-size metrics for the
  client-facing service;
- systemd restarts/errors and filesystem use under `/var/lib/ncps`.

The additional custom metrics are declared in the v0.9.4 source but were not
present on the deployed endpoint
([served/cache metrics](https://github.com/kalbasit/ncps/blob/v0.9.4/pkg/cache/cache.go#L199-L335),
[upstream gauges](https://github.com/kalbasit/ncps/blob/v0.9.4/pkg/cache/cache.go#L746-L779)).
Prometheus is exposed on `/metrics` when enabled
([server source](https://github.com/kalbasit/ncps/blob/v0.9.4/pkg/server/server.go#L100-L139)).

Do not treat `/healthz` or an active systemd unit as proof that upstream caches
are ready: `/healthz` is only a process heartbeat. Upstream health is checked at
startup and then every minute; an unavailable cache is excluded from the race
until a later successful check
([health checker](https://github.com/kalbasit/ncps/blob/v0.9.4/pkg/cache/healthcheck/healthcheck.go#L30-L136),
[heartbeat route](https://github.com/kalbasit/ncps/blob/v0.9.4/pkg/server/server.go#L100-L139)).
During rollout, wait until the HTTP client metric contains successful health
checks for all six upstream addresses before testing Nix clients. This avoids
recording a one-hour client-side negative result during the brief startup
window.

The first validation should compare a cold and warm realization of a known
closure, followed by a random narinfo miss. Success means:

1. the client contacts only ncps;
2. the cold lookup fans out and downloads from an upstream;
3. the warm lookup is served locally by ncps;
4. a complete miss returns near the slowest measured probe, not six times that
   latency and not the three-second default timeout;
5. reducing client concurrency does not lower sustained NAR download throughput.

Revisit the one-second timeout, optional-upstream list, 200 GB cache cap and
32/32 client concurrency only after those measurements. They are safe starting
points for this single-node homelab, not universal constants.
