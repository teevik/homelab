{ charts, ... }:
{
  applications.immich = {
    namespace = "immich";
    createNamespace = true;

    helm.releases.immich = {
      chart = charts.immich.immich;

      values = {
        # Pin Immich image tag to stay current when chart lags app releases
        # renovate: datasource=docker depName=ghcr.io/immich-app/immich-server
        controllers.main.containers.main.image.tag =
          "v3.1.0@sha256:b434cb9287eea1471c9974845914d4dd328c9c2d652e446ed4930f99944f0ceb";

        # Database connection (shared across components); the password comes
        # from the sops-provisioned immich-secrets (modules/nixos/kubernetes.nix)
        controllers.main.containers.main.env = {
          DB_HOSTNAME = "immich-postgresql";
          DB_USERNAME = "immich";
          DB_PASSWORD.valueFrom.secretKeyRef = {
            name = "immich-secrets";
            key = "DB_PASSWORD";
          };
          DB_DATABASE_NAME = "immich";
        };

        # Enable Valkey (Redis) with persistent storage
        valkey = {
          enabled = true;
          # renovate: datasource=docker depName=docker.io/valkey/valkey
          controllers.main.containers.main.image.tag =
            "9.1.1-alpine@sha256:de31910896150d5e754a07d57d227cfdde4e258ddd0d1aa4607f2d2f95843715";
          persistence.data = {
            enabled = true;
            type = "persistentVolumeClaim";
            size = "1Gi";
            accessMode = "ReadWriteOnce";
          };
        };

        # Machine learning with ROCm GPU acceleration (RX 6650M XT / gfx1032)
        machine-learning = {
          enabled = true;

          # Use ROCm image variant for AMD GPU acceleration
          controllers.main = {
            containers.main = {
              # renovate: datasource=docker depName=ghcr.io/immich-app/immich-machine-learning
              image.tag = "v3.1.0-rocm@sha256:dd0984a9d61172d45ab4cc3508e3e9861d5262b50ede18200bb5fa56b3addb49";
              env.HSA_OVERRIDE_GFX_VERSION = "10.3.0";
              # MIGraphX model compilation blocks /ping for several minutes on gfx1032.
              probes.liveness.spec.failureThreshold = 60;
              # GPU access comes from the AMD device plugin
              # (kubernetes/amd-device-plugin.nix) instead of a privileged
              # container with raw hostPath device mounts.
              resources.limits."amd.com/gpu" = 1;
              securityContext = {
                allowPrivilegeEscalation = false;
                capabilities.drop = [ "ALL" ];
                seccompProfile.type = "RuntimeDefault";
              };
            };
            # /dev/kfd and /dev/dri device nodes are group-owned on the host
            pod.securityContext.supplementalGroups = [
              26
              303
            ]; # video, render
          };

          persistence.cache = {
            enabled = true;
            type = "persistentVolumeClaim";
            size = "10Gi";
            accessMode = "ReadWriteOnce";
          };
        };

        # Photo library storage using a pre-created PVC
        immich.persistence.library.existingClaim = "immich-library";

        # Prometheus metrics. Not via `immich.metrics.enabled`: that also
        # renders a ServiceMonitor (CRD not installed) and its hard-coded
        # `true` wins the chart's value merge, so wire the pieces directly.
        # Immich serves API metrics on 8081 and job/microservice metrics on
        # 8082 once telemetry is on.
        server = {
          controllers.main.containers.main.env.IMMICH_TELEMETRY_INCLUDE = "all";
          service.main.ports = {
            metrics-api = {
              enabled = true;
              port = 8081;
              targetPort = 8081;
              protocol = "HTTP";
            };
            metrics-ms = {
              enabled = true;
              port = 8082;
              targetPort = 8082;
              protocol = "HTTP";
            };
          };
        };
      };
    };

    # Scraped by vmagent (see docs/agents/adding-a-service.md)
    yamls = [
      ''
        apiVersion: operator.victoriametrics.com/v1beta1
        kind: VMServiceScrape
        metadata:
          name: immich-server
          namespace: immich
        spec:
          selector:
            matchLabels:
              app.kubernetes.io/service: immich-server
          endpoints:
            - port: metrics-api
            - port: metrics-ms
      ''
    ];

    resources = {
      # PVC for the photo/video library
      persistentVolumeClaims.immich-library = {
        metadata.labels = {
          "recurring-job.longhorn.io/source" = "enabled";
          "recurring-job-group.longhorn.io/snapshot" = "enabled";
          "recurring-job-group.longhorn.io/backup" = "enabled";
        };
        spec = {
          storageClassName = "longhorn";
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "50Gi";
        };
      };

      # PVC for PostgreSQL data
      persistentVolumeClaims.immich-postgresql-data = {
        metadata.labels = {
          "recurring-job.longhorn.io/source" = "enabled";
          "recurring-job-group.longhorn.io/snapshot" = "enabled";
          "recurring-job-group.longhorn.io/backup" = "enabled";
        };
        spec = {
          storageClassName = "longhorn";
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "10Gi";
        };
      };

      # PostgreSQL with VectorChord extension (required by Immich)
      deployments.immich-postgresql.spec = {
        replicas = 1;
        selector.matchLabels.app = "immich-postgresql";
        template = {
          metadata.labels.app = "immich-postgresql";
          spec = {
            containers.postgresql = {
              image = "docker.io/tensorchord/vchord-postgres:pg16-v1.1.1@sha256:d12a579a95c5ea7bb0294181eddf091ab790eebd37f40c49b6de221e2fb756ed";
              args = [
                "postgres"
                "-c"
                "shared_preload_libraries=vchord.so"
              ];
              ports.postgresql.containerPort = 5432;
              env = {
                POSTGRES_USER.value = "immich";
                POSTGRES_PASSWORD.valueFrom.secretKeyRef = {
                  name = "immich-secrets";
                  key = "DB_PASSWORD";
                };
                POSTGRES_DB.value = "immich";
              };
              volumeMounts."/var/lib/postgresql/data" = {
                name = "data";
                subPath = "pgdata";
              };
            };
            volumes.data.persistentVolumeClaim.claimName = "immich-postgresql-data";
          };
        };
      };

      # PostgreSQL ClusterIP service
      services.immich-postgresql.spec = {
        selector.app = "immich-postgresql";
        ports.postgresql = {
          port = 5432;
          targetPort = 5432;
        };
      };

      # Share-link gateway: only serves Immich's public share pages and the
      # assets they reference, so the Funnel never exposes the Immich login,
      # API, or admin surface to the internet.
      deployments.immich-public-proxy.spec = {
        replicas = 1;
        selector.matchLabels.app = "immich-public-proxy";
        template = {
          metadata.labels.app = "immich-public-proxy";
          spec = {
            automountServiceAccountToken = false;
            containers.proxy = {
              # renovate: datasource=docker depName=ghcr.io/alangrainger/immich-public-proxy
              image = "ghcr.io/alangrainger/immich-public-proxy:3.2.1@sha256:7ca34cc3efa618a11674db00e1d943e4611cb2e14d1f6d73343757db700a6e3c";
              ports.http.containerPort = 3000;
              env.IMMICH_URL.value = "http://immich-server:2283";
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
          };
        };
      };

      services.immich-public-proxy.spec = {
        selector.app = "immich-public-proxy";
        ports.http = {
          port = 3000;
          targetPort = 3000;
        };
      };

      # Public HTTPS endpoint for Immich share links via Tailscale Funnel,
      # routed through immich-public-proxy (share pages only, never the app).
      ingresses.immich-funnel = {
        metadata.annotations = {
          "tailscale.com/funnel" = "true";
        };
        spec = {
          ingressClassName = "tailscale";
          defaultBackend.service = {
            name = "immich-public-proxy";
            port.number = 3000;
          };
          tls = [
            {
              hosts = [ "immich-share" ];
            }
          ];
        };
      };

      # Tailscale LoadBalancer to expose Immich externally
      services.immich-tailscale = {
        metadata.annotations = {
          "tailscale.com/proxy-group" = "ingress";
          "tailscale.com/hostname" = "immich";
        };
        spec = {
          type = "LoadBalancer";
          loadBalancerClass = "tailscale";
          selector = {
            "app.kubernetes.io/instance" = "immich";
            "app.kubernetes.io/name" = "server";
          };
          ports.http = {
            port = 80;
            targetPort = 2283;
          };
        };
      };
    };
  };
}
