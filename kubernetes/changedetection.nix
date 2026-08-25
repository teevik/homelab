{ ... }:
{
  # Website change monitoring (changedetection.io). Watches pages and sends
  # notifications via ntfy (configure watches + notification URLs in the UI,
  # e.g. ntfy://ntfy.ntfy.svc.cluster.local/<topic>). Pages are rendered in a
  # real headless Chrome (sockpuppetbrowser) so JS-heavy and Cloudflare-fronted
  # sites work.
  applications.changedetection = {
    namespace = "changedetection";
    createNamespace = true;

    resources = {
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

      # --- changedetection.io webserver ---

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
              # renovate: datasource=docker depName=docker.io/dgtlmoon/changedetection.io
              image = "docker.io/dgtlmoon/changedetection.io:0.55.8@sha256:5438423d5e906eff4e8f7886823482ad23f472bf7b8530ccaca89fb48c337882";
              ports.http.containerPort = 5000;
              env = {
                BASE_URL.value = "http://changedetection.tail84b6c.ts.net";
                PLAYWRIGHT_DRIVER_URL.value = "ws://changedetection-browser:3000/?stealth=1";
                TZ.value = "Europe/Oslo";
              };
              volumeMounts."/datastore".name = "data";
              securityContext = {
                allowPrivilegeEscalation = false;
                capabilities.drop = [ "ALL" ];
                seccompProfile.type = "RuntimeDefault";
              };
              resources = {
                requests = {
                  cpu = "50m";
                  memory = "128Mi";
                };
                limits.memory = "512Mi";
              };
            };
            volumes.data.persistentVolumeClaim.claimName = "changedetection-data";
          };
        };
      };

      # --- Headless Chrome for JS rendering / Cloudflare ---

      deployments.changedetection-browser.spec = {
        replicas = 1;
        selector.matchLabels.app = "changedetection-browser";
        template = {
          metadata.labels.app = "changedetection-browser";
          spec = {
            automountServiceAccountToken = false;
            containers.sockpuppetbrowser = {
              # renovate: datasource=docker depName=docker.io/dgtlmoon/sockpuppetbrowser
              image = "docker.io/dgtlmoon/sockpuppetbrowser:0.0.3@sha256:23a7be698216407648b6c78fc55de0411bde550635edc30347373c86a5176fad";
              ports.ws.containerPort = 3000;
              env = {
                SCREEN_WIDTH.value = "1920";
                SCREEN_HEIGHT.value = "1024";
                SCREEN_DEPTH.value = "16";
                MAX_CONCURRENT_CHROME_PROCESSES.value = "3";
              };
              # Chrome's sandbox needs SYS_ADMIN (upstream-documented setup)
              securityContext.capabilities.add = [ "SYS_ADMIN" ];
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "256Mi";
                };
                limits.memory = "2Gi";
              };
            };
          };
        };
      };

      services.changedetection-browser.spec = {
        selector.app = "changedetection-browser";
        ports.ws = {
          port = 3000;
          targetPort = 3000;
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
