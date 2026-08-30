{ ... }:
let
  # The image is built in-cluster from images/changedetection (see the
  # build-changedetection Job below). Its tag is derived from the build
  # inputs, so any change Renovate makes to the Dockerfile or requirements
  # yields a new tag and therefore a rebuild on the next sync.
  dockerfile = builtins.readFile ../images/changedetection/Dockerfile;
  requirements = builtins.readFile ../images/changedetection/requirements.txt;
  upstreamVersion = builtins.head (
    builtins.match ".*changedetection\\.io:([^@[:space:]]+)@.*" dockerfile
  );
  imageTag = "${upstreamVersion}-${
    builtins.substring 0 8 (builtins.hashString "sha256" (dockerfile + requirements))
  }";
in
{
  # Website change monitoring (changedetection.io). Watches pages and sends
  # notifications via ntfy (configure watches + notification URLs in the UI,
  # e.g. ntfy://ntfy.ntfy.svc.cluster.local/<topic>).
  #
  # Pages are rendered by the CloakBrowser stealth fetcher: a fingerprint-
  # patched Chromium that runs inside the changedetection pod and gets past
  # Cloudflare Turnstile / bot detection that a plain headless Chrome trips.
  # The plugin and its Chromium are baked into a custom image built by the
  # PreSync Job below into the in-cluster registry; pick "CloakBrowser" as
  # the fetcher per watch or as the system default in the UI.
  applications.changedetection = {
    namespace = "changedetection";
    createNamespace = true;

    # The PreSync build Job fails if the registry is not up yet (fresh cluster,
    # zot restarting); let Argo CD retry the sync instead of stalling on it.
    syncPolicy.retry = {
      limit = 10;
      backoff = {
        duration = "30s";
        factor = 2;
        maxDuration = "10m";
      };
    };

    resources = {
      # Build context for the PreSync Job: the Dockerfile and its pins.
      configMaps.changedetection-build-context.data = {
        Dockerfile = dockerfile;
        "requirements.txt" = requirements;
      };

      jobs.build-changedetection = import ./lib/build-job.nix {
        name = "build-changedetection";
        pushSecret = "changedetection-registry-push";
        contextConfigMap = "changedetection-build-context";
        builds = [
          {
            image = "changedetection";
            tag = imageTag;
            context = "/workspace";
          }
        ];
      };

      persistentVolumeClaims.changedetection-data = {
        metadata.labels = {
          "recurring-job.longhorn.io/source" = "enabled";
          "recurring-job-group.longhorn.io/backup" = "enabled";
          "recurring-job-group.longhorn.io/snapshot" = "enabled";
        };
        spec = {
          storageClassName = "longhorn";
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "1Gi";
        };
      };

      deployments.changedetection.spec = {
        replicas = 1;
        strategy.type = "Recreate"; # RWO PVC
        selector.matchLabels.app = "changedetection";
        template = {
          metadata.labels.app = "changedetection";
          spec = {
            automountServiceAccountToken = false;
            securityContext = {
              runAsUser = 1000;
              runAsGroup = 1000;
              fsGroup = 1000;
            };
            containers.changedetection = {
              # Built by the build-changedetection Job above; the node pulls
              # it over the tailnet (kubernetes/registry.nix).
              image = "registry.tail84b6c.ts.net/changedetection:${imageTag}";
              ports.http.containerPort = 5000;
              env = {
                BASE_URL.value = "http://changedetection.tail84b6c.ts.net";
                TZ.value = "Europe/Oslo";
                # Fetcher for new installs / watches set to "system default".
                DEFAULT_FETCH_BACKEND.value = "html_cloakbrowser";
                # Each fetch launches its own Chromium; bound concurrency to
                # keep memory predictable (was MAX_CONCURRENT_CHROME_PROCESSES).
                FETCH_WORKERS.value = "3";
                # uid 1000 has no passwd entry in the image; Chromium wants a
                # writable home for its config/cache directories.
                HOME.value = "/tmp";
              };
              volumeMounts = {
                "/datastore".name = "data";
                # Chromium uses /dev/shm for renderer shared memory; the
                # container-runtime default of 64Mi crashes tabs on big pages.
                "/dev/shm".name = "dshm";
              };
              # CloakBrowser launches Chromium with --no-sandbox, so no extra
              # capabilities are needed for the in-pod browser.
              securityContext = {
                allowPrivilegeEscalation = false;
                capabilities.drop = [ "ALL" ];
                seccompProfile.type = "RuntimeDefault";
              };
              resources = {
                requests = {
                  cpu = "200m";
                  memory = "512Mi";
                };
                limits.memory = "2Gi";
              };
            };
            volumes = {
              data.persistentVolumeClaim.claimName = "changedetection-data";
              dshm.emptyDir = {
                medium = "Memory";
                sizeLimit = "1Gi";
              };
            };
          };
        };
      };

      # --- Tailscale ingress ---

      services.changedetection-tailscale = {
        metadata.annotations = {
          "tailscale.com/proxy-group" = "ingress";
          "tailscale.com/hostname" = "changedetection";
        };
        spec = {
          type = "LoadBalancer";
          loadBalancerClass = "tailscale";
          selector.app = "changedetection";
          ports.http = {
            port = 80;
            targetPort = 5000;
          };
        };
      };
    };
  };
}
