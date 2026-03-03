{ ... }:
let
  # renovate: datasource=docker depName=freikin/dawarich
  dawarichImage = "freikin/dawarich:1.3.1@sha256:a3b000a5a85b2997ceb7117cb078f7b8851e5f958c87d5286bf098a6e1e26ea0";

  commonEnv = {
    RAILS_ENV.value = "production";
    REDIS_URL.value = "redis://dawarich-redis:6379";
    DATABASE_HOST.value = "dawarich-db";
    DATABASE_PORT.value = "5432";
    DATABASE_USERNAME.value = "postgres";
    DATABASE_PASSWORD.valueFrom.secretKeyRef = {
      name = "dawarich-secrets";
      key = "DATABASE_PASSWORD";
    };
    DATABASE_NAME.value = "dawarich_production";
    APPLICATION_HOSTS.value = "dawarich,localhost,::1,127.0.0.1";
    APPLICATION_PROTOCOL.value = "http";
    TIME_ZONE.value = "Europe/Oslo";
    SECRET_KEY_BASE.valueFrom.secretKeyRef = {
      name = "dawarich-secrets";
      key = "SECRET_KEY_BASE";
    };
    SELF_HOSTED.value = "true";
    STORE_GEODATA.value = "true";
    RAILS_LOG_TO_STDOUT.value = "true";
    PROMETHEUS_EXPORTER_ENABLED.value = "false";
  };

  commonVolumeMounts = {
    "/var/app/public" = {
      name = "public";
    };
    "/var/app/tmp/imports/watched" = {
      name = "watched";
    };
    "/var/app/storage" = {
      name = "storage";
    };
  };

  commonVolumes = {
    public.persistentVolumeClaim.claimName = "dawarich-public";
    watched.persistentVolumeClaim.claimName = "dawarich-watched";
    storage.persistentVolumeClaim.claimName = "dawarich-storage";
  };
in
{
  applications.dawarich = {
    namespace = "dawarich";
    createNamespace = true;

    resources = {
      # --- Persistent Volume Claims ---

      persistentVolumeClaims.dawarich-db-data.spec = {
        storageClassName = "longhorn";
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = "10Gi";
      };

      persistentVolumeClaims.dawarich-db-data.metadata.labels = {
        "recurring-job.longhorn.io/source" = "enabled";
        "recurring-job-group.longhorn.io/backup" = "enabled";
        "recurring-job-group.longhorn.io/snapshot" = "enabled";
      };

      persistentVolumeClaims.dawarich-public.spec = {
        storageClassName = "longhorn";
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = "1Gi";
      };

      persistentVolumeClaims.dawarich-watched.spec = {
        storageClassName = "longhorn";
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = "1Gi";
      };

      persistentVolumeClaims.dawarich-storage.spec = {
        storageClassName = "longhorn";
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = "5Gi";
      };

      persistentVolumeClaims.dawarich-storage.metadata.labels = {
        "recurring-job.longhorn.io/source" = "enabled";
        "recurring-job-group.longhorn.io/backup" = "enabled";
        "recurring-job-group.longhorn.io/snapshot" = "enabled";
      };

      persistentVolumeClaims.dawarich-redis-data.spec = {
        storageClassName = "longhorn";
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = "1Gi";
      };

      # --- PostgreSQL (PostGIS) ---

      deployments.dawarich-db.spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels.app = "dawarich-db";
        template = {
          metadata.labels.app = "dawarich-db";
          spec = {
            containers.postgis = {
              # renovate: datasource=docker depName=postgis/postgis
              image = "postgis/postgis:17-3.5-alpine@sha256:c75c8a8d4c0271f6bf788078e0ae8fa860a1c1a6904d2556c8b2a1b93753cd11";
              ports.postgres.containerPort = 5432;
              env = {
                POSTGRES_USER.value = "postgres";
                POSTGRES_PASSWORD.valueFrom.secretKeyRef = {
                  name = "dawarich-secrets";
                  key = "DATABASE_PASSWORD";
                };
                POSTGRES_DB.value = "dawarich_production";
              };
              volumeMounts."/var/lib/postgresql/data" = {
                name = "data";
                subPath = "pgdata";
              };
              resources = {
                requests = {
                  memory = "256Mi";
                  cpu = "100m";
                };
                limits.memory = "1Gi";
              };
            };
            volumes.data.persistentVolumeClaim.claimName = "dawarich-db-data";
          };
        };
      };

      services.dawarich-db.spec = {
        selector.app = "dawarich-db";
        ports.postgres = {
          port = 5432;
          targetPort = 5432;
        };
      };

      # --- Redis ---

      deployments.dawarich-redis.spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels.app = "dawarich-redis";
        template = {
          metadata.labels.app = "dawarich-redis";
          spec = {
            containers.redis = {
              # renovate: datasource=docker depName=redis
              image = "redis:7.4-alpine@sha256:8b81dd37ff027bec4e516d41acfbe9fe2460070dc6d4a4570a2ac5b9d59df065";
              command = [ "redis-server" ];
              ports.redis.containerPort = 6379;
              volumeMounts."/data" = {
                name = "data";
              };
              resources = {
                requests = {
                  memory = "64Mi";
                  cpu = "50m";
                };
                limits.memory = "256Mi";
              };
            };
            volumes.data.persistentVolumeClaim.claimName = "dawarich-redis-data";
          };
        };
      };

      services.dawarich-redis.spec = {
        selector.app = "dawarich-redis";
        ports.redis = {
          port = 6379;
          targetPort = 6379;
        };
      };

      # --- Dawarich App (Rails web server) ---

      deployments.dawarich-app.spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels.app = "dawarich-app";
        template = {
          metadata.labels.app = "dawarich-app";
          spec = {
            containers.dawarich = {
              image = dawarichImage;
              command = [
                "web-entrypoint.sh"
                "bin/rails"
                "server"
                "-p"
                "3000"
                "-b"
                "::"
              ];
              ports.http.containerPort = 3000;
              env = commonEnv;
              volumeMounts = commonVolumeMounts;
              resources = {
                requests = {
                  memory = "512Mi";
                  cpu = "200m";
                };
                limits.memory = "4Gi";
              };
            };
            volumes = commonVolumes;
          };
        };
      };

      services.dawarich-app.spec = {
        selector.app = "dawarich-app";
        ports.http = {
          port = 3000;
          targetPort = 3000;
        };
      };

      # --- Dawarich Sidekiq (background worker) ---

      deployments.dawarich-sidekiq.spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels.app = "dawarich-sidekiq";
        template = {
          metadata.labels.app = "dawarich-sidekiq";
          spec = {
            containers.sidekiq = {
              image = dawarichImage;
              command = [
                "sidekiq-entrypoint.sh"
                "sidekiq"
              ];
              env = commonEnv // {
                BACKGROUND_PROCESSING_CONCURRENCY.value = "10";
              };
              volumeMounts = commonVolumeMounts;
              resources = {
                requests = {
                  memory = "512Mi";
                  cpu = "200m";
                };
                limits.memory = "4Gi";
              };
            };
            volumes = commonVolumes;
          };
        };
      };

      # --- Tailscale ingress ---

      services.dawarich-tailscale = {
        metadata.annotations = {
          "tailscale.com/proxy-group" = "ingress";
          "tailscale.com/hostname" = "dawarich";
        };
        spec = {
          type = "LoadBalancer";
          loadBalancerClass = "tailscale";
          selector.app = "dawarich-app";
          ports.http = {
            port = 80;
            targetPort = 3000;
          };
        };
      };
    };
  };
}
