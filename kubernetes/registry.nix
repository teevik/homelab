{ ... }:
let
  # Tailnet hostname; the Ingress below terminates TLS with a ts.net cert.
  externalUrl = "https://registry.tail84b6c.ts.net";

  zotConfig = {
    distSpecVersion = "1.1.1";
    storage = {
      rootDirectory = "/var/lib/zot";
      dedupe = true;
      gc = true;
      gcDelay = "1h";
      gcInterval = "24h";
      # Keep every repo bounded: the 10 most recently pushed tags plus
      # anything tagged "latest"; untagged manifests are collected.
      retention = {
        dryRun = false;
        delay = "24h";
        policies = [
          {
            repositories = [ "**" ];
            deleteReferrers = false;
            deleteUntagged = true;
            keepTags = [
              { mostRecentlyPushedCount = 10; }
              { patterns = [ "latest" ]; }
            ];
          }
        ];
      };
    };
    http = {
      address = "0.0.0.0";
      port = "5000";
      inherit externalUrl;
      realm = "registry";
      # Accept Docker schema-2 manifests from plain `docker push`.
      compat = [ "docker2s2" ];
      auth.htpasswd.path = "/etc/zot/auth/htpasswd";
      # Anyone (the node's containerd, the dev machine) can pull; only the
      # "ci" user from the sops htpasswd can push. Metrics stay scrapeable.
      accessControl = {
        repositories."**" = {
          policies = [
            {
              users = [ "ci" ];
              actions = [
                "read"
                "create"
                "update"
                "delete"
              ];
            }
          ];
          anonymousPolicy = [ "read" ];
          defaultPolicy = [ ];
        };
        metrics.anonymousPolicy = [ "read" ];
        adminPolicy.users = [ "ci" ];
      };
    };
    log.level = "info";
    extensions = {
      ui.enable = true;
      # The UI needs the search (GraphQL) extension. CVE scanning is left
      # off: it pulls a Trivy database and burns memory for three images.
      search.enable = true;
      metrics = {
        enable = true;
        prometheus.path = "/metrics";
      };
      scrub = {
        enable = true;
        interval = "24h";
      };
    };
  };
in
{
  # Self-hosted OCI registry (zot) for images this cluster builds itself
  # (changedetection + CloakBrowser, KodeKamp). In-cluster BuildKit Jobs
  # (kubernetes/lib/build-job.nix) push as "ci" over the cluster network; the
  # node pulls anonymously over the tailnet. Tags are derived from the build
  # sources, so nothing here needs to be reachable by Renovate.
  applications.registry = {
    namespace = "registry";
    createNamespace = true;

    resources = {
      # Images are rebuildable, but a cluster rebuild would otherwise need
      # every workflow re-run before anything custom can start; back it up.
      persistentVolumeClaims.zot-data = {
        metadata.labels = {
          "recurring-job.longhorn.io/source" = "enabled";
          "recurring-job-group.longhorn.io/backup" = "enabled";
          "recurring-job-group.longhorn.io/snapshot" = "enabled";
        };
        spec = {
          storageClassName = "longhorn";
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "20Gi";
        };
      };

      configMaps.zot-config.data."config.json" = builtins.toJSON zotConfig;

      deployments.zot.spec = {
        replicas = 1;
        strategy.type = "Recreate"; # RWO PVC
        selector.matchLabels.app = "zot";
        template = {
          metadata.labels.app = "zot";
          spec = {
            automountServiceAccountToken = false;
            securityContext = {
              runAsUser = 1000;
              runAsGroup = 1000;
              fsGroup = 1000;
            };
            containers.zot = {
              image = "ghcr.io/project-zot/zot-linux-amd64:v2.1.20@sha256:95a837a0afacf5b7edc0c92493f04beee6891989b8d2fd50a00cf65a1e6d4fd5";
              ports.http.containerPort = 5000;
              volumeMounts = {
                "/var/lib/zot".name = "data";
                "/etc/zot".name = "config";
                "/etc/zot/auth".name = "htpasswd";
              };
              readinessProbe.httpGet = {
                path = "/v2/";
                port = "http";
              };
              livenessProbe = {
                httpGet = {
                  path = "/v2/";
                  port = "http";
                };
                initialDelaySeconds = 15;
              };
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
                limits.memory = "1Gi";
              };
            };
            volumes = {
              data.persistentVolumeClaim.claimName = "zot-data";
              config.configMap.name = "zot-config";
              # Created on the host from sops (modules/nixos/kubernetes.nix).
              htpasswd.secret.secretName = "zot-htpasswd";
            };
          };
        };
      };

      services.zot = {
        metadata.labels.app = "zot";
        spec = {
          selector.app = "zot";
          ports.http = {
            port = 5000;
            targetPort = 5000;
          };
        };
      };

      # HTTPS on the tailnet (registry.tail84b6c.ts.net). Docker clients
      # refuse plain-HTTP registries unless configured as insecure, so this
      # is an Ingress with a ts.net certificate rather than a LoadBalancer.
      ingresses.zot.spec = {
        ingressClassName = "tailscale";
        defaultBackend.service = {
          name = "zot";
          port.number = 5000;
        };
        tls = [ { hosts = [ "registry" ]; } ];
      };

      configMaps.registry-dashboard = {
        metadata.labels.grafana_dashboard = "1";
        metadata.annotations.grafana_folder = "Cluster";
        data."registry.json" = builtins.readFile ./dashboards/registry.json;
      };
    };

    yamls = [
      ''
        apiVersion: operator.victoriametrics.com/v1beta1
        kind: VMServiceScrape
        metadata:
          name: zot
          namespace: registry
        spec:
          selector:
            matchLabels:
              app: zot
          endpoints:
            - port: http
              path: /metrics
      ''
    ];
  };
}
