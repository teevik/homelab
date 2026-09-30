# Non-Go runtimes for the laptop health display

Researched 2026-09-30 for
[Compare non-Go TUI runtimes and reusable dashboards](https://github.com/teevik/homelab/issues/67),
a prerequisite of
[Settle startup, data freshness, and night-mode behavior](https://github.com/teevik/homelab/issues/66).
This is factual research and a recommendation; the owner still selects the runtime.
No application, Nix derivation, hardware test, or performance benchmark was built.

## Recommendation

Prefer **Rust with Ratatui and Crossterm**, reusing libraries for collection and
terminal widgets while writing the small service-first display. It gives direct
control over when frames are drawn and a conventional Cargo-to-Nix build. That
fits an unattended appliance whose principal requirements are predictable
updates, readable custom instruments, and recovery rather than rich interaction.
This is an engineering judgment from the evidence below, not a measured claim
that Rust uses less CPU or memory than OpenTUI.

**TypeScript with OpenTUI on Bun is a credible alternative** if TypeScript is
more comfortable to maintain. Current OpenTUI supports demand-driven rendering;
there is no requirement to run a continuous animation loop. It can preserve the
accepted amber/ivory instrument design. Its additional native-package/runtime
packaging work is the principal trade-off here. Do not describe current OpenTUI
as simply Bun-only or assume that old development requirements still apply.

The three existing dashboards examined provide useful host instruments or
Kubernetes operations, but their documented configuration does not supply the
whole accepted service-check ledger, freshness policy, and independent host
fallback. Reusing a library is the narrower fit than maintaining a substantial
fork of one of those applications.

## Runtime comparison

| Concern | Rust / Ratatui | TypeScript / OpenTUI |
| --- | --- | --- |
| UI shape | Widgets, layout constraints, RGB colors, tables, charts, and custom widgets support the chosen display. | Core renderables or React/Solid, Flexbox layout, styled text, tables, and custom renderables support it. |
| Render scheduling | Application explicitly calls `Terminal::draw`; buffers are diffed before terminal output. | Initially demand-driven; tree changes request a frame. `start()` enables continuous rendering, which this display need not use. |
| Runtime | Compiled application with terminal backend and linked dependencies; no Rust compiler needed on the deployed host. | Bun or qualifying Node.js plus the matching Zig native library, or a packaged executable containing runtime/native assets. |
| Nix fit | Standard `rustPlatform.buildRustPackage`, checked-in Cargo lockfile, pinned dependency hash. | Feasible; must lock JS dependencies and ship the correct native artifact/assets. Source-building the native core adds Bun and Zig build requirements. |
| Collection | Separate tasks/channels update a display model; Ratatui does not supply host or service monitoring. | Async tasks update a display model outside rendering; OpenTUI does not supply host or service monitoring. |

The Ratatui UI/rendering claims follow its
[widget examples](https://ratatui.rs/examples/widgets/),
[terminal rendering API](https://docs.rs/ratatui/0.30.2/ratatui/struct.Terminal.html),
and [backend documentation](https://ratatui.rs/concepts/backends/).
OpenTUI's corresponding evidence is its
[introduction](https://opentui.com/docs/),
[renderer scheduling](https://opentui.com/docs/core-concepts/renderer/),
and [deployment guide](https://opentui.com/docs/ship/deploy/).
The collection separation is the proposed application architecture, not a
built-in monitoring feature of either library.

### Ratatui: dependencies and maturity

The latest stable release returned by GitHub was
[Ratatui 0.30.2, published 2026-06-19](https://github.com/ratatui/ratatui/releases/tag/ratatui-v0.30.2).
Its [workspace manifest](https://github.com/ratatui/ratatui/blob/ratatui-v0.30.2/Cargo.toml)
sets Rust 1.88 as the minimum and uses Crossterm 0.29. Align backend versions
instead of introducing independent incompatible Crossterm event queues.
Ratatui continued `tui-rs` development in 2023 and maintains examples, templates,
and a breaking-change record; this establishes a substantial existing ecosystem,
not a guarantee of unattended reliability.
([Project history](https://github.com/ratatui/ratatui#acknowledgements),
[backend compatibility](https://ratatui.rs/concepts/backends/).)

The homelab's nixpkgs pin already builds the Rust monitor bottom using
[`rustPlatform.buildRustPackage`](https://github.com/NixOS/nixpkgs/blob/e5bdc4a41d4c072fe1e3787eaa0320a384741d44/pkgs/by-name/bo/bottom/package.nix).
Use that packaging pattern for a bespoke application; the existence of a package
for the Ratatui library itself is unnecessary. Pin versions compatible with the
chosen Rust toolchain and account for any additional HTTP/TLS dependencies.

### OpenTUI: distinguish deployment from native development

The inspected upstream revision was
[`5a4c7d2d3306054ef281eb6cd6e2aa0f1d6513a2`](https://github.com/anomalyco/opentui/commit/5a4c7d2d3306054ef281eb6cd6e2aa0f1d6513a2),
whose [Core manifest](https://github.com/anomalyco/opentui/blob/5a4c7d2d3306054ef281eb6cd6e2aa0f1d6513a2/packages/core/package.json)
identifies version 0.5.13. Current
[runtime support documentation](https://opentui.com/docs/getting-started/runtime-support/)
requires **Bun 1.3.0+**, or **Node.js 26.4.0+ with ESM and
`--experimental-ffi`**. Linux x64 and arm64 artifacts exist for both glibc and
musl. Core's Node native/distribution acceptance runs on Linux x64; React has no
dedicated Node acceptance lane. For this project, Bun avoids selecting the
experimental Node FFI path.

[Upstream development](https://github.com/anomalyco/opentui/blob/5a4c7d2d3306054ef281eb6cd6e2aa0f1d6513a2/README.md)
requires **Bun 1.4.1+ and Zig 0.16.0**. Those are native-source development
requirements, not a requirement to install Zig on the dashboard host. Released
native packages and Bun executable embedding are supported. Ensure optional
native dependencies are retained; an installation can load JS while lacking the
library required by the first native operation.
([Runtime artifacts](https://opentui.com/docs/getting-started/runtime-support/),
[deployment forms](https://opentui.com/docs/ship/deploy/).)

Homelab's pinned nixpkgs supplies
[Bun 1.3.13](https://github.com/NixOS/nixpkgs/blob/e5bdc4a41d4c072fe1e3787eaa0320a384741d44/pkgs/by-name/bu/bun/package.nix):
above the documented runtime minimum, below current upstream development's
minimum. Its
[OpenCode derivation](https://github.com/NixOS/nixpkgs/blob/e5bdc4a41d4c072fe1e3787eaa0320a384741d44/pkgs/by-name/op/opencode/package.nix)
already demonstrates packaging an OpenTUI-based application using frozen Bun
dependencies and a compiled executable. This proves a Nix path exists; it does
not prove that a new application using current OpenTUI will build unchanged on
that pin. Explicitly select release artifacts versus source compilation and
verify the selected combination.

OpenTUI reports production use in OpenCode and has native, scheduler, lifecycle,
and package-distribution tests. That is meaningful maintenance evidence; its
0.x version and changing runtime surface still justify pinning the release and
checking upgrades. Source inspection is not a long-running appliance soak test.
([Project](https://github.com/anomalyco/opentui),
[test sources at inspected revision](https://github.com/anomalyco/opentui/tree/5a4c7d2d3306054ef281eb6cd6e2aa0f1d6513a2/packages/core/src/tests).)

## What can be reused

| Project | Useful existing functionality | Fit for this display |
| --- | --- | --- |
| [bottom](https://github.com/ClementTsang/bottom/tree/0.14.9) (Rust) | CPU, memory, network, disks, temperature, battery; configurable colors, update rate, and arrangement of its built-in widgets. | Strong ready-made host monitor. Its documented widget set has no HTTP service ledger or cluster freshness model. Those require application changes, not just a theme/config file. |
| [btop](https://github.com/aristocratos/btop/tree/v1.4.7) (C++) | Host resource monitoring, themes, layouts, and adjustable update interval. | Useful manual diagnostic companion. Its host-oriented boxes do not supply the required service/workload split and source-age policy. A fork would carry unrelated process-monitor functionality. |
| [KDash](https://github.com/kdash-rs/kdash/tree/v2.1.1) (Rust) | Kubernetes resources, logs, metrics, themes, and configurable tick/poll rates. | Useful interactive cluster tool. Metrics depend on cluster metrics-server; it is not an independent local-host fallback. Resource mutation, shell, and port-forward workflows are beyond this read-only display. |

These are conclusions from the documented feature sets, not a claim that the
projects could never be extended. Their latest GitHub stable releases were
[bottom 0.14.9 on 2026-08-27](https://github.com/ClementTsang/bottom/releases/tag/0.14.9),
[btop 1.4.7 on 2026-05-01](https://github.com/aristocratos/btop/releases/tag/v1.4.7),
and [KDash 2.1.1 on 2026-07-22](https://github.com/kdash-rs/kdash/releases/tag/v2.1.1).
None needs to be rejected as abandoned to conclude that its product scope differs.

For Rust host instruments, reuse
[`sysinfo`](https://docs.rs/sysinfo/0.39.6/sysinfo/), which exposes Linux CPU,
memory, disk, network, and temperature information. Keep its sampling instance
between updates, refresh only needed measurements, and avoid enumerating every
process just to display aggregate host readings. CPU/rate measurements need a
previous sample; show an initial unavailable state rather than fabricated zero.
The inspected latest version requires Rust 1.95, so do not assume that selecting
Ratatui's minimum compiler also satisfies every current collector dependency.
Sensor identity and availability still need verification on the actual laptop.

For HTTP probing, the upstream
[Prometheus blackbox exporter](https://github.com/prometheus/blackbox_exporter)
is reusable independently of the TUI: it implements HTTP and other probes and
exports `probe_success` and timing metrics. It is a Go program, but using an
existing binary does not require writing the display in Go. Whether to reuse it
or perform small direct host-side checks belongs in the data-access decision;
this research does not silently choose probe placement.

## Shared catalog and unattended operation

The proposed Nix service attrset is compatible with either runtime: derive
Glance configuration and a JSON description for the display/checks from the
same stable service IDs, display names, URLs, and probe targets. Neither runtime
needs to evaluate Nix while running. Keep probe location and expected response
semantics explicit: the same target observed from inside the cluster and from
the laptop can produce different, truthful results. This is a proposed boundary,
not a settled catalog schema.

In either implementation, collection must update a timestamped model outside
the render path. The renderer consumes snapshots; it should not wait for a
network request to finish before painting local readings. Schedule local
collection at five seconds and cluster collection at thirty seconds; render on
new data, freshness transitions, resize, or explicit control changes. Preserve
source sample timestamps separately from the time the client fetched them.
The previously accepted failure/staleness behavior remains application logic.

The fullscreen Alacritty/Sway session, unprivileged account, process restart,
and night-policy controller remain surrounding system services. Neither TUI
library guarantees boot ordering, process restart, physical panel darkness, or
AniMe Matrix state. In particular, suspending rendering is not screen-power
control. Keep those policies independent so a display crash cannot override
quiet hours. OpenTUI documents
[terminal cleanup](https://opentui.com/docs/core-concepts/lifecycle/), while
Ratatui documents
[panic/terminal restoration](https://ratatui.rs/recipes/apps/panic-hooks/);
verify shutdown and restart behavior in the actual launched session.

Remaining implementation checks are a reproducible package for the selected
version, correct fonts/colors/width in Alacritty, idle and update CPU/RSS on the
laptop, recovery when sources fail or a renderer exits, and hardware night-mode
acceptance. No numerical resource budget or performance comparison has been
established by this research.
