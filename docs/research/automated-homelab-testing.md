# Automated testing for homelab updates

Researched: 2026-09-22. This is a recommendation based on repository inspection
and primary documentation. No workflows, cluster resources, branch rules, or
services were changed; no proposed VM or application upgrade test was executed.

## Recommendation

Add a required PR validation workflow first, then a small NixOS VM test for the
host/K3s integration, and one stateful application upgrade test. The most useful
first application is Paperless: ingest a synthetic document on the base version,
upgrade to the PR version, and verify that the document and its metadata survive
and that a new document can still be ingested. These layers answer different
questions: can the configuration build, can it run, and can it preserve existing
data during an update?

Do not begin by replicating the entire homelab in every PR. Tailscale, Cloudflare,
the AMD GPU, private image builds, and Longhorn add substantial fixture and
infrastructure requirements. Test those boundaries deliberately as coverage grows.

## What exists now

- [The regeneration workflow](../../.github/workflows/nixidy-regenerate.yml)
  refreshes chart hashes and generated manifests on selected `renovate/**`
  pushes. It does not boot services or exercise application upgrades.
- [Blueprint](../../flake.nix) already exposes four checks: `devshell-default`,
  `nixos-homelab`, `pkgs-anime-matrix-stats`, and `private-nix-cache`. Repository
  evaluation confirmed that `nixos-homelab` is the actual host system toplevel.
  Consequently, **`nix flake check -L` already includes building the host here**;
  a second explicit host build is unnecessary. The
  [cache check](../../checks/private-nix-cache.nix) runs six Python tests but is
  not called by a general PR workflow.
- The host runs K3s with embedded etcd and provisioned Kubernetes Secrets via
  [systemd units](../../modules/nixos/kubernetes.nix). Applications are rendered
  by nixidy and [automatically synced by Argo CD](../../kubernetes/homelab.nix).
- [Custom image build Jobs](../../kubernetes/lib/build-job.nix) run during Argo
  PreSync. Manifest generation alone does not build their Dockerfiles.
- Read-only GitHub API inspection found the active `main` rules only prohibit
  deletion and force pushes; required status checks and PR review requirements
  were absent. Passing checks should become a merge prerequisite once reliable.

The general Nix distinction remains useful: `nix flake check` builds derivations
under `checks`; evaluating a `nixosConfigurations` output alone is not a system
build. Blueprint supplies the bridge in this repository.
([Nix flake check manual](https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-flake-check.html))

## 1. Required build and manifest checks on every PR

Run the existing flake checks, regenerate manifests from the committed inputs,
and fail when the generated tree differs from the committed tree. Include newly
generated/untracked files in that comparison. The checker should consume pinned
chart hashes; updating hashes remains the regeneration workflow's responsibility.
The required checks must run again after that workflow commits its changes, so
the accepted result covers the final PR content.

Validate the rendered YAML with **kubeconform**, using strict schemas for the
Kubernetes version shipped by the pinned K3s package. Pin the schema inputs too.
For Argo CD, Tailscale, Longhorn, and VictoriaMetrics custom resources, derive
schemas from the selected chart CRDs or another version-matched source. Report
coverage and fail on missing schemas; globally ignoring missing schemas would
hide much of this repository's interesting configuration. Kubeconform checks
OpenAPI shape, not every API-server validation or runtime behavior.
([Kubeconform documentation](https://github.com/yannh/kubeconform#readme))

Add a handful of explicit invariants over the **final rendered resources**:

- Longhorn's uninstall Job and VictoriaMetrics' destructive cleanup hook must
  remain absent. The repository already documents incidents involving these
  hooks in [Longhorn](../../kubernetes/longhorn.nix) and
  [VictoriaMetrics](../../kubernetes/victoriametrics.nix). Checking the result
  catches an upstream chart renaming or ignoring the old values setting.
- Critical PVC names, storage classes, and backup opt-in labels must remain
  stable unless an intentional migration changes their declared expectations.
- Referenced Secrets/keys must be supplied by the host's declared secret
  inventory, by rendered resources, or by explicitly identified controllers.
- Required PreSync dependencies must precede custom image build Jobs; check
  both hook phase and sync wave, rather than resource presence alone.
- New privileged containers, host mounts, host networking, and externally
  exposed services should need explicit, narrow exceptions appropriate to this
  infrastructure. A universal ban would incorrectly reject Longhorn/device
  management components.

Prefer nixidy assertions for straightforward Nix-level invariants and a small
YAML checker for relationships in the complete rendered output. The exact
pinned nixidy source already supports global and application assertions.
Conftest/Rego is a reasonable alternative if policies grow, but introducing a
second policy language is optional.
([Nixidy assertions](https://nixidy.dev/user_guide/assertions/),
[Pinned assertion implementation](https://github.com/arnarg/nixidy/blob/6ec84e1121d323f3d7d782cd3ca1d93bb13a2053/modules/default.nix),
[Conftest](https://www.conftest.dev/))

Build changed custom Dockerfiles in CI, with synthetic build credentials and a
temporary/local registry when needed. This catches dependency installation and
image-build failures before production PreSync. Use the same source revision,
build arguments, and Dockerfile as the cluster. Initially this can be an ordinary
networked CI build using tools pinned by `nix develop`; it does not need to become
a hermetic Nix derivation to be valuable.

That verifies the build sources, not necessarily the exact production artifact:
the current Dockerfiles include mutable network downloads such as apt packages
and Chromium. Exact artifact fidelity requires deploying the image digest built
and tested by CI, rather than rebuilding it independently during production
PreSync.

## 2. NixOS VM integration tests

**`pkgs.testers.runNixOSTest` is the strongest Nix-specific option.** It builds
one or more declarative NixOS VMs, connects them on a test network, and drives
them through Python. Tests can start services, execute commands, check network
access, restart VMs, and inspect logs. Expose each test as a flake check to use
the same command locally and in CI. Successful results are cached by their Nix
inputs; a changed service package, module, test, or fixture invalidates that
result. This is useful for deterministic integration tests, not ongoing live
availability monitoring.
([NixOS integration testing tutorial](https://nix.dev/tutorials/nixos/integration-testing-using-virtual-machines.html))

The first VM should import the relevant production modules, with explicit test
overrides for the fixed LAN address and secret files. Use fake credentials and
a disposable filesystem. Do not merely recreate an unrelated minimal K3s setup
and call that coverage of the production module. Keep hardware/disk provisioning
outside this test; extracting reusable configuration is justified only where
necessary to import the real behavior.

Suggested assertions:

1. K3s becomes ready, creates the expected namespaces/Secrets, and the secret
   units finish successfully despite concurrent namespace creation.
2. A tiny preloaded workload runs, resolves cluster DNS, and can reach a Service
   through the CNI/firewall configuration.
3. Restart K3s and verify the Secret units and workload recover. A reboot can
   separately exercise startup ordering.
4. Add a focused ncps/Harmonia test: populate a small synthetic cache, restart or
   upgrade it, then fetch and verify the original artifact/signature. The
   [ncps investigation](ncps.md) already records a migration where success did
   not imply retained cache records. Such behavior deserves a fixture test.

The locked nixpkgs already has an upstream
[single-node K3s test](https://github.com/NixOS/nixpkgs/blob/e5bdc4a41d4c072fe1e3787eaa0320a384741d44/nixos/tests/rancher/single-node.nix)
that preloads an image, waits for a pod to become ready, and tests cleanup. Use
its setup as a reference, then add the repository-specific assertions above.

### Image and runner requirements

Ordinary sandboxed Nix test builds cannot depend on pulling container images
from the internet at runtime. The **pinned NixOS module already supports**
`services.k3s.images`, including
`config.services.k3s.package.airgap-images` for the matching K3s core images and
`pkgs.dockerTools.pullImage` for workloads. The latter needs the OCI digest and
the Nix fixed-output hash; a Renovate digest alone is not both. Preload init
containers, hook Jobs, and images created by operators as well. Confirm the
imported image names/digests match what containerd resolves, and avoid an
`Always` pull policy contacting a registry during an offline test.
([Pinned K3s module](https://github.com/NixOS/nixpkgs/blob/e5bdc4a41d4c072fe1e3787eaa0320a384741d44/nixos/modules/services/cluster/rancher/k3s.nix),
[K3s air-gap installation](https://docs.k3s.io/installation/airgap))

Plan for an x86_64 Linux builder with working `/dev/kvm` and the Nix `kvm`
system feature. Check this on the actual CI runner before choosing the test
budget. GitHub documents Linux hardware acceleration but does not promise
general nested virtualization support; avoid assuming all hosted runner types
can execute this test. A dedicated disposable Linux VM runner is an alternative
if hosted-runner support or resources are insufficient. A test of K3s alone is
much lighter than one also running application databases, OCR, and Longhorn.
([NixOS test requirements](https://github.com/NixOS/nixpkgs/blob/master/nixos/doc/manual/development/running-nixos-tests.section.md),
[GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners),
[GitHub virtualization caveat](https://docs.github.com/en/actions/concepts/runners/github-hosted-runners))

## 3. Application upgrade tests with synthetic data

A fresh-install smoke test misses the failure that matters most for stateful
updates. Build both the base-branch and candidate manifests/images as explicit
inputs, then exercise the actual transition on retained test volumes:

1. Start the base version of Paperless with PostgreSQL and Redis.
2. Upload a tiny generated document; wait for processing and verify metadata,
   search results, and a downloaded-file checksum.
3. Apply the candidate configuration to the same installation and wait for
   database migrations and readiness.
4. Verify the old document and metadata, then ingest a second document.
5. Restart the workload and repeat the read checks.

Paperless documents that updates apply database migrations. If initializing
fixtures through its exporter/importer, restore into the matching old version
first: its documentation explicitly disallows importing an export into a
different Paperless version. Upgrade only after that restoration succeeds.
([Paperless administration source](https://github.com/paperless-ngx/paperless-ngx/blob/main/docs/administration.md))

This can run inside a NixOS/K3s VM for host fidelity, or in **k3d** for a simpler
networked CI job. k3d runs K3s in Docker and supports selecting its image version;
it does not test the NixOS kernel, systemd units, or host configuration. Nix can
still pin k3d/kubectl and provide a reproducible test entry point.
([k3d](https://k3d.io/stable/),
[Cluster creation options](https://k3d.io/stable/usage/commands/k3d_cluster_create/))

Use the real application module with small documented test overrides. A local
storage class can cover application migration/persistence, but then **Longhorn
is outside that test's coverage**. A separate Longhorn update test should attach
a real test volume, write known bytes, upgrade, reattach, and check those bytes.
Likewise, an Immich CPU test can cover upload, retrieval, metadata, and database
migrations without validating ROCm/GPU behavior.

For Argo-specific hook ordering, pruning, and reconciliation, use Argo CD in a
disposable test cluster or test the relevant behavior explicitly. Plain
`kubectl apply` does not reproduce Argo's deployment sequence and can execute
hook Jobs that Argo would handle differently. Avoid applying the whole generated
tree indiscriminately.

## 4. Recovery and security checks

Run a scheduled restore drill on disposable infrastructure: restore backups,
start the matching application version, and verify file checksums and useful
application reads. Start with synthetic backups in PR tests; a controlled
restore of actual off-site backups provides additional evidence that the real
backup path works. Production data and credentials do not belong in PR jobs.

The repository already schedules Longhorn snapshots and S3 backups. Volume
backup presence alone does not demonstrate a complete application recovery.
Immich explicitly requires both database and media backups, with ordering or
quiescence to keep them consistent. K3s datastore recovery also needs its server
token; etcd snapshots cover cluster state, while application volumes need their
own recovery path. A Nix generation rollback does not reverse application
database migrations or recover deleted volume data.
([Longhorn backup and restore](https://longhorn.io/docs/1.12.1/snapshots-and-backups/backup-and-restore/),
[Immich backup consistency](https://docs.immich.app/administration/backup-and-restore/#backup-ordering),
[K3s datastore backup](https://docs.k3s.io/datastore/backup-restore))

If “security” also means vulnerabilities, scan changed image digests with
**Trivy**, and schedule scans of deployed digests. Trivy supports severity,
fixed/unfixed filtering, and failure exit codes. Begin with visible reports;
later gate on a reviewed policy, such as newly introduced fixable critical
findings. Comparing base and candidate against the same vulnerability database
avoids confusing a newly disclosed existing issue with an update regression.
Mutable vulnerability feeds belong in a refreshed CI job, rather than an
indefinitely cached pure flake check. A clean scan is not evidence that the
application upgrade works.
([Trivy image scanning](https://trivy.dev/docs/dev/references/configuration/cli/trivy_image/),
[Trivy filtering](https://trivy.dev/docs/dev/configuration/filtering/))

## Suggested delivery order

| Order | Deliverable | Main confidence gained |
| --- | --- | --- |
| 1 | Required PR workflow: existing flake checks, manifest consistency, strict schemas, selected rendered invariants | Configuration builds and known dangerous regressions are rejected |
| 2 | Changed custom image builds and one K3s/Secret-unit VM check | Build failures and host integration failures surface before merge |
| 3 | Paperless base-to-candidate fixture test | Existing data survives the actual application update |
| 4 | Focused cache, Immich, Argo, and Longhorn tests when those components change | Coverage follows the important stateful boundaries |
| 5 | Scheduled restore drills, live read probes, and vulnerability scans | Recovery and changing external conditions are continuously checked |

Keep dependency groups small enough to identify the cause of a failed test.
The current broad non-major Docker group is convenient, but isolating important
stateful applications would make upgrade failures easier to interpret. Major
database/storage changes still deserve deliberate review even with green tests.
This is a prioritization recommendation, not a claim that any finite suite can
guarantee a safe production upgrade.
