# Self-hosted ideas for this homelab

Researched: 2026-09-15. Preference: a mix of useful and unusual projects.

## Recommendation

Start with **Karakeep** for saving and finding interesting material,
**RomM** for a gaming project, or **Dawarich** for a new use of the existing
Immich library. **Pocket ID** is the strongest option for improving the
experience across existing services. These rankings are judgments based on
the repository, rather than a claim that these are universally the best apps.

## Context and method

The configuration shows NixOS, a single-node Kubernetes cluster, nixidy,
Argo CD, Longhorn, Tailscale, and services including Immich, Paperless-ngx,
BentoPDF, AMP, TwitchDropsMiner, Glance, ntfy, changedetection.io,
VictoriaMetrics/Grafana, an image registry, and ncps.
Glance includes technical blogs, selfh.st, Hacker News/Lobsters, and technology
YouTube channels. Sources: [flake](../../flake.nix),
[Glance](../../kubernetes/glance.nix),
[host configuration](../../hosts/homelab/configuration.nix).

That suggests opportunities around collecting information, gaming, and
connecting existing services. Cooking, audiobook listening, and home automation
remain conditional interests. Kavita was present at the first inspection but
was removed from the working tree during research; recommendations do not
assume it remains deployed.

Reddit supplied discovery leads and first-person experiences, primarily from
2026 discussions in r/selfhosted and r/homelab. Official project documentation
supplied feature and deployment facts. Community enthusiasm is anecdotal;
maintainer announcement threads are identified separately below. No services
were installed or benchmarked. Complexity estimates describe deployment and
ongoing administration, not measured CPU/RAM requirements or implementation
time.

## Strongest candidates

### 1. Karakeep — a searchable collection of things worth keeping

**Fit:** Save the articles, project links, snippets, and images discovered
through Glance and Reddit, then retrieve them later. This is my strongest
general daily-use recommendation for the visible reading/developer workflow.

Karakeep supports bookmarking links, notes, and images, full-text search,
archiving, and optional AI tagging/summarization. AI is opt-in, so an LLM is
not a prerequisite. Its complete Docker setup includes the application,
Meilisearch, and Chrome. Sources:
[project](https://github.com/karakeep-app/karakeep),
[installation](https://docs.karakeep.app/installation/docker/).
Removing Meilisearch disables search; removing Chrome affects screenshots and
JavaScript-heavy page capture. Keep those components in the initial trial.
[Minimal-install tradeoffs](https://docs.karakeep.app/installation/minimal-install/).

**Tradeoff:** More moving parts than a basic bookmark list, and value depends
on actually revisiting saved material. In a
[June thread about saving miscellaneous material](https://www.reddit.com/r/selfhosted/comments/1udhzji/any_selfhosted_tool_for_dumping_stuff/),
Karakeep was a prominent recommendation. A
[January removal thread](https://www.reddit.com/r/selfhosted/comments/1q7vgbv/what_selfhosted_services_did_you_recently_remove/)
also contains people who found no use for it, alongside users who valued
preserving disappearing content. Try it with a small real collection first.

**Alternative:** Linkwarden is worth comparing if shared collections and
preserving pages as screenshots/PDFs/HTML are the main attraction. Choose one
bookmark system initially. [Linkwarden](https://github.com/linkwarden/linkwarden).
Its AI is also optional; omitting Meilisearch retains basic PostgreSQL search,
but loses preserved-page full-text search and advanced operators.
[Lighter setup](https://docs.linkwarden.app/self-hosting/lighter-setup).

### 2. Dawarich — location history connected to Immich

**Fit:** A personal map of trips and places, with photographs alongside it.
It offers a new way to explore data already in this homelab.

Dawarich accepts location data from phone trackers and imports, and integrates
with Immich. It can also match timestamps to location history and write missing
coordinates into Immich's database. This requires location records covering
the photos' dates; it does not reconstruct journeys from nothing or change
the original files' EXIF metadata. Sources:
[project](https://github.com/Freika/dawarich),
[photo enrichment](https://dawarich.app/docs/features/enrich-photos/).

**Tradeoff:** Ongoing phone tracking/imports and an actively changing app to
maintain. The upstream README explicitly calls out breaking changes and
reading release notes. In a
[July discussion](https://www.reddit.com/r/selfhosted/comments/1v7eegf/whats_an_incredibly_good_but_not_well_known_self/),
one user described enriching an Immich library, while another preferred
GeoPulse. The appeal is strong; perceived reliability is mixed.

### 3. Pocket ID — passkey sign-in for the apps you already use

**Fit:** Reduce separate sign-ins across the lab using one identity provider.
Official integration examples cover both
[Immich](https://pocket-id.org/docs/client-examples/immich) and
[Grafana](https://pocket-id.org/docs/client-examples/grafana).

Pocket ID supplies OpenID Connect (OIDC) authentication using passkeys.
Applications need OIDC support or a separate compatible authentication proxy.
The Pocket ID endpoint requires HTTPS; the existing short HTTP service names
alone are insufficient. Sources: [project](https://pocket-id.org/),
[installation](https://pocket-id.org/docs/setup/installation).

**Tradeoff:** The service itself is relatively simple, but connecting and
testing each application's login flow is real integration work. Start with
one application. A
[March user discussion](https://www.reddit.com/r/selfhosted/comments/1s5vg15/add_passkeys_to_your_apps_pocket_id/)
describes this use case; the
[July certification post](https://www.reddit.com/r/selfhosted/comments/1uunxeq/pocket_id_is_now_openid_connect_certified_oauth/)
is a maintainer announcement, not independent validation of every integration.

### 4. RomM — a retro-game library with browser play

**Fit:** AMP and TwitchDropsMiner suggest gaming is a better-supported interest
than another generic productivity dashboard. RomM adds a different gaming
experience: browse a collection and play supported systems in a browser.

RomM organizes ROM libraries, retrieves metadata, and integrates browser
emulation. Metadata support for a platform does not mean it can be played
inside the browser. Sources: [project](https://github.com/rommapp/romm),
[browser emulation](https://docs.romm.app/5.2.0/using/in-browser-play/emulatorjs/).
Browser emulation runs on the device doing the playing. The standard full-image
setup bundles Valkey and adds MariaDB; the library, database, and saves are
persistent state. [Quick start](https://docs.romm.app/5.2.0/getting-started/quick-start/).

**Tradeoff:** Library preparation, metadata credentials, and platform-specific
emulator/BIOS requirements. Start with one system and a small collection of
games you can use. Do not assume it replaces AMP or streams modern PC games.

### 5. Miniflux — turn the Glance reading list into a reading workflow

**Fit:** Glance already provides discovery. Miniflux would add a dedicated
place to read and organize the technical feeds, then send selected articles
to Karakeep through an official integration.

Features include article extraction, full-text search, categories, mobile
client APIs, and integrations. PostgreSQL is required. Sources:
[features](https://miniflux.app/features.html),
[Karakeep integration](https://miniflux.app/docs/karakeep.html),
[requirements](https://miniflux.app/docs/requirements.html).

**Tradeoff:** Useful when following feeds is a habit; lower priority if Glance
already satisfies it. A
[March reader discussion](https://www.reddit.com/r/selfhosted/comments/1s68a02/new_rss_reader_needed/)
contains both Miniflux and FreshRSS recommendations, with differing performance
experiences. No performance claims were tested here.

## Small practical additions

| Project | Concrete use here | Main consideration |
| --- | --- | --- |
| [ConvertX](https://github.com/C4illin/ConvertX) | Convert images, audio/video, documents, and ebooks through a local web interface. Extends the existing BentoPDF utility collection. | Server-side conversion uses temporary storage and CPU; concurrency can be limited. |
| [PairDrop](https://github.com/schlagmichdoch/PairDrop) | Send a file or text between a phone and computer through their browsers. | WebRTC connectivity can need a TURN relay across networks; this is not persistent file storage. |
| [IT-Tools](https://github.com/CorentinTh/it-tools) | A convenient collection of browser tools for development and administration. | Small deployment; mostly a convenience improvement over existing local tools. |
| [Mealie](https://docs.mealie.io/documentation/getting-started/introduction/) | Import recipes by URL, plan meals, and produce shopping lists. | High value if cooking/planning is a regular activity; otherwise another collection to maintain. |
| [Audiobookshelf](https://github.com/advplyr/audiobookshelf) | Serve audiobooks and podcasts with listening progress and offline-capable clients. | Pick a client for the actual phone before building a library; audio listening is an unconfirmed interest. |

ConvertX appears in the
[April fun-project discussion](https://www.reddit.com/r/homelab/comments/1smum4v/whats_the_most_unnecessary_but_fun_thing_running/).
Mealie is repeatedly suggested in a
[recipe-app discussion](https://www.reddit.com/r/selfhosted/comments/1sdg413/good_recipe_self_hosted_app/),
while Audiobookshelf appears in the
[June daily-use discussion](https://www.reddit.com/r/selfhosted/comments/1ugb4eg/what_selfhosted_apps_do_you_actually_use_every_day/).
These reports support trying the workflows, rather than installing them just
because they are popular.

Two deployment details to retain if these are selected:

- Audiobookshelf's official repository currently lists its mobile apps as beta
  and the iOS TestFlight as full. Its embedded SQLite configuration directory
  should not live on an NFS filesystem.
  [App status](https://github.com/advplyr/audiobookshelf),
  [storage documentation](https://audiobookshelf.org/docs/documentation/install/docker/).
- PairDrop's optional WebSocket fallback passes readable traffic through its
  server. Describe direct WebRTC, TURN-relayed WebRTC, and that fallback
  accurately when choosing the deployment.
  [Hosting guide](https://github.com/schlagmichdoch/PairDrop/blob/master/docs/host-your-own.md).

## Unusual projects and larger experiments

### Home Assistant with Nord Pool

An entry into home automation with a locally relevant first project: show
electricity spot prices and, if there are suitable controllable devices, use
them in automations. The official
[Nord Pool integration](https://www.home-assistant.io/integrations/nordpool/)
provides market-area prices; taxes and additional charges are not included.
It also depends on an external API. This is worthwhile if there is a concrete
device or household routine to automate. Device access and network discovery
make deployment more involved than a normal web app.

### ADS-B aircraft receiver

Build a live map from aircraft signals received by your own antenna. This
crosses into radio hardware and is a good weekend project if the attraction
is collecting real-world data. The
[ADSB.im guide](https://adsb.im/howto) describes the receiver, a USB
software-defined radio (SDR), antenna, and web map. Antenna position influences
what can be received; a separate small receiver near a useful window or outdoor
antenna may suit this better than the main server.

This idea appeared in the
[April r/homelab discussion](https://www.reddit.com/r/homelab/comments/1smum4v/whats_the_most_unnecessary_but_fun_thing_running/).
No hardware price, local reception range, or subscription benefit is assumed.

### Hypermind

A deliberately frivolous peer-to-peer project: count other running Hypermind
nodes, with optional ephemeral chat and a map. The
[project README](https://github.com/lklynet/hypermind) documents its peer discovery
and deployment, including network requirements. It appeared in the same
[fun-project thread](https://www.reddit.com/r/homelab/comments/1smum4v/whats_the_most_unnecessary_but_fun_thing_running/).
Treat it as a network experiment; the counter itself is the joke.

## Ideas that rank lower for this setup

- **Another dashboard, deployment manager, cache, or monitoring stack:** the
  repository already provides Glance, Argo CD, registry/ncps, and Grafana with
  VictoriaMetrics. A new app should address a specific missing workflow.
- **Backrest:** potentially useful for client or host directories outside
  Longhorn, but Longhorn already configures hourly snapshots and daily Hetzner
  S3 backups for opted-in volumes. This is configuration evidence, not a
  restore test. Sources: [Longhorn configuration](../../kubernetes/longhorn.nix),
  [Backrest](https://github.com/garethgeorge/backrest).
- **A large local-AI stack:** the host has AMD GPU support and Immich requests
  a GPU, but spare memory/VRAM and realistic inference performance were not
  measured. Optional AI features in a useful app are a more concrete starting
  point than choosing models without a workload.
- **An automatic YouTube archive:** Glance's channel list makes the idea
  relevant, but an
  [August Pinchflat discussion](https://www.reddit.com/r/selfhosted/comments/1vi7b4b/pinchflat_alternative/)
  reports maintenance and downloading problems. These are user reports, not
  a verified declaration that the project is abandoned. Compare current
  maintenance and test real downloads before choosing an archiver.

## Suggested first trials

1. **Daily use:** save 20 real links in Karakeep and see whether search and
   retrieval improve the current workflow.
2. **Fun:** import one platform into RomM and verify browser play on the device
   that would actually be used.
3. **Connected personal data:** import a short existing location track into
   Dawarich, connect Immich, and inspect the resulting map before committing
   to ongoing location collection.
4. **Polish existing services:** connect one app to Pocket ID and verify its
   browser and mobile login flows.

These are proposed trials, not completed deployments.
