{ ... }:
{
  # Self-hosted push notification server. Alertmanager alerts are forwarded
  # here (via alertmanager-ntfy in the victoria-metrics namespace) and the
  # ntfy mobile/web app subscribes over the tailnet.
  applications.ntfy = {
    namespace = "ntfy";
    createNamespace = true;

    resources = {
      persistentVolumeClaims.ntfy-cache.spec = {
        storageClassName = "longhorn";
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = "1Gi";
      };

      deployments.ntfy.spec = {
        replicas = 1;
        strategy.type = "Recreate"; # RWO PVC
        selector.matchLabels.app = "ntfy";
        template = {
          metadata.labels.app = "ntfy";
          spec = {
            automountServiceAccountToken = false;
            securityContext = {
              runAsUser = 1000;
              runAsGroup = 1000;
              fsGroup = 1000;
            };
            containers.ntfy = {
              # renovate: datasource=docker depName=docker.io/binwiederhier/ntfy
              image = "docker.io/binwiederhier/ntfy:v2.27.0@sha256:f2419f405127afa868f10985c1a41449e673477cee1eb19994339a5ae8b592e7";
              args = [ "serve" ];
              ports.http.containerPort = 8080;
              env = {
                NTFY_BASE_URL.value = "http://ntfy.tail84b6c.ts.net";
                NTFY_LISTEN_HTTP.value = ":8080"; # unprivileged port, non-root user
                NTFY_BEHIND_PROXY.value = "true";
                # Forward poll requests through ntfy.sh -> APNs so the iOS
                # app gets instant notifications (iOS can't hold a background
                # connection to a self-hosted server).
                NTFY_UPSTREAM_BASE_URL.value = "https://ntfy.sh";
                NTFY_CACHE_FILE.value = "/var/cache/ntfy/cache.db";
              };
              volumeMounts."/var/cache/ntfy".name = "cache";
              securityContext = {
                allowPrivilegeEscalation = false;
                capabilities.drop = [ "ALL" ];
                seccompProfile.type = "RuntimeDefault";
              };
              resources = {
                requests = {
                  cpu = "10m";
                  memory = "64Mi";
                };
                limits.memory = "256Mi";
              };
            };
            volumes.cache.persistentVolumeClaim.claimName = "ntfy-cache";
          };
        };
      };

      # Cluster-internal endpoint used by alertmanager-ntfy
      services.ntfy.spec = {
        selector.app = "ntfy";
        ports.http = {
          port = 80;
          targetPort = 8080;
        };
      };

      # Tailnet endpoint for the ntfy apps
      services.ntfy-tailscale = {
        metadata.annotations = {
          "tailscale.com/proxy-group" = "ingress";
          "tailscale.com/hostname" = "ntfy";
        };
        spec = {
          type = "LoadBalancer";
          loadBalancerClass = "tailscale";
          selector.app = "ntfy";
          ports.http = {
            port = 80;
            targetPort = 8080;
          };
        };
      };
    };
  };
}
