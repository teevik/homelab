{ ... }:
{
  # Self-hosted push notification server. Alertmanager alerts are forwarded
  # here (via alertmanager-ntfy in the victoria-metrics namespace) and the
  # ntfy mobile/web app subscribes over the tailnet.
  applications.ntfy = {
    namespace = "ntfy";
    createNamespace = true;

    # Scraped by vmagent (see docs/agents/adding-a-service.md)
    yamls = [
      ''
        apiVersion: operator.victoriametrics.com/v1beta1
        kind: VMServiceScrape
        metadata:
          name: ntfy
          namespace: ntfy
        spec:
          selector:
            matchLabels:
              app: ntfy
          endpoints:
            - port: metrics
      ''
    ];

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
              ports.metrics.containerPort = 9090;
              env = {
                NTFY_BASE_URL.value = "http://ntfy.tail84b6c.ts.net";
                NTFY_LISTEN_HTTP.value = ":8080"; # unprivileged port, non-root user
                NTFY_BEHIND_PROXY.value = "true";
                # Prometheus metrics on a separate, cluster-internal port
                NTFY_ENABLE_METRICS.value = "true";
                NTFY_METRICS_LISTEN_HTTP.value = ":9090";
                # Forward poll requests through ntfy.sh -> APNs so the iOS
                # app gets instant notifications (iOS can't hold a background
                # connection to a self-hosted server).
                NTFY_UPSTREAM_BASE_URL.value = "https://ntfy.sh";
                NTFY_CACHE_FILE.value = "/var/cache/ntfy/cache.db";
                # Needed for attachments; Apprise turns large changedetection
                # notifications (>8 KB, e.g. big diffs) into .txt attachments.
                NTFY_ATTACHMENT_CACHE_DIR.value = "/var/cache/ntfy/attachments";
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

      # Cluster-internal endpoint used by alertmanager-ntfy and vmagent
      services.ntfy = {
        metadata.labels.app = "ntfy";
        spec = {
          selector.app = "ntfy";
          ports.http = {
            port = 80;
            targetPort = 8080;
          };
          ports.metrics = {
            port = 9090;
            targetPort = 9090;
          };
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
