# Reclip

Reclip is available on the tailnet at <http://reclip.tail84b6c.ts.net> after
deployment, with a link and health check in Glance. It has no application login;
access is controlled by the tailnet.

## Deployment

1. Deploy the NixOS configuration with `just deploy` to provision
   `reclip-registry-push` in the `reclip` namespace from the existing SOPS registry
   credential. No new credential is needed.
2. Commit the Reclip source configuration, lock file, and generated manifests
   together, then push to `main`. Argo CD builds the pinned upstream source with
   the existing rootless BuildKit PreSync Job, pushes it to zot, and starts Reclip.
3. Open Reclip from Glance or its tailnet URL.

The NixOS secret must exist before the first Argo CD sync can complete. Do not
apply the rendered manifests manually.

## Downloads and updates

Downloads stage in a disk-backed `emptyDir` limited to 10 GiB. Save completed files
to your browser's device. Replacing the pod clears the staged files; restarting
the application loses its in-memory job history. Upstream does not automatically
delete completed downloads, so staging can fill up; replacing the pod clears it
but also interrupts any active jobs.

The deployment uses one replica and upstream's single Gunicorn worker because
jobs are held in process memory. A source update replaces the pod and interrupts
active downloads.

Renovate updates the non-flake `reclip` input in `flake.lock`; the image tag is
derived from that commit. Upstream's startup update of yt-dlp remains enabled to
pick up extractor fixes. The source is pinned, but upstream's Docker base and
Python dependencies are not locked, so rebuilding can pick up newer dependencies.

Upstream: <https://github.com/averygan/reclip>.
