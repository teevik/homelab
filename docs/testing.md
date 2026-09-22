# Homelab testing

Run `just check` (or `nix flake check -L --no-update-lock-file`) before merging
configuration or dependency changes. GitHub runs the same checks on every PR,
including commits added by manifest regeneration. The stable aggregate status
is **Homelab validation**; this is the status to require on `main`.

## What runs

- Blueprint's host build, development shell, application package, and existing
  private cache tests. The public NixOS module outputs are wrapped as imports so
  they also satisfy flake output validation.
- `checks/manifests.nix`: compare fresh nixidy output with the entire committed
  manifest tree; validate every resource with pinned Kubernetes schemas and
  schemas extracted from the rendered CRDs; enforce the deployment invariants
  in `tests/manifest-policy.json`. No missing schemas are silently skipped.
- `checks/k3s.nix`: boot the real Kubernetes NixOS module in a disposable VM;
  check Secret provisioning, cluster DNS, Service traffic, k3s restart, and
  reboot recovery. It uses fake secret files and preloaded container images.
- Changed custom image sources are built with Docker in separate CI jobs.
  `homelab.teevik.dev/image-builds` annotations on the BuildKit Jobs expose their
  source revisions. Local build contexts come from the rendered ConfigMaps.
  The source plan is compared against the PR base, so unchanged builds are
  skipped. Changes to build context files still trigger a build even if a tag
  was accidentally left unchanged. The first rollout builds all five images
  because the base branch has no build-plan annotations yet.

The image jobs build locally and do not publish. They verify the source build,
not the full production BuildKit Job or byte-for-byte identity with a later
production rebuild. Mutable apt/pip/Chromium downloads can change the artifact.

## Focused local commands

```sh
just check-manifests
just check-k3s
nix develop --command python3 scripts/build-images.py manifests/homelab --list
nix develop --command python3 scripts/build-images.py manifests/homelab --image amp/amp
```

The VM check needs Linux with working `/dev/kvm` and Nix's `kvm` system feature.
The GitHub Nix installer configures KVM when available; CI fails explicitly if
the runner cannot provide it. The VM uses 4 GiB RAM, two CPUs, and an 8 GiB
disposable disk. Its initial local runtime was about three minutes, including
an orderly reboot. Nix caches successful deterministic checks.

## Updating expectations

Regenerate manifests with `nix develop --command nixidy switch .#homelab` and
commit them with the source change. The check compares files without modifying
the worktree, including detecting missing, extra, and renamed files.

`tests/manifest-policy.json` records the persistent volumes whose identity and
storage class must be preserved, required Longhorn backup labels, the early
network policy for KodeKamp's image build, and specific infrastructure exceptions
for host access and public Funnel ingresses. Change these deliberately alongside
an intentional service removal, migration, or exposure change. Do not regenerate
the policy automatically from candidate manifests.

The host access exceptions cover Longhorn's storage management, the AMD device
plugin, host statistics exporters, and AMP's game networking. The only public
Funnel ingress exceptions are the Argo webhook and Immich share proxy. These
checks detect new exposed resources; they do not verify the proxies' runtime
authorization or their allowed HTTP routes.

`tests/kubernetes-schemas.nix` pins a Kubernetes schema version, source revision,
and hashes. A k3s minor-version change requires updating that pin to the matching
Kubernetes minor before validation can pass. Refresh the sparse-checkout hash
with Nix's reported fixed-output hash and the two raw JSON hashes with
`nix store prefetch-file --json <pinned-url>`. Recursive CRD definitions use local
JSON references because standalone schemas cannot represent their recursion.

## Coverage still to add

Application data migrations, Longhorn volume upgrades/restores, Immich's GPU,
external Tailscale/Cloudflare behavior, and production backup recovery are not
covered by the VM. The next useful test is Paperless's base-to-candidate upgrade
with synthetic documents; see [the testing research](research/automated-homelab-testing.md).
Vulnerability scans and live availability checks also need separate fresh runs
rather than reuse of cached Nix test results.
