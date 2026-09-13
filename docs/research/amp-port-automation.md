# AMP game port automation

Status: researched and native AMP allocation defaults configured 2026-09-13.
No router changes, licence activations, plugins, or game instances were needed.
The owner manages games through the existing AMP panel.

## Router and plugin options

For the existing Telia F1, the practical starting point is a single forwarding
rule for the reserved game range, with AMP allocating game ports inside that
range. `Mecistios/AMP-Unifi` demonstrates automatic forwarding for UniFi
gateways, but its router interface cannot control a Telia/Vantiva router. An
external UPnP reconciler is a possible alternative if the installed F1 firmware
exposes UPnP; that capability has not been verified for this router's
`23.1.b` firmware. The live configuration and management-binding defaults are
recorded below.

## Applied: AMP's built-in allocator

The deployed AMP 2.8.0.4 exposes `ADSModule.Network.AppPortInclusions` as
**Application Port Ranges**, using colon-delimited inclusive ranges. This is a
common pool for application and AMP service ports. Advice about separate
application and management pools predates their removal in
[AMP 2.5.1.6](https://discourse.cubecoders.com/t/amp-callisto-2-5-1-release-notes/14472/10).

The following settings are now stored in the live panel:

| Setting | Value |
| --- | --- |
| `ADSModule.Network.AppPortInclusions` | `["20000:20999"]` |
| `ADSModule.Network.DefaultIPBinding` | `127.0.0.1` (already configured) |
| `ADSModule.Defaults.DefaultSettings` | Includes `"FileManagerPlugin.SFTP.SFTPIPBinding":"127.0.0.1"` |
| `ADSModule.Network.DefaultAppIPBinding` | `0.0.0.0` (already configured) |
| `ADSModule.Network.DefaultAdvertisedAddress` | `games.teevik.no` (already configured) |

The SFTP default was merged into the existing defaults before restricting the
pool. The old `1024:65535` entry was replaced, not retained alongside it. AMP's
native allocator can select available ports inside the forwarded block when
creating instances, including associated query ports described by templates.
Web/SFTP allocations also consume ports from this pool, but their localhost
bindings prevent direct public access through the forwarded range.

SFTP needs its own binding: the existing Valheim instance's AMP web listener
was observed at `127.0.0.1:8081`, while its SFTP listener was on
`0.0.0.0:2224`. Changing only the common port pool would allow a future SFTP
listener to become public. The supported new-instance setting is documented in
[CubeCoders' provisioning guide](https://discourse.cubecoders.com/t/configuring-amp-for-enterprise-or-advanced-usage/1830).
The deployed runtime's `ADSModule/GetProvisionArguments` for
`FileManagerPlugin` independently confirms `SFTPIPBinding` as an `IPAddress`
provisioning node related to `SFTPPortNumber`. It is not exposed through
`Core/GetConfig`, which returns "No such node" for that key; this does not make
it an invalid provisioning argument.

Validation: both modified settings report `RequiresRestart=false`; API readback
matched the requested values. Existing instance IDs, IPs, ports, endpoints, and
running states remained unchanged. Valheim's game listeners were observed on
20000/20001. A subsequent owner-created Minecraft instance independently verified
the new defaults through its persisted configuration and live listening sockets:
AMP web on TCP `127.0.0.1:20000`, SFTP on TCP `127.0.0.1:20001`, and Minecraft
on TCP `*:20999`. The panel's advertised SFTP address is
`games.teevik.no:20001`; advertising an address does not make its localhost
listener reachable at that address. These checks establish allocation within
the pool and private management bindings, not game reachability from the public
internet. This configuration lives on the backed-up AMP PVC;
it is an owner-editable panel setting, not continuously enforced by the image.

A game template or mod can introduce its own RCON/admin listener. That is a
separate service from AMP web/SFTP and must use a local binding or other
appropriate game-specific configuration. A general router range does not filter
ports by purpose. This caveat also applies to manually assigning game ports
inside the same block.

## Router and plugin research

### What AMP-Unifi actually does

Inspected upstream commit
[`a6e9a857473b14949fe5c5c5148b73ee7dbd5d5f`](https://github.com/Mecistios/AMP-Unifi/tree/a6e9a857473b14949fe5c5c5148b73ee7dbd5d5f).
It is an AMP 2.8/.NET 8 plugin installed on the ADS machine with access to the
instance data directories, a UniFi OS console API key, and the server's target
LAN IP. It exposes a dry-run `SyncNow(apply=false)` operation and an applying
sync operation ([README](https://github.com/Mecistios/AMP-Unifi/blob/a6e9a857473b14949fe5c5c5148b73ee7dbd5d5f/README.md)).

The router side uses HTTPS requests with an `X-API-KEY` header. Site discovery
uses `/proxy/network/integration/v1/sites`; listing, creating, updating, and
deleting forwards use `/proxy/network/api/s/{site}/rest/portforward`, with a rule
ID appended for updates/deletions. This is a UniFi-specific API integration;
there is no UPnP or NAT-PMP client. The client unconditionally accepts the
router's TLS certificate, a concrete limitation if adapting or deploying this
code ([UnifiClient.cs](https://github.com/Mecistios/AMP-Unifi/blob/a6e9a857473b14949fe5c5c5148b73ee7dbd5d5f/UnifiClient.cs)).

For discovery, it reads `instances.json` and each instance's module KVP file.
Generic applications use the `App.Ports` JSON array; Minecraft receives special
handling through `Minecraft.PortNumber`. ADS and suspended instances are
skipped. Ports are grouped per instance/protocol, forwarded with matching
external/internal port numbers, and compared with existing rules. Rules bearing
its configured prefix are managed; overlapping foreign rules are preserved and
conflicts reported. The advertised exclusion of administrative ports is a
heuristic: `Ref` containing `rcon`, `admin`, or `echo`. The parser does not inspect
an `IsAdmin` flag, and stopped instances are not excluded. Do not interpret the
README as proof that every game template's administrative port is filtered
([UnifiReconciler.cs](https://github.com/Mecistios/AMP-Unifi/blob/a6e9a857473b14949fe5c5c5148b73ee7dbd5d5f/UnifiReconciler.cs)).

It watches `*.kvp` files recursively using `FileSystemWatcher`, waits two seconds
to combine changes, and then reconciles the affected instance. A full scan runs
after an initial 30-second delay and every 15 minutes by default. These are
filesystem observations and periodic scans, not AMP instance lifecycle hooks.
The source still starts the watcher when the timer interval is zero, so zero
disables the fallback timer rather than all automatic synchronization. The code
also detects a known AMP interface incompatibility and disables syncing until
the plugin is rebuilt/updated
([PluginMain.cs](https://github.com/Mecistios/AMP-Unifi/blob/a6e9a857473b14949fe5c5c5148b73ee7dbd5d5f/PluginMain.cs),
[settings](https://github.com/Mecistios/AMP-Unifi/blob/a6e9a857473b14949fe5c5c5148b73ee7dbd5d5f/PluginSettings.cs)).

### Developer licence requirements

AMP normally requires plugins to be signed by CubeCoders. Its Developer licence
allows unsigned plugins and is an additional licence attached to an instance
that retains its paid runtime licence. CubeCoders says these companion licences
are freely available to paid AMP owners. Advanced alone therefore does not
enable an unsigned plugin such as AMP-Unifi
([CubeCoders editions and Developer licence description](https://discourse.cubecoders.com/t/editions-comparison-sheet/2247)).

The official developer guide describes requesting the key in the
[licence manager](https://manage.cubecoders.com/) and activating it with
`ampinstmgr reactivate INSTANCE DEVELOPERKEY`. The plugin author recommends
activating the Developer key and then the runtime key on ADS so both remain
active. These instructions concern the AMP plugin host; they are not a new
requirement for ordinary game mods or using AMP's HTTP API. An external program
that reads AMP's API and manages the router would not load an unsigned AMP
plugin and avoids this companion-licence step
([official developer guide](https://github.com/CubeCoders/AMP/wiki/Getting-started-with-AMP-developer-licences),
[plugin installation](https://github.com/Mecistios/AMP-Unifi/blob/a6e9a857473b14949fe5c5c5148b73ee7dbd5d5f/README.md#licensing),
[official HTTP API client](https://github.com/CubeCoders/ampapi-node)).

### Telia F1 / Vantiva feasibility

Telia Norway documents local F1 administration at `http://teliagateway.lan` or
`192.168.1.1`, manual port forwarding, and bridging LAN port 4 when using another
router. Its instructions explicitly exclude port forwarding and bridge mode
for Telia's Trådløst Bredbånd service. They do not document a public router
configuration API or version-specific behavior for `23.1.b`
([Telia Norway F1 support](https://www.telia.no/internett/wifi/rutere/f1/)).

Telia Sweden's guide for Technicolor EWA1330/F1 places manual forwarding under
Advanced interface → WAN Services → Add new IPv4 port mapping, with protocol,
WAN/LAN ports, and destination device fields
([Telia Sweden forwarding guide](https://www.telia.se/foretag/support/guider/bredband/oppna-portar-technicolor-ewa-1330-f1)).
Telia Lithuania's official F1/EWA1330 manual, page 25, documents port ranges
using a colon, such as `8001:8010`, with equal-sized WAN/LAN ranges. It also
documents UPnP under WAN Services → Show advanced and states UPnP and NAT-PMP
are disabled by default
([official F1 manual](https://www.telia.lt/medias/telia-f1-ewa1330.pdf?context=bWFzdGVyfGZja0ltYWdlL0ZBUS9Ib21lIEludGVybmV0L1JvdXRlcnMgSW5zdHJ1Y3Rpb25zfDE0MzU2OTF8YXBwbGljYXRpb24vcGRmfGZja0ltYWdlL0ZBUS9Ib21lIEludGVybmV0L1JvdXRlcnMgSW5zdHJ1Y3Rpb25zL2hlZi9oMDQvMTE0NDcxNDA2Nzk3MTAucGRmfDE5MDg4MTg5NDBjODJlZWM0MGUzNmIyZGIwZmM4MGFkODJkOGJhMzVlYTg1MDg0N2U0MWY3MWUyM2FkMmQyN2Q)).

Those sources establish capabilities in the F1 family, not identical behavior
across countries and firmware releases. In particular, no official evidence
found establishes UPnP availability, its permission model, or a supported HTTP
automation API on this exact Norwegian `23.1.b` installation. A read-only check
of the local WAN Services interface and UPnP discovery can settle that without
changing forwarding rules.

| Approach | Fit for this homelab |
| --- | --- |
| Forward TCP/UDP `20000:20999` once and allocate game ports within it | Selected. Native allocation and localhost management defaults were verified on a subsequently created Minecraft instance. |
| AMP-Unifi plugin on the current F1 | Does not fit: its API client requires UniFi OS. |
| External AMP API → UPnP automation | Feasible design if this firmware offers UPnP; requires implementing reconciliation and verifying game-port filtering, mapping renewal, and cleanup. No unsigned AMP plugin is needed. |
| Firmware-specific Telia web-interface automation | No supported API established; would require inspecting and maintaining the exact firmware's authentication and form/API behavior. |
| UniFi gateway behind F1 bridge mode | Makes the referenced plugin applicable but adds router hardware and a network migration; unnecessary solely to reserve one game-port range. |

The alternatives above are engineering assessments from the cited interfaces;
no router connectivity, UPnP behavior, or plugin installation was tested during
this research.
