{ charts, ... }:
let
  dbPassword = "immich";
in
{
  applications.immich = {
    namespace = "immich";
    createNamespace = true;

    helm.releases.immich = {
      chart = charts.immich.immich;

      values = {
        # Pin Immich image tag to stay current when chart lags app releases
        # renovate: datasource=docker depName=ghcr.io/immich-app/immich-server
        controllers.main.containers.main.image.tag = "v3.1.0";

        # Database connection (shared across components)
        controllers.main.containers.main.env = {
          DB_HOSTNAME = "immich-postgresql";
          DB_USERNAME = "immich";
          DB_PASSWORD = dbPassword;
          DB_DATABASE_NAME = "immich";
        };

        # Enable Valkey (Redis) with persistent storage
        valkey = {
          enabled = true;
          # renovate: datasource=docker depName=docker.io/valkey/valkey
          controllers.main.containers.main.image.tag =
            "9.0.3-alpine@sha256:e1095c6c76ee982cb2d1e07edbb7fb2a53606630a1d810d5a47c9f646b708bf5";
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
              image.tag = "v3.1.0-rocm";
              env.HSA_OVERRIDE_GFX_VERSION = "10.3.0";
              securityContext = {
                privileged = true;
                allowPrivilegeEscalation = true;
                seccompProfile.type = "Unconfined";
                capabilities.add = [ "SYS_PTRACE" ];
              };
            };
            # Grant GPU device access to the pod
            pod.securityContext.supplementalGroups = [
              26
              303
            ]; # video, render
          };

          persistence = {
            cache = {
              enabled = true;
              type = "persistentVolumeClaim";
              size = "10Gi";
              accessMode = "ReadWriteOnce";
            };
            # AMD GPU device access
            dev-kfd = {
              enabled = true;
              type = "hostPath";
              hostPath = "/dev/kfd";
              hostPathType = "CharDevice";
              globalMounts = [ { path = "/dev/kfd"; } ];
            };
            dev-dri = {
              enabled = true;
              type = "hostPath";
              hostPath = "/dev/dri";
              hostPathType = "Directory";
              globalMounts = [ { path = "/dev/dri"; } ];
            };
          };
        };

        # Photo library storage using a pre-created PVC
        immich.persistence.library.existingClaim = "immich-library";
      };
    };

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

      # PostgreSQL with pgvecto.rs extension (required by Immich)
      deployments.immich-postgresql.spec = {
        replicas = 1;
        selector.matchLabels.app = "immich-postgresql";
        template = {
          metadata.labels.app = "immich-postgresql";
          spec = {
            containers.postgresql = {
              image = "docker.io/tensorchord/vchord-postgres:pg16-v1.1.0@sha256:6cd96c0fbe03aea7280d2ef21ea08508bf035c545e66a61e044be64e99b24fb7";
              args = [
                "postgres"
                "-c"
                "shared_preload_libraries=vchord.so"
              ];
              ports.postgresql.containerPort = 5432;
              env = {
                POSTGRES_USER.value = "immich";
                POSTGRES_PASSWORD.value = dbPassword;
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

      # Public HTTPS endpoint for Immich share links via Tailscale Funnel.
      # Immich's random /share/<token> URL remains the bearer secret.
      ingresses.immich-funnel = {
        metadata.annotations = {
          "tailscale.com/funnel" = "true";
        };
        spec = {
          ingressClassName = "tailscale";
          defaultBackend.service = {
            name = "immich-server";
            port.number = 2283;
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
