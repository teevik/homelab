# TTY dashboard: layout, type and palette study

Throwaway prototype for [Choose the final TTY layout, typography, and palette](https://github.com/teevik/homelab/issues/70), in [Create the final TTY dashboard visual design](https://github.com/teevik/homelab/issues/69). **All readings are illustrative fixtures, not live data.** Not production code. No host, cluster, getty, font or display state is touched.

## Run

From this directory:

```sh
nix shell nixpkgs#cargo nixpkgs#rustc nixpkgs#gcc -c cargo run --release              # interactive
nix shell nixpkgs#cargo nixpkgs#rustc nixpkgs#gcc -c cargo run --release -- --png out # console-faithful PNGs
```

Interactive keys: `←`/`→` switch variant, `n`/`m` normal or mixed-attention fixture, `↑`/`↓` scroll, `Ctrl+C` or `q` quit. The amber pill on the bottom row is the prototype switcher, not part of the design. The program loads the proposed palette into the terminal (OSC 4, or `ESC ] P` on `TERM=linux`) and resets it on exit. A graphical terminal preview shows neither the console font nor the console's colour rules. Use the PNGs for that.

`--png` renders each variant and fixture at every console geometry into 2560×1600 images. It uses the real console glyph bitmaps and applies the Linux 6.18 VT colour rules. Any glyph missing from the font, any bright background or any bold/italic/underline/dim/reverse attribute is reported. The committed `screenshots/` report none.

## Measured facts (read-only, 2026-09-30)

- Laptop: ROG Zephyrus G14 GA402RK, eDP panel 2560×1600, amdgpu framebuffer (`amdgpudrmfb`).
- tty1 is **160×50** today. No `console.font` is configured (`/etc/vconsole.conf` has only `KEYMAP=us`), so fbcon uses the kernel built-in **TER16x32** (Terminus 16×32 bold, 256 glyphs, default CP437 Unicode map).

## Console constraints (Linux 6.18 `vt.c`, checked in source)

- Crossterm writes every colour as `38;5;n` / `48;5;n`. For n < 16 the VT maps foregrounds back onto palette slots 0–15. **Backgrounds fold to slots 0–7**: slot 8+ grounds become 0–7. The palette spends slots 1 and 4 on dark grounds for that reason.
- Bold only flips the bright bit. Italic, underline and half-bright become substitute colours. Reverse swaps only the low three bits. The design uses no attributes, only explicit palette slots.
- A **512-glyph font drops the console to 8 foreground colours**, because the bright bit becomes a glyph-index bit. That rules out Spleen (all sizes) and Terminus `ter-v*`. Terminus `ter-1*`/`ter-u*`/`ter-i*` are 256 glyphs.
- Only `ter-i*`, `ter-k*`, `ter-m*` and `ter-u*` at 12×24 carry `▀▄`. `ter-124b` lacks them. The prototype uses **`ter-i24b`** (CP437).
- Glyphs used: ASCII, `█ ▀ ▄ ░ ─ │ · ■ ▲ ↑ ↓ ◄ ► °`. No Braille, eighth blocks, emoji or Nerd Font icons.
- The kernel accepts fonts up to 64×128 (`KD_FONT_OP_SET_TALL`), and fbcon's blit supports 24- and 32-pixel widths. Loading a 24×48 or 32×64 font through the NixOS console setup, and `setfont`'s tall-font support, are **not yet verified on the laptop**.

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
| **A · Instrument ledger** | 2× block-letter status band, fixed 4-row attention slot, then a full ledger. Endpoints (check, latency) sit left of a rule, Argo app/sync/health right of it, with apps that have no endpoint listed underneath. Host meters, temperature history and source ages fill the right column. Stable catalog order; failing rows get an ember ground. | 160×50 | Everything visible and nothing moves. Body text is small at 1 m, but the status word is huge. |
| **B · Attention first** | 1× status band, then problems expanded worst-first. Healthy endpoints collapse into a 4-column name grid. Apps show only a count plus the no-endpoint list. Instruments and a full-width temperature history sit along the bottom. | 106×33 | Body text is readable at 1 m. Healthy detail is compressed, so per-app sync/health is not shown when fine. |
| **C · Large type** | Status band, up to 3 one-line problems, endpoints in 2 columns (catalog order), one apps line, and instruments in 2 lines. No temperature history. Scrolls with `↓ n` if the service list outgrows the screen. | 80×25 | Everything readable at 1 m. Least detail. |

Small-screen rule, as prototyped: A falls back to C's compact layout below 150×45, and B below 100×30. Under 60×20 only the status word and one summary line remain. PNGs of every variant at every size show this.

### Palette (NixOS `console.colors`, slots 0–15)

`13120f 4d2217 9aac86 c9964f 2a2620 9d7d93 71858a c4baa2 5a5347 ff8a5c c2d6a0 f3bd62 8ea3c4 dba6c9 a6c1c2 f1e7cd`

These are soot ground, ember ground, lichen (ok), brass (labels), raised ground, heather (Argo cue), slate (metadata), parchment (text), ash (rules), ember (failing), bright lichen (all clear), amber (heat), moon (night note), bright heather (deployment problem), bright slate (unknown), ivory (values). Reachability uses lichen/ember with `·`/`■`. Deployment uses heather with `▲`. The two are never merged into one state.

## Fixtures

- Endpoints: the 16 sites in `kubernetes/glance.nix`, with stable ids in catalog order.
- Apps: the 18 Argo Applications in `manifests/homelab/apps`. Immich Share maps to `immich`, Grafana to `victoria-metrics`, and Nix Cache has no app. amd-device-plugin, cloudflare-tunnel, glance-agent and tailscale-operator have no endpoint.
- Mixed fixture: Registry fails with HTTP 503 and its app is Degraded. Changedetection times out and its pod has 5 restarts in 15m (app Progressing). Paperless-ngx is OutOfSync while its endpoint is fine. Two alerts are active; CPU is at 86% and temperature at 83 °C and rising. "8 signals on 3 services" counts signals, not incidents. Thresholds and alert names are illustrative.
- The stale, unknown, cold-start and missing-sensor states belong to [Approve TTY health states and interaction details](https://github.com/teevik/homelab/issues/71).
