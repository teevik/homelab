# Game server panels for Valheim and other games

Status: researched 2026-09-13 against upstream documentation, release metadata,
and source code. This records the panel comparison and proposed deployment.
Implementation and its validation checklist are in [AMP operations](../amp.md).
Prices are the vendor's displayed prices and
may change.

Follow-up: the user selected AMP and already owns an Advanced licence. The
selected addresses are `amp.teevik.no` for the panel and `games.teevik.no` with
different ports for games. The final scope is an AMP panel with **games installed
and configured manually in its UI**, backed up through Longhorn. Game passwords
are not stored in SOPS. TCP/UDP 20000–20999 is reserved for game ports, forwarded
once at the router. No separate AMP S3 credentials or bucket are needed. Local
AMP archives and game-specific schedules are optional settings for the owner.

## Proposed AMP arrangement

Use `https://amp.teevik.no` for the panel through the existing Cloudflare Tunnel,
and DNS-only `games.teevik.no` for direct game connections. A Valheim endpoint
could be `games.teevik.no:2456`; an optional DNS-only `valheim.teevik.no` alias
could resolve to the same game host. Additional instances need non-overlapping
port allocations. Valheim normally needs UDP 2456 and 2457; another instance
could use 2466 and 2467. These are proposals, not existing DNS records
([Valheim ports](https://github.com/CubeCoders/AMPTemplates/blob/main/valheimports.json)).

Per-game DNS records would not require repeated manual work if wildcard DNS
were used: a DNS-only `*.games.teevik.no` CNAME pointing to `games.teevik.no`
would cover names such as `valheim.games.teevik.no`. A broader
`*.teevik.no` wildcard could cover `valheim.teevik.no`, with explicit existing
records taking precedence. This is a DNS alternative, not AMP automatically
provisioning individual records. It would still resolve all those names to
the same game host; ports would continue to select the game instance. The
selected setup keeps the single `games.teevik.no` hostname
([Cloudflare wildcard DNS](https://developers.cloudflare.com/dns/manage-dns-records/reference/wildcard-dns-records/)).

No built-in Cloudflare DNS provisioning was verified for AMP Professional.
The maintainer describes polling AMP's instance list for external automation;
creation/deletion hooks are Enterprise-only. AMP 2.8's Advertised Connection
Address setting can supply the default `games.teevik.no` display address with
per-instance overrides, but does not create DNS records
([maintainer reply](https://discourse.cubecoders.com/t/lifecycle-hooks-scripts-on-instance-creation-and-deletion/39712/2),
[AMP 2.8 release notes](https://discourse.cubecoders.com/t/amp-proteus-2-8-0-release-notes/40953)).

The split matters because a Cloudflare-proxied hostname resolves to Cloudflare
addresses. Adding `:2456` does not make it resolve to the home IP instead.
Using one hostname for HTTPS and games would be possible with direct DNS and
a directly reachable web reverse proxy, but does not fit ordinary Cloudflare
Tunnel public routes. AMP's documented reverse proxy configuration supports
the panel and its instance-management UI
([Cloudflare DNS behavior](https://developers.cloudflare.com/dns/proxy-status/),
[Tunnel protocols](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/routing-to-tunnel/protocols/),
[AMP HTTPS configuration](https://discourse.cubecoders.com/t/setting-up-secure-http-https-with-amp/2305)).

A hidden hostname is not access control: a client can connect to the public IP
and port without knowing that name. Valheim gameplay does not use HTTP paths,
so `amp.teevik.no/secret/valheim` cannot substitute for a game address or
password. Keep a shared game password. AMP's current template documents a
normal server password requirement and a mod-specific option to disable it.
Optionally hide the server from discovery with `-public 0` and restrict players
with `permittedlist.txt`; neither is the same as panel login
([AMP game/subdirectory discussion](https://discourse.cubecoders.com/t/can-amp-provide-servers-under-a-subdirectory-subfolder/15204),
[AMP Valheim settings](https://github.com/CubeCoders/AMPTemplates/blob/main/valheimconfig.json),
[Iron Gate guide](https://www.valheimgame.com/support/a-guide-to-dedicated-servers/)).

If inbound port forwarding is unavailable, Valheim's crossplay relay avoids
it. A general alternative is playit.gg, which supports Valheim and only
requires the server operator to run its agent. This changes connectivity, not
the game's authentication requirements. Direct forwarding is my default here
if the existing home connection supports it
([Iron Gate guide](https://www.valheimgame.com/support/a-guide-to-dedicated-servers/),
[playit.gg](https://playit.gg/)).

For backups, reuse the **same Hetzner account**. Two arrangements are possible:

- The selected approach writes local AMP archives onto a Longhorn-backed volume that opts
  into the existing offsite jobs. This uses the existing Longhorn bucket;
  retrieving an archive after total volume loss requires restoring/extracting
  that volume first. Schedule its offsite backup after AMP finishes archiving.
- An alternative for direct game archive recovery is AMP local archives plus
  direct S3 uploads to a separate private bucket, such as `homelab-amp-backup` if
  available, in the existing Hetzner project. Keep infrastructure backups
  of AMP's configuration/state as well. These workflow differences follow from
  AMP's archive paths and Longhorn's volume recovery mechanism
  ([AMP archive locations](https://discourse.cubecoders.com/t/how-to-change-backup-locations/2783),
  [Longhorn recovery](https://longhorn.io/docs/1.12.1/advanced-resources/data-recovery/recover-without-system/)).

Hetzner bills the base fee and included allowance per account across projects
and buckets. A new project/bucket therefore adds no second base fee, although
total storage/egress beyond the allowance costs more. A fresh key in the
existing project would still access all its buckets by default. The user
prefers keeping the existing project; a dedicated AMP key would allow separate
revocation but would not itself provide bucket-level isolation
([billing](https://docs.hetzner.com/storage/object-storage/overview/#pricing),
[credential scope](https://docs.hetzner.com/storage/object-storage/faq/s3-credentials/#how-do-i-restrict-access-per-key)).

AMP supports custom S3 endpoints and Hetzner is S3-compatible. For Helsinki,
the endpoint is `https://hel1.your-objectstorage.com`. Direct AMP-to-Hetzner
compatibility has not been tested here; verify upload, list, download, restore,
and rotation with the installed AMP version before relying on it
([AMP S3 configuration](https://discourse.cubecoders.com/t/guide-to-setup-a-free-offsite-backblaze-s3-backup-for-amp-instances/40410),
[Hetzner SDK configuration](https://docs.hetzner.com/storage/object-storage/getting-started/using-libraries/#aws-sdk-for-net)).

## Recommendation

Shortlist **AMP Professional** and **Pterodactyl**. AMP is the first trial for
someone who wants a convenient Crafty-like experience across many games and is
comfortable paying for proprietary software. Pterodactyl is the stronger
choice when free/open-source software and a mature release line matter more
than installation simplicity. Both have Valheim templates, permissions for
friends, scheduled backups, and S3 storage. Pelican is promising but still
publishes beta versions. PufferPanel is viable, although its backup features
are less complete for this requirement. The evidence behind these judgments
is below.

| Panel | Valheim and game coverage | Backup fit | Sharing and tradeoff |
| --- | --- | --- | --- |
| **AMP** | Valheim template; broad game catalogue; optional BepInEx/ValheimPlus | Scheduled local/S3 backups, configurable count/space limits, restore UI | Detailed roles; paid licence; Professional has unlimited panel accounts |
| **Pterodactyl** | Valheim vanilla/modded eggs; broad community egg catalogue | Scheduled local **or** S3 backups, count rotation, locked backups, restore UI | Free/open-source; per-server subusers; more infrastructure to operate |
| **Pelican** | Valheim eggs; fork of Pterodactyl | Scheduled local/S3 backups, rotation/locks, restore UI | Free/open-source; subusers and admin roles; current version is beta |
| **PufferPanel** | Valheim template; supports multiple game types | Basic local compressed backups and restore; external work for a complete offsite policy | Free/open-source; server permissions; simpler backup feature set |

## AMP

The upstream [Valheim template](https://github.com/CubeCoders/AMPTemplates/blob/main/valheim.kvp)
supports Linux and Windows x86-64 and optional BepInEx/ValheimPlus. Docker is
supported but not required for this game. A template's existence does not
guarantee compatibility between today's game version and every mod.

The current [product catalogue](https://cubecoders.com/AMP) offers Professional
for **£15 / approximately €19 or US$20 once**, with 15 configured application
instances and unlimited panel users. Advanced is **£30 / approximately €38 or
US$40 once**, with 50 instances, OIDC SSO, and priority support. These values
were also checked in the website's current JavaScript bundle because the
plain HTML initially shows a loading screen. The older comparison post has
an inconsistent USD price; use the current product page and checkout.

Users can receive permissions for individual instances and operations such as
start/stop, scheduling, and backups. Pro's unlimited panel users suits friends
helping manage your community servers. There is a separate licence distinction
if hosting independent servers for friends: Advanced explicitly permits up to
10 such instances administered by those friends. Do not equate sharing a panel
login with sharing the licence key.
([Permissions guide](https://discourse.cubecoders.com/t/managing-user-permissions-in-amp/2301),
[vendor's terms](https://cubecoders.com/TermsOfSale))

AMP has an integrated backup plugin with local and S3 storage, scheduled backup
tasks, upload/restore controls, and separate S3 count and space limits. A
recent community-contributed guide in the official knowledge base documents
these controls; upstream release notes independently confirm automated S3
uploads. No separate Advanced-only S3 requirement was found in the published
tier descriptions. The recommendation to buy Pro is driven by instance and
user limits; Advanced adds SSO and the other listed capabilities.
([S3 setup guide](https://discourse.cubecoders.com/t/guide-to-setup-a-free-offsite-backblaze-s3-backup-for-amp-instances/40410),
[backup plugin release notes](https://discourse.cubecoders.com/t/amp-phobos-2-6-0-release-notes/18255))

Configure and test local/S3 rotation separately. The maintainer documents
replacement policies that delete either one oldest backup or enough old
backups to satisfy limits. This is not the same thing as a flexible
hourly/daily/weekly retention policy, and storage-provider compatibility must
be tested with the actual endpoint.
([Replacement-policy explanation](https://discourse.cubecoders.com/t/backup-deletion-issue/2161/2))

Treat AMP 3's new snapshot architecture as future work. The
[AMP 3 announcement](https://discourse.cubecoders.com/t/announcing-amp-3/41039)
describes a substantial rewrite and invitation-only beta plans; its promises
are not evidence of currently available AMP 2 features.

## Pterodactyl

Pterodactyl has an established stable release line; the latest release checked
was [v1.15.1, published 2026-08-14](https://github.com/pterodactyl/panel/releases/tag/v1.15.1).
Its maintained [game eggs repository](https://github.com/pterodactyl/game-eggs/tree/main/valheim)
includes vanilla Valheim, BepInEx, and ValheimPlus. Eggs describe how the panel
installs and launches a game server.

The panel defaults to local backups managed by Wings, and can instead use AWS
S3 or compatible storage with a custom endpoint and optional path-style URLs.
This makes the existing Hetzner S3 service a candidate, subject to an actual
upload/download/restore test. The documented configuration selects a backup
driver; it does not promise simultaneous local and S3 copies.
([Backup configuration](https://pterodactyl.io/panel/1.0/additional_configuration.html#backups))

Scheduled tasks can create backups. When a server reaches its configured
backup-count limit, scheduled backups remove the oldest unlocked backup;
locked backups are protected, and filling all slots with locked backups can
prevent new backups. Rotation occurs before the replacement backup completes,
so keep several recovery points. These details are verified in the current
release's [scheduler](https://github.com/pterodactyl/panel/blob/v1.15.1/app/Jobs/Schedule/RunTaskJob.php)
and [backup service](https://github.com/pterodactyl/panel/blob/v1.15.1/app/Services/Backups/InitiateBackupService.php).

Friends can be subusers on selected servers, with separate permissions for
console access, restart, files, schedules, and creating/downloading/restoring/
deleting backups. For example, allow restart and backup creation while keeping
restore and deletion restricted. Downloading a backup exposes its included
files, regardless of other file-view permissions.
([Permission definitions](https://github.com/pterodactyl/panel/blob/v1.15.1/app/Models/Permission.php),
[restore implementation](https://github.com/pterodactyl/panel/blob/v1.15.1/app/Http/Controllers/Api/Client/Servers/BackupController.php))

The installation has a web panel, SQL database, queue processing, scheduled
worker, and Wings game hosts. Wings manages Docker containers; it is not a
Kubernetes workload controller. Back up the panel database and its `APP_KEY`
as well as game files: upstream explicitly warns that losing that key makes
encrypted panel data unrecoverable even with a database backup.
([Panel installation](https://pterodactyl.io/panel/1.0/getting_started.html),
[Wings installation](https://pterodactyl.io/wings/1.0/installing.html))

## Pelican

Pelican is a free/open-source Pterodactyl fork, still using Wings and Docker.
It adds a redesigned interface, OAuth, admin roles, and simpler setup options.
Its [Valheim eggs](https://github.com/pelican-eggs/games-steamcmd/tree/main/valheim)
cover vanilla and modded variants.
([Architecture](https://pelican.dev/docs/),
[Pelican feature descriptions](https://pelican.dev/docs/comparison/))

The latest release checked was
[v1.0.0-beta38, published 2026-08-16](https://github.com/pelican/panel/releases/tag/v1.0.0-beta38).
GitHub labels it a regular release, but its version remains explicitly beta.
That makes it a reasonable trial rather than the default recommendation for
minimizing maintenance surprises.

It supports local/S3 backups, restore, and scheduled count rotation with
locked backups. Beta38 contains backup-host objects and selects a backup host
per node, so follow the installed version's UI: some documentation still
describes an older global settings layout.
([Storage documentation](https://pelican.dev/docs/panel/optional-config/),
[backup creation/rotation](https://github.com/pelican/panel/blob/v1.0.0-beta38/app/Services/Backups/InitiateBackupService.php),
[scheduled backup task](https://github.com/pelican/panel/blob/v1.0.0-beta38/app/Extensions/Tasks/Schemas/CreateBackupSchema.php),
[backup UI](https://github.com/pelican/panel/blob/v1.0.0-beta38/app/Filament/Server/Resources/Backups/Pages/ListBackups.php))

## PufferPanel and MCSManager

PufferPanel's current release checked was
[v3.0.9](https://github.com/pufferpanel/pufferpanel/releases/tag/v3.0.9).
It has a [Linux Valheim template](https://github.com/pufferpanel/templates/tree/v3/valheim).
Version 3 added a basic compressed local backup/restore UI, so older claims
that PufferPanel has no backups are outdated. Both operations require the game
server to be stopped. Its host environment uses `unshare`, while Docker is an
alternative; its published Docker image expects games to run in separate
Docker containers.
([Upstream v3 notes](https://docs.pufferpanel.com/en/3.x/release-notes/3.0.0.html))

PufferPanel also has a [task scheduler](https://github.com/pufferpanel/pufferpanel/blob/v3.0.9/servers/scheduler.go)
and [per-operation backup permissions](https://github.com/pufferpanel/pufferpanel/blob/v3.0.9/client/frontend/src/components/server/Backup.vue).
However, the inspected release exposes a backup folder rather than native S3
settings, and I did not verify a built-in backup retention policy or a
ready-made scheduled-backup action. Plan external backup automation if choosing
it for this requirement.
([Configuration](https://github.com/pufferpanel/pufferpanel/blob/v3.0.9/config/entries.go),
[available task operations](https://github.com/pufferpanel/pufferpanel/tree/v3.0.9/operations))

MCSManager is another active free/open-source panel with multiple users,
distributed hosts, generic Steam-server setup, and optional Docker isolation.
It has scheduling, but the current schedule action list covers commands,
delays, and power operations, not an integrated backup/retention/S3 workflow.
I did not independently verify a maintained turnkey Valheim template. It is
less compelling than AMP/Pterodactyl when backups are a priority.
([Project](https://mcsmanager.com/),
[Steam-server setup](https://docs.mcsmanager.com/setup_steam.html),
[v10.18.3 schedule actions](https://github.com/MCSManager/MCSManager/blob/v10.18.3/frontend/src/types/const.ts))

## Fit with this homelab

These are observations of the repository configuration, not a live audit of the
cluster or Cloudflare dashboard:

- [Crafty](../../kubernetes/crafty.nix) already exposes its panel through Tailscale,
  uses a public Minecraft NodePort, and updates the DNS-only
  `gtnh.teevik.no` record through Cloudflare DDNS.
- [Cloudflare Tunnel](../../kubernetes/cloudflare-tunnel.nix) is already declared.
  Its public application routes are managed in the Cloudflare dashboard.
- [Longhorn](../../kubernetes/longhorn.nix) is configured for hourly snapshots
  retaining 24 and daily offsite backups retaining 14, targeting Hetzner Object
  Storage. Volumes must opt in through labels. Crafty's server and backup volumes
  currently opt in; its config volume does not.
- [The host](../../modules/nixos/kubernetes.nix) runs k3s without a Docker runtime
  override. K3s uses containerd by default; this does not provide the Docker API
  required by Wings ([K3s runtime documentation](https://docs.k3s.io/advanced),
  [Wings requirements](https://pterodactyl.io/wings/1.0/installing.html)).

My architecture recommendation for Pterodactyl or Pelican is a Linux VM or
separate game host for Wings and Docker, with the panel optionally in Kubernetes.
This is a deployment choice, not a claim that Kubernetes workarounds are
impossible. Game data on that separate host would need its own backup setup;
the cluster's Longhorn jobs would not automatically cover it.

## Public panel and game connections

`https://amp.teevik.no` is the proposed panel address. The existing
tunnel could route it to the panel's internal HTTP service; Cloudflare documents
publishing private web applications this way and supports WebSockets on all
plans. Friends can access the website with their browsers, using individual
panel accounts and per-server permissions
([published applications](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/routing-to-tunnel/),
[WebSockets](https://developers.cloudflare.com/network/websockets/)).

Cloudflare Access can optionally restrict entry to friends' email addresses.
The panel still controls what each friend may do. With Wings-based panels, plan
for a browser-reachable node endpoint as well, for example
`https://games-node.teevik.no`: Pterodactyl returns a WebSocket URL using the
node's connection address. Test console connections, file operations, and
panel/daemon API calls when adding Access; interactive login rules need to
account for those additional flows
([Access policies](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/),
[Pterodactyl WebSocket controller](https://github.com/pterodactyl/panel/blob/1.0-develop/app/Http/Controllers/Api/Client/Servers/WebsocketController.php),
[Pelican connection troubleshooting](https://pelican.dev/docs/troubleshooting/)).

Valheim gameplay needs a separate path. Ordinary Cloudflare Tunnel public
application routes do not expose arbitrary UDP to standard game clients; even
the documented TCP routes require client-side cloudflared. Publishing the panel
does not publish its games
([supported public-route protocols](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/routing-to-tunnel/protocols/)).

- **Steam backend:** a proposed DNS-only `valheim.teevik.no` record can point to
  the home public IP, following the existing Minecraft DDNS pattern. Forward
  the configured game ports through the router and host firewall. Iron Gate
  specifies the base port and base+1, normally 2456–2457; AMP's maintained
  template identifies these as UDP. If deploying inside Kubernetes, also expose
  those ports through a suitable Service. Reachability depends on the home
  connection permitting inbound traffic
  ([Iron Gate server guide](https://www.valheimgame.com/support/a-guide-to-dedicated-servers/),
  [AMP Valheim port definitions](https://github.com/CubeCoders/AMPTemplates/blob/main/valheimports.json)).
- **Crossplay backend:** Iron Gate documents a relay that avoids router port
  forwarding. Friends can use a join code or the server list. Its documented
  limitation is that local/loopback-IP connections are not supported. This is
  Valheim-specific; other games need their own networking plan
  ([Iron Gate server guide](https://www.valheimgame.com/support/a-guide-to-dedicated-servers/)).

## Backup setup to aim for

Use panel backups for convenient per-world recovery and an offsite copy for
host loss. A reasonable starting policy is hourly world recovery points for a
day, daily copies for two weeks, and an extra backup before upgrades or mod
changes. Those intervals are a recommendation, not panel defaults.

Valheim already provides configurable automatic world saves and rotating local
backups. Preserve those, the world data, permission files, and mod configuration.
Also back up the panel database/configuration and any required encryption keys:
recovering world files alone does not recover friend accounts or panel settings
([Iron Gate server guide](https://www.valheimgame.com/support/a-guide-to-dedicated-servers/)).

Verify how the chosen panel coordinates backups with Valheim saves. For a
known-consistent recovery point, gracefully stop the server and wait for exit
before archiving, or use an explicitly supported game-aware backup mechanism.
Do not assume a typed `save` console command works: AMP's Valheim template marks
its console read-only. Longhorn filesystem snapshots do not themselves trigger
a Valheim save; filesystem synchronization is different from coordinating
application state
([AMP Valheim template](https://github.com/CubeCoders/AMPTemplates/blob/main/valheim.kvp),
[Longhorn snapshot settings](https://longhorn.io/docs/1.12.1/references/settings/#freeze-filesystem-for-snapshot)).

Before relying on the setup, restore a backup into a separate test server and
confirm that the world loads and a friend can join. Direct S3 backup integrations
should use a separate bucket and credentials from Longhorn, and be tested with
Hetzner's endpoint for both upload and restore.
