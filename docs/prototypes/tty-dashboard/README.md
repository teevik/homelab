# TTY dashboard: layout, type, palette and health states

Throwaway prototype for [Choose the final TTY layout, typography, and palette](https://github.com/teevik/homelab/issues/70) and [Approve TTY health states and interaction details](https://github.com/teevik/homelab/issues/71), in [Create the final TTY dashboard visual design](https://github.com/teevik/homelab/issues/69). **All readings are illustrative fixtures, not live data.** Not production code. No host, cluster, getty, font or display state is touched.

## Run

From this directory:

```sh
nix shell nixpkgs#cargo nixpkgs#rustc nixpkgs#gcc -c cargo run --release                             # interactive
nix shell nixpkgs#cargo nixpkgs#rustc nixpkgs#gcc -c cargo run --release -- --png screenshots/states  # console-faithful PNGs
```

Interactive keys: `←`/`→` step through the 15 scenarios, `↑`/`↓` scroll, `Ctrl+C` closes. The header's centre label names the scenario; it is prototype-only. The program loads the palette (OSC 4, or `ESC ] P` on `TERM=linux`) and resets it on exit, then prints the shell handoff message. A graphical terminal shows neither the console font nor its colour rules. Use the PNGs for that.

The code now draws only the selected **A · Instrument ledger at 160×50**. The B/C variants and the 106×33 layout are in commit `1011672`, with their PNGs still in `screenshots/`.

## Health states and interaction (#71)

`--png` writes `screenshots/states/NN-<scenario>.png` at 160×50 with the kernel TER16x32 font. Every render reports no missing glyphs, no bright backgrounds and no text attributes. Attention rows, counts and the status word are derived from the fixture's per-source freshness in `src/data.rs` (`derive`). They are not hand-written.

| # | Scenario | Status |
| --- | --- | --- |
| 01 | normal | ALL CLEAR |
| 02 | one HTTP failure | ATTENTION |
| 03 | mixed attention | ATTENTION |
| 04 | many HTTP failures, attention overflow | ATTENTION |
| 05 | HTTP ok, deployment unhealthy / out of sync | ATTENTION |
| 06 | active alerts only, including one on no service | ATTENTION |
| 07 | cluster monitoring unavailable, host still current | UNKNOWN |
| 08 | alerts unavailable while a known failure exists | ATTENTION |
| 09 | expected endpoint and app missing | UNKNOWN |
| 10 | http check samples stale (4m) | UNKNOWN |
| 11 | recovery | ALL CLEAR |
| 12 | no CPU temperature sensor | ALL CLEAR |
| 13 | cold start | UNKNOWN |
| 14 | woken in quiet hours | ALL CLEAR |
| 15 | woken during bedtime | ALL CLEAR |

Proposed rules, as drawn:

- **Status word:** ATTENTION when any known signal exists; else UNKNOWN when any cluster source is waiting, stale or unavailable or a catalog entry has no data; else ALL CLEAR. UNKNOWN is yellow on base; ALL CLEAR green on base; ATTENTION text on the red-mix ground. The summary column is anchored to the ATTENTION width, so it never moves.
- **Attention rows:** one per service (catalog identity), tiered by its worst signal: `■` red HTTP check failing, `!` yellow active alert, `▲` mauve deployment only (health, sync, restarts), `?` yellow expected but no data. Tier first, then stable catalog order, so rows don't reshuffle as durations change. A shared app's signals attach to its first endpoint (immich → Immich). Alerts that map to no app get a row with their label (`cluster`). `endpoint ok` is appended when the endpoint answers despite other signals. `since` is the oldest signal. Counts say "signals on n services (and the cluster)", never incidents; coverage gaps are not counted as signals.
- **Overflow:** the slot is fixed at 4 rows. With more than 4 services, it shows 3 plus `+n more` with the remaining names. Failing rows are highlighted in the ledger. Signals that don't fit end in `+n more`, never mid-word.
- **Empty attention slot:** "Nothing needs attention." (ALL CLEAR). "No known problems, but health cannot be confirmed until every source is current." (UNKNOWN). "Waiting for first readings…" (cold start). Recoveries show as `· Registry  recovered · was HTTP 503 for 14m · ok since 21:38` under it. They don't affect status (proposed retention: 15 minutes).
- **Freshness:** each section header states its source: `every 30s · 21s ago`, `STALE · newest sample 4m old`, `UNAVAILABLE 6m · last results`, or `waiting for the first result`. Last-known *ok* values from a stale or unavailable source are dimmed to overlay1 and lose their green; known failures and Degraded stay at full strength. SOURCES lists each source's age and state, plus one reason line per distinct failure (e.g. HTTP 401 from the cluster API).
- **Unknown is never zero:** "alerts: unknown, alertmanager unavailable", not "no active alerts"; "endpoints: no current results"; CPU shows `--` / "measuring" until a second sample; the temperature history starts empty ("no history yet, it builds from now"); an unsupported sensor reads "unavailable. This does not affect service health."
- **Night:** the footer's right side shows the policy controller's state: `screen dark 23:00-08:00, in 1h 18m`, `quiet hours until 08:00 · woken, dark again at 02:24 (in 10m)` or `bedtime until 08:00 · woken, dark again at 22:16 (in 10m)`. The UI never controls power.
- **Controls:** the footer shows `Ctrl+C close, monitoring keeps running`; `↑↓ scroll services` appears only when the ledger overflows. Ctrl+C is the only exit key. After it, the shell prints "Dashboard closed. Monitoring and the night schedule keep running. Run `dashboard` to open it again." Checked in a pty with `TERM=linux`: exit status 0, `ESC ] R` palette reset, alternate screen left, cursor shown.
- **Redraw:** only on new data, freshness transitions, resize and input. Ages are recomputed on each redraw (at least every 5 s with host samples), not by a per-second timer. There is no animation or blinking.

## Layout study (#70)

## Measured facts (read-only, 2026-09-30)

- Laptop: ROG Zephyrus G14 GA402RK, eDP panel 2560×1600, amdgpu framebuffer (`amdgpudrmfb`).
- tty1 is **160×50** today. No `console.font` is configured (`/etc/vconsole.conf` has only `KEYMAP=us`), so fbcon uses the kernel built-in **TER16x32** (Terminus 16×32 bold, 256 glyphs, default CP437 Unicode map).

## Console constraints (Linux 6.18 `vt.c`, checked in source)

- Crossterm writes every colour as `38;5;n` / `48;5;n`. For n < 16 the VT maps foregrounds back onto palette slots 0–15. **Backgrounds fold to slots 0–7**: slot 8+ grounds become 0–7. The palette spends slots 1 and 4 on dark grounds for that reason.
- Bold only flips the bright bit. Italic, underline and half-bright become substitute colours. Reverse swaps only the low three bits. The design uses no attributes, only explicit palette slots.
- A **512-glyph font drops the console to 8 foreground colours**, because the bright bit becomes a glyph-index bit. That rules out Spleen (all sizes) and Terminus `ter-v*`. Terminus `ter-1*`/`ter-u*`/`ter-i*` are 256 glyphs.
- Only `ter-i*`, `ter-k*`, `ter-m*` and `ter-u*` at 12×24 carry `▀▄`. `ter-124b` lacks them. The prototype uses **`ter-i24b`** (CP437).
- Glyphs used: ASCII, `█ ▀ ▄ ░ ─ │ · ■ ▲ ↑ ↓ ◄ ► °`. No Braille, eighth blocks, emoji or Nerd Font icons.
- The kernel accepts fonts up to 64×128 (`KD_FONT_OP_SET_TALL`). The laptop runs kbd 2.9.0, whose `setfont` uses `KD_FONT_OP_SET_TALL`, and `setfont -d` doubles a font.
- **systemd 261's `systemd-vconsole-setup` copies the font to the other VTs with a hard 32×32 check.** For a taller font it logs "Invalid font metadata" and skips the copy, and the VT it treats as source is not guaranteed to be tty1. Don't rely on the global `console.font` for a 24×48 or 32×64 font. Load it explicitly on tty1, for example with `setfont -C /dev/tty1` from a tty1-scoped unit or the dashboard launcher. The other VTs keep the built-in 16×32. (Sources: [vconsole-setup.c v261.1](https://github.com/systemd/systemd/blob/v261.1/src/vconsole/vconsole-setup.c), [kbd kdfontop.c v2.9.0](https://github.com/legionus/kbd/blob/v2.9.0/src/libkfont/kdfontop.c).) Checking on the real panel is left to implementation acceptance.

## Console geometries on this panel

Assumes a 301.6 mm-wide active area (14" 16:10), which gives 0.118 mm per pixel. Cap heights are measured from the glyph bitmaps. About 5 arcmin is the threshold of legibility; about 16 arcmin is comfortable reading.

| Console | Font | Body cap height at 1 m | Status word at 1 m |
| --- | --- | --- | --- |
| **160×50** | built-in TER16x32 (today) | 2.4 mm, **8′**: legible, not comfortable | A: 26 mm, 91′ |
| **106×33** | `ter-i24b` doubled to 24×48 | 3.5 mm, **12′** | 20 mm, 68′ |
| **80×25** | TER16x32 doubled to 32×64 | 4.7 mm, **16′**: comfortable | 26 mm, 91′ |

The 106×33 grid is 2544×1584 px and leaves an 8 px border. Physical readability still needs the owner's look at the real panel.

## Variants

All three keep the selected hierarchy: prominent status and attention first, then the service checks, with host instruments secondary. Each variant is shown at its intended console size.

| | Layout | Console | Trade-off |
| --- | --- | --- | --- |
| **A · Instrument ledger** (owner's choice) | At 160×50: 2× block-letter status band, fixed 4-row attention slot, then a full ledger. Endpoints (check, latency) sit left of a rule, Argo app/sync/health right of it, with apps that have no endpoint listed underneath. Host meters, temperature history and source ages fill the right column. Stable catalog order; failing rows get an ember ground. | 160×50 | Everything visible and nothing moves. Body text is small at 1 m, but the status word is huge. |
| **A at 106×33** | Same status band, attention slot and endpoint/deployment ledger at 1× word size, without the 4-row gaps. The apps without an endpoint collapse to one line. Host meters and a 2-row temperature history move to a strip above the footer. Source ages fold into the summary. | 106×33 | Body text is 1.5× larger. The temperature history is coarse (4 levels) and per-source ages are dropped. |
| **B · Attention first** | 1× status band, then problems expanded worst-first. Healthy endpoints collapse into a 4-column name grid. Apps show only a count plus the no-endpoint list. Instruments and a full-width temperature history sit along the bottom. | 106×33 | Body text is readable at 1 m. Healthy detail is compressed, so per-app sync/health is not shown when fine. |
| **C · Large type** | Status band, up to 3 one-line problems, endpoints in 2 columns (catalog order), one apps line, and instruments in 2 lines. No temperature history. Scrolls with `↓ n` if the service list outgrows the screen. | 80×25 | Everything readable at 1 m. Least detail. |

Small-screen rule, as prototyped: A uses its full layout at 150×45 or more, its 106×33 layout at 100×30 or more, and C's compact layout below that. B falls back below 100×30. Under 60×20 only the status word and one summary line remain. PNGs of every variant at every size show this.

### Palette: Catppuccin Mocha (NixOS `console.colors`, slots 0–15)

`1e1e2e 53394c a6e3a1 b4befe 181825 9399b2 7f849c bac2de 45475a f38ba8 eba0ac f9e2af 89b4fa cba6f7 fab387 cdd6f4`

The swatches match [teevik/Config](https://github.com/teevik/Config): Mocha throughout, Lavender as the single structural accent (as in hyprlock), and Maroon (Noctalia's primary) only on the `HOMELAB` mark.

| Slot | Swatch | Role |
| --- | --- | --- |
| 0 | base | screen ground |
| 1 | red at 25% over base (derived) | attention band and failing-row ground |
| 2 | green | ok, ALL CLEAR |
| 3 | lavender | section labels |
| 4 | mantle | header/footer ground |
| 5 | overlay2 | quiet Argo state |
| 6 | overlay1 | ages, units, metadata |
| 7 | subtext1 | body text |
| 8 | surface1 | rules, empty meter cells |
| 9 | red | failing, and only failing |
| 10 | maroon | brand mark |
| 11 | yellow | warm reading |
| 12 | blue | normal instrument reading, night note |
| 13 | mauve | deployment problem (`▲`) |
| 14 | peach | hot reading |
| 15 | text | primary values |

Reachability uses green/red with `·`/`■`. Deployment uses overlay2/mauve with `▲`, in its own columns. Heat never uses red. Grounds stay in slots 0–7. The earlier amber/ivory study is commit `ca5ce73`.

## Fixtures

- Endpoints: the 16 sites in `kubernetes/glance.nix`, with stable ids in catalog order.
- Apps: the 18 Argo Applications in `manifests/homelab/apps`. Immich Share maps to `immich`, Grafana to `victoria-metrics`, and Nix Cache has no app. amd-device-plugin, cloudflare-tunnel, glance-agent and tailscale-operator have no endpoint.
- Mixed fixture: Registry fails with HTTP 503 and its app is Degraded. Changedetection times out and its pod has 5 restarts in 15m (app Progressing). Paperless-ngx is OutOfSync while its endpoint is fine. Two alerts are active; CPU is at 86% and temperature at 83 °C and rising. "8 signals on 3 services" counts signals, not incidents. Thresholds and alert names are illustrative.
- The stale, unknown, cold-start and missing-sensor states belong to [Approve TTY health states and interaction details](https://github.com/teevik/homelab/issues/71).
