# Adding a Service

Steps for adding a new application to the cluster. Done when all five are true.

1. Create `kubernetes/<name>.nix` defining `applications.<name>` — copy the shape of `kubernetes/ntfy.nix` (namespace, digest-pinned image with renovate comment, non-root securityContext, Tailscale LoadBalancer for the UI).
2. Import the module in `envs.homelab.modules` in `flake.nix`.
3. `git add -N kubernetes/<name>.nix` — flake evaluation ignores untracked files.
4. Add the service to the Glance monitor list in `kubernetes/glance.nix`: `url` is the tailnet hostname, `check-url` is the cluster-internal service (the `-tailscale` LoadBalancer service works).
5. Regenerate manifests with `nix develop -c nixidy switch .#homelab` and commit `manifests/` together with the source change. Argo CD deploys from pushed `main`; nothing reaches the cluster until then.

PVCs holding hard-to-recreate data get the Longhorn backup labels (see `kubernetes/paperless-ngx.nix`).
