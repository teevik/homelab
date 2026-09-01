# Adding a Service

Steps for adding a new application to the cluster. Done when all five are true.

1. Create `kubernetes/<name>.nix` defining `applications.<name>` — copy the shape of `kubernetes/ntfy.nix` (namespace, digest-pinned image with renovate comment, non-root securityContext, Tailscale LoadBalancer for the UI).
2. Import the module in `envs.homelab.modules` in `flake.nix`.
3. `git add -N kubernetes/<name>.nix` — flake evaluation ignores untracked files.
4. Add the service to the Glance monitor list in `kubernetes/glance.nix`: `url` is the tailnet hostname, `check-url` is the cluster-internal service (the `-tailscale` LoadBalancer service works).
5. Regenerate manifests with `nix develop -c nixidy switch .#homelab` and commit `manifests/` together with the source change. Argo CD deploys from pushed `main`; nothing reaches the cluster until then. Never `nixidy apply` or `kubectl apply -f manifests/` by hand: the rendered tree contains Helm hook Jobs Argo CD deliberately never runs, and the cluster's `no-manual-apply` admission policy rejects client-side applies from non-system users.

If the service exposes Prometheus metrics, add a `VMServiceScrape` via `yamls` and a dashboard ConfigMap labeled `grafana_dashboard: "1"` with a `grafana_folder` annotation, both in the service's own module (see `kubernetes/longhorn.nix`). vmagent and the Grafana sidecar watch every namespace.

PVCs holding hard-to-recreate data get the Longhorn backup labels (see `kubernetes/paperless-ngx.nix`).

If the upstream image needs extra packages baked in, the cluster builds it itself: put a `Dockerfile` (plus a `requirements.txt` for pinned pip packages) under `images/<name>/`, embed them in a ConfigMap, and add a `jobs.build-<name> = import ./lib/build-job.nix { ... }` PreSync Job with a tag derived from the file contents — copy `kubernetes/changedetection.nix`. Argo CD runs the Job (rootless BuildKit) against the in-cluster zot registry (`kubernetes/registry.nix`) before rolling the Deployment, and the Job is a no-op when the tag already exists. If the source lives in another repo, pin it as a `flake = false` input and build from a git context tagged with the commit — copy `kubernetes/kodekamp.nix`; Renovate bumps flake inputs and `images/*`, and `nixidy-regenerate.yml` re-renders the tags. Never reference `registry.tail84b6c.ts.net/*` images by hand-written tags. Everything the Job needs at run time — its build-context ConfigMap, and in a namespace with a default-deny NetworkPolicy an egress policy for the `app: build-<name>` pod — must itself be a `PreSync` hook with `sync-wave: "-1"`: Argo CD applies regular resources only after PreSync hooks finish, so a Job that depends on one of them can never start. On a fresh install the only manual step is in the changedetection UI: Settings → Fetching → default fetcher "CloakBrowser" (the setting lives in its datastore, so `DEFAULT_FETCH_BACKEND` only seeds new installs).
