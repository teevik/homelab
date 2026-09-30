# Laptop health display: visual studies

Throwaway primary source for [Choose the laptop display’s visual direction](https://github.com/teevik/homelab/issues/65), within [Design a distinctive laptop health display](https://github.com/teevik/homelab/issues/62). **Awaiting the owner's reaction; no visual decision has been made.**

Run from the repository root:

```sh
python3 docs/prototypes/laptop-health-display/serve.py
```

Open http://127.0.0.1:8765/. It is also possible to open `index.html` directly. No dependencies, external assets, live queries, stored preferences, or host/display controls. This is a new host-local display concept; the existing Glance page is not its application shell, so the study has its own throwaway route under `docs/prototypes`.

Use the bottom arrows (or keyboard left/right) to switch designs. Scenario buttons preserve the selected design. The URL preserves `variant=A|B|C`, `state=normal|warning|stale|missing`, and optional `scale=large`. The fixture details disclose all data. Comparison controls appear only on loopback/file URLs, and this directory is not wired into any production build or deployment.

## Design question

Which layout should live on the laptop: a service-first terminal instrument panel, a relationship-first bespoke GUI, or a temperature/history-first bespoke GUI? The user may combine elements. Evaluate the hierarchy at laptop scale and the intended viewing distance, then settle direction and content priority through live feedback.

| Variant | Composition and signature | Palette | Typography |
| --- | --- | --- | --- |
| A · Terminal instruments | Broad status line above aligned service ledger and character-cell host meters. Terminal framing is the signature. | Charcoal `#151613`, ivory `#e6ddc5`, amber `#ddaf69`, sage `#bdc9aa`, warning peach `#f2a477` | Iosevka utility/display, DejaVu Sans Mono fallback. Terminal has one deliberate monospace family. |
| B · Service schematic | A dependency drawing occupies the main field; a narrow service-check rail and host readings surround it. Configured wires are the signature. | Marine `#152333`, ice `#d9e9f1`, powder blue `#abc9ee`, sea glass `#a4d3c8`, warning apricot `#ffc39b` | Source Sans 3 labels/display, Iosevka data. System sans/mono fallbacks. |
| C · Thermal observatory | Large temperature and continuous one-hour landscape dominate; explicit attention band, service watch below. Thermal landscape is the signature. | Aubergine `#241d2d`, pale mauve `#eee5ed`, orchid `#d8b1d4`, lichen `#bfceba`, warning peach `#ffbca1` | TeX Gyre Pagella restrained display, Source Sans 3 body, Iosevka data. Georgia/system fallbacks. |

The initial plan deliberately gives each variant a different information hierarchy. All use low-luminance backgrounds for a bedroom display; actual brightness is a later hardware check. No decorative animation, generic card grid, or Grafana view. Fonts use local system families with fallbacks rather than network loading.

## Evidence and fixtures

Service names and check inventory come from `kubernetes/glance.nix`. Eight services form an explicit illustrative subset, not a claim that the cluster has eight services. CPU means five-minute utilization, root usage means the host root filesystem, and temperature is a hypothetical CPU sensor pending actual label verification.

The schematic is an excerpt of relationships configured in `kubernetes/immich.nix` and `kubernetes/paperless-ngx.nix`: Immich uses PostgreSQL/Valkey and Longhorn-backed library/database storage; Paperless uses PostgreSQL/Redis and Longhorn-backed storage. It intentionally omits other dependencies. Dashed lines depict configured dependencies, not connectivity measurements or causal diagnoses. Database/cache health is unmeasured. A Longhorn HTTP check does not establish volume health.

| Scenario | Checks / alerts | Host readings | Meaning |
| --- | --- | --- | --- |
| Normal | Eight passing HTTP checks, zero active alerts, monitoring current | CPU 28%, RAM 43%, host root 58%, CPU sensor 54°C | Sample age 20 seconds. |
| Warning | Registry HTTP failure for four minutes; one illustrative active alert | CPU 86%, RAM 67%, root 58%, sensor 83°C | All sources current; temperature rising. Alert names/thresholds are not production decisions. |
| Stale | Current checks and alerts unknown | Last known normal readings, eight minutes old | Old values remain marked old, and plot styling loses emphasis. No fresh all-clear. |
| Missing | Checks and alerts unknown | No samples; em dashes and empty history | No missing value is converted to zero. |

Fan speed and GPU utilization are unavailable in every scenario. The frozen sample clock reads 21:42 Europe/Oslo. Night policy is a static reminder of the already accepted 23:00–08:00 screen/lid darkness, not a simulation or physical control. Data recovery, health aggregation, alert precedence, wake override duration and runtime are still owned by [Settle startup, data freshness, and night-mode behavior](https://github.com/teevik/homelab/issues/66).

Relevant research: [custom runtimes and health data](https://github.com/teevik/homelab/blob/f149d9b83be7179fdcc3be19dd4c92ea564b23ee/docs/research/laptop-display-data.md), [screen/lid power control](https://github.com/teevik/homelab/blob/0d99d4af93caf29af43fcffdd12840a9b0f2fd29/docs/research/laptop-display-power.md).

**A is an HTML TUI mockup, not a working terminal or evidence of virtual-console compatibility.** No production code is to be promoted from this branch. After selection, preserve this study as evidence and record the decision in the ticket, following the planning-only map.

## Feedback still needed

- Preferred direction, or a specific combination of elements.
- Viewing distance and which information must remain legible there.
- Content priority: service failures/alerts, temperature, history, resource usage.

The optional larger-text control permits an initial readability comparison. Actual laptop resolution, desktop scaling and physical readability still require implementation acceptance.

## Review checks

The local prototype was exercised through the T3 collaborative browser. Browser DOM/layout measurements at 1366×768 and 1280×800 checked the normal, warning, stale and missing scenarios across all three variants; default layouts fit the laptop viewport. A 390×844 layout check verified no horizontal overflow (vertical scrolling is expected on a phone). Scenario switching, URL updates, keyboard cycling and larger-text controls were exercised. The larger-text mode is an exploratory readability option and can require additional vertical space.

T3 screenshot/snapshot capture and viewport resizing failed in this session. The layout sizes above were inspected in same-origin, explicitly sized browser frames through T3, not on physical laptop hardware. Screenshot-based visual QA remains unavailable; do not treat the layout checks as the owner's visual review or a physical readability result.
