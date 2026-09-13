# AMP game servers

AMP provides the panel; install games, configure passwords, manage accounts and
choose game-specific backup schedules in its UI. The homelab does not provision
any game instances. The existing **Advanced** licence and initial `admin` panel
password are stored in SOPS. Game passwords live in AMP's persistent data.

The application is defined in [kubernetes/amp.nix](../kubernetes/amp.nix). Its
[custom image](../images/amp/Dockerfile) runs the controller as UID/GID 1000 on
the `homelab` node, with `/home/amp` on a 150 GiB Longhorn volume. AMP and its
game processes share a 10 GiB memory limit; increase it before adding several
large servers, accounting for Crafty's memory use.

Deployed on 2026-09-13 from commit `359d14a`. Argo CD reports Synced/Healthy;
public HTTPS login, licence activation and persistence after pod recreation
were verified. `games.teevik.no` resolves to the home public IP. The host
firewall range is installed; router forwarding is configured by the owner.

## Addresses and game ports

| Use | Address | Routing |
| --- | --- | --- |
| Public panel | `https://amp.teevik.no` | Existing Cloudflare Tunnel → `http://amp.amp.svc:80` |
| Private panel | `http://amp` on Tailscale | Tailscale ingress service |
| Games | `games.teevik.no:<game port>` | DNS-only DDNS → router → `192.168.1.225` |

Forward **TCP and UDP 20000–20999** at the router to `192.168.1.225`, keeping
the same internal ports. This is the homelab's static Ethernet address; reserve
it for Ethernet MAC `6C:6E:07:22:0D:0A` in the router's DHCP settings. Wi-Fi is
disabled and its saved connection has been removed. Keeping the existing node
address on Ethernet also preserves K3s and embedded-etcd connectivity. Forwarding
to the former Wi-Fi address while Ethernet used `192.168.1.79` caused Valheim's
UDP replies to use a different source address from incoming traffic.

The router panel is available over Tailscale at
`http://homelab.tail84b6c.ts.net:8081`, using the router's own login. A host nginx
proxy on `127.0.0.1:18081` supplies the `Host: 192.168.1.1` header required by the
router; Tailscale Serve exposes it only inside the tailnet. Both services are
configured in `hosts/homelab/configuration.nix`. Port 8081 needs no router rule.

NixOS allows this range. AMP's **Instance Deployment →
Networking → Application Port Ranges** is set to the single entry
`20000:20999`, replacing `1024:65535`. Its native allocator uses this pool for
new instances, so another router rule is unnecessary while capacity remains.
The owner-created Valheim instance was verified on UDP 20000–20001. Existing
instances are not renumbered by changing the allocation pool.

The pool also covers AMP web and SFTP ports. **Default AMP IP Binding** remains
`127.0.0.1`; **New Instance Defaults → Default Settings** includes
`FileManagerPlugin.SFTP.SFTPIPBinding` = `127.0.0.1`. These make new management
listeners local even when their assigned port falls inside the forwarded range.
Keep these defaults together. The panel's file manager remains available over
HTTPS; direct SFTP to future instances requires a local SSH tunnel. Games use
`0.0.0.0` and advertise `games.teevik.no`.

These panel settings were applied and read back on 2026-09-13 without restarting
ADS or Valheim. They persist in the AMP PVC and are covered by Longhorn backups;
the image's first-run bootstrap does not enforce them. Reapply them after a
fresh installation without restored AMP data. A subsequent owner-created
Minecraft instance verified the defaults: AMP web listens on TCP
`127.0.0.1:20000`, SFTP on TCP `127.0.0.1:20001`, and Minecraft on TCP
`*:20999`. The panel advertises `games.teevik.no:20001` for SFTP, but that label
does not override its localhost-only listener. Explicit per-instance overrides
or game mods can require additional configuration.

The controller remains on 8080 and its nginx proxy on 8088; neither is forwarded
at the router. The range avoids Glance's agent on 27973 and Kubernetes' NodePort
range. For games with their own RCON/admin service, use a local binding where
supported; a forwarded range does not distinguish gameplay from administration.
The public panel requires AMP login; give friends individual accounts with only
the instance permissions they need. See [port automation research](research/amp-port-automation.md)
for the router/plugin alternatives and the native pool's limitations.

The Cloudflare route is dashboard-managed. nginx supplies AMP's HTTPS scheme
and WebSocket headers. It forwards its immediate peer IP, so public logins share
the connector's IP in AMP's IP-based logging/rate limits. It does not trust
arbitrary client-supplied IP headers.

## Secrets and deployment

The licence and initial panel password were captured by a one-time setup
wizard and encrypted in `secrets.yaml`. No setup script needs to be retained
or rerun. Use `sops secrets.yaml` to edit these values later:

| SOPS key | Mounted secret field |
| --- | --- |
| `amp_license_key` | `AMP_LICENSE_KEY` |
| `amp_admin_password` | `AMP_ADMIN_PASSWORD` |

NixOS creates `amp/amp-secrets`, mounted read-only at `/run/secrets/amp`. The
DDNS and registry push Secrets reuse existing credentials. Only ciphertext
enters Git and the Nix store. AMP retains its runtime configuration on the PVC,
which also needs protection because it contains accounts and credentials.

1. Generate manifests with `nix develop -c nixidy switch .#homelab`.
2. Run `just deploy` for host Secrets and firewall changes.
3. Commit source, encrypted secrets and generated manifests together, then push
   `main`. Argo CD builds the image and deploys it. Do not manually apply the
   rendered manifests.
4. Check `kubectl -n amp get pods,pvc` and
   `kubectl -n amp logs deployment/amp -c amp`. First startup downloads AMP,
   configures standalone mode and the reverse proxy, and activates the licence.
5. Open the panel as `admin`. Create game instances and set their passwords in
   AMP. The bootstrap does not install games or create their backup schedules.

Completed controller setup is recorded in `/home/amp/.homelab`. Pod restarts do
not reset panel settings or passwords. The SOPS password seeds the initial
administrator; changing it later does not automatically change AMP's password.
Changing licence keys also requires updating AMP's licence/default-instance key.

## Grafana monitoring

The **Games → AMP Game Servers** dashboard is provisioned from
[kubernetes/dashboards/amp.json](../kubernetes/dashboards/amp.json), at
`http://grafana/d/amp-game-servers` on Tailscale. It shows game state, connected
player counts, CPU, memory, uptime, and Minecraft TPS when the game exposes it.
Shared AMP container memory/limit and PVC usage come from Kubernetes metrics.
Some AMP modules report host RAM as their maximum; that is not the shared
container's actual memory limit. Per-instance disk figures are omitted because
AMP currently reports zero for them; the dashboard uses the real PVC usage.

The separate `amp-exporter` Deployment uses
[soynx/amp-cubecoders-exporter](https://github.com/soynx/amp-cubecoders-exporter)
0.1.0, pinned by image digest and verified against upstream commit
`84a45743aad9a11d1def66878e917e828798a7bd`. It reads ADS through the internal AMP
Service, automatically discovers new instances, and serves only an internal
ClusterIP on 9822. Its NetworkPolicy permits scraping from `victoria-metrics`
and outbound access only to DNS and the host-network AMP proxy.

A `VMServiceScrape` collects every 30 seconds with a 20-second timeout. The
`amp-exporter` job drops the ADS controller's game metrics but retains `amp_up`
for controller connectivity/authentication. Metrics use the existing
VictoriaMetrics retention (three months). History starts when scraping starts;
AMP's historical player-session database is not imported. This integration
does not enable AMP's optional per-player analytics or collect player names/IPs.

Authentication uses the dedicated `amp-metrics` account and common **Metrics
Reader** role, whose only grant is `Instances.*.Manage`. Despite AMP's wording,
this grants access to an instance, not its separate start/stop/console/file
permissions. The common role works across existing and future instances.
Successful root and child status reads were checked with this account, along
with denied server-control, console, file-download and role-edit permissions.
The account cannot change its own password. Its random password is stored as
`amp_exporter_password` in SOPS and supplied through `amp/amp-exporter` as
`AMP_PASSWORD`. No AMP admin credential is mounted in the exporter.

The account and role persist in AMP's backed-up data. After a fresh AMP install
without that data, recreate them before starting the exporter. Rotate its
password in AMP and SOPS together, run `just deploy`, and restart only the
exporter so its environment reloads. `amp_up=0` indicates AMP/API authentication
failure; an unavailable scrape is a separate exporter/network problem. Sleeping
or intentionally stopped games are displayed as such, not treated as failures.

## Backups and restoration

The entire AMP PVC opts into the existing Longhorn jobs:

| Backup | Schedule | Retention |
| --- | --- | --- |
| Local snapshots | Every hour | 24 |
| Hetzner offsite | Daily at 02:00 UTC | 14 |

The offsite destination is the existing `homelab-longhorn-backup` bucket. Every
game stored on this volume is included automatically, along with AMP itself,
accounts, settings and any local AMP backup archives. No separate AMP S3 bucket
or credentials are needed. The schedule was verified on the live cluster on
2026-09-13; 02:00 UTC is 04:00 Norway summer / 03:00 winter.

The initial offsite backup `backup-8e8e5100b55a4324`, from snapshot
`amp-initial-20260913`, completed at 100% without errors. This verifies an export
to Hetzner; a restore has not yet been tested.

Longhorn snapshots capture on-disk state while applications run. They do not
include unsaved game state in memory. For game-consistent recovery, configure
an appropriate local backup/save schedule inside AMP. For Valheim, backing up
with the server stopped avoids copying a world during a save. Schedule any
nightly local archive comfortably before Longhorn's offsite export if it should
be included in that night's backup. This is configured per game by its owner.

Hourly snapshots remain on the homelab; losing the server can lose up to a day
of changes since the last successful offsite backup. Verify backup completion
and test a restore after adding important worlds.

For a full restore, scale AMP down through Git, restore the Longhorn volume into
a PVC, point the deployment at it if necessary, and scale back up. Restoring to
another host may require licence reactivation. Individual archives, if enabled
in AMP, can be restored from the game's Backups page with that game stopped.

## Packaging and updates

This uses the maintained community
[AMP-dockerized image](https://github.com/MitchTalmadge/AMP-dockerized), with
non-root startup and Tini to reap detached processes. CubeCoders does not
officially support the ADS controller in a container. There is no Docker socket
or nested container runtime. Games share the Unix user, filesystem, pod resources
and host network; templates requiring nested Docker cannot run here.

The dependency image is pinned. First startup downloads the current AMP
Mainline runtime into the PVC; its version is separate from the image tag.
Use AMP's update controls for the controller, instances, templates and games.
Pod restarts do not force upgrades. Rolling back the Kubernetes image does not
roll back AMP's persisted binaries or databases.

Sources: [AMP container support](https://discourse.cubecoders.com/t/configuring-amp-to-use-docker-podman-for-instances/1957),
[proxy configuration](https://discourse.cubecoders.com/t/setting-up-secure-http-https-with-amp/2305),
[Valheim ports](https://github.com/CubeCoders/AMPTemplates/blob/main/valheimports.json),
[Valheim saves and backup options](https://www.valheimgame.com/support/a-guide-to-dedicated-servers/).
