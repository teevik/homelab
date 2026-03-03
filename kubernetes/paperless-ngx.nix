{ ... }:
let
  dbPassword = "paperless";

  # renovate: datasource=docker depName=ghcr.io/paperless-ngx/paperless-ngx
  paperlessImage = "ghcr.io/paperless-ngx/paperless-ngx:2.20.9@sha256:1d99ede700ffdf7aa44899b5fee29c8c279f175769b6cb295e91e9f15772728e";

  paperlessEnv = {
    PAPERLESS_REDIS.value = "redis://paperless-redis:6379";
    PAPERLESS_DBHOST.value = "paperless-db";
    PAPERLESS_DBPORT.value = "5432";
    PAPERLESS_DBUSER.value = "paperless";
    PAPERLESS_DBPASS.value = dbPassword;
    PAPERLESS_DBNAME.value = "paperless";
    PAPERLESS_TIKA_ENABLED.value = "1";
    PAPERLESS_TIKA_GOTENBERG_ENDPOINT.value = "http://paperless-gotenberg:3000";
    PAPERLESS_TIKA_ENDPOINT.value = "http://paperless-tika:9998";
    PAPERLESS_SECRET_KEY.valueFrom.secretKeyRef = {
      name = "paperless-secrets";
      key = "PAPERLESS_SECRET_KEY";
    };
    PAPERLESS_TIME_ZONE.value = "Europe/Oslo";
    PAPERLESS_OCR_LANGUAGES.value = "nor";
    PAPERLESS_OCR_LANGUAGE.value = "eng+nor";
    PAPERLESS_URL.value = "http://paperless";
    PAPERLESS_ADMIN_USER.value = "admin";
    PAPERLESS_ADMIN_PASSWORD.value = "admin";
  };
in
{
  applications.paperless-ngx = {
    namespace = "paperless-ngx";
    createNamespace = true;

    resources = {
      # --- Persistent Volume Claims ---

      persistentVolumeClaims.paperless-db-data.spec = {
        storageClassName = "longhorn";
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = "10Gi";
      };

      persistentVolumeClaims.paperless-db-data.metadata.labels = {
        "recurring-job.longhorn.io/source" = "enabled";
        "recurring-job-group.longhorn.io/backup" = "enabled";
        "recurring-job-group.longhorn.io/snapshot" = "enabled";
      };

      persistentVolumeClaims.paperless-redis-data.spec = {
        storageClassName = "longhorn";
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = "1Gi";
      };

      persistentVolumeClaims.paperless-data.spec = {
        storageClassName = "longhorn";
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = "5Gi";
      };

      persistentVolumeClaims.paperless-data.metadata.labels = {
        "recurring-job.longhorn.io/source" = "enabled";
        "recurring-job-group.longhorn.io/backup" = "enabled";
        "recurring-job-group.longhorn.io/snapshot" = "enabled";
      };

      persistentVolumeClaims.paperless-media.spec = {
        storageClassName = "longhorn";
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = "20Gi";
      };

      persistentVolumeClaims.paperless-media.metadata.labels = {
        "recurring-job.longhorn.io/source" = "enabled";
        "recurring-job-group.longhorn.io/backup" = "enabled";
        "recurring-job-group.longhorn.io/snapshot" = "enabled";
      };

      persistentVolumeClaims.paperless-consume.spec = {
        storageClassName = "longhorn";
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = "1Gi";
      };

      persistentVolumeClaims.paperless-export.spec = {
        storageClassName = "longhorn";
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = "5Gi";
      };

      # --- PostgreSQL ---

      deployments.paperless-db.spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels.app = "paperless-db";
        template = {
          metadata.labels.app = "paperless-db";
          spec = {
            containers.postgres = {
              # renovate: datasource=docker depName=postgres
              image = "postgres:17-alpine@sha256:6f30057d31f5861b66f3545d4821f987aacf1dd920765f0acadea0c58ff975b1";
              ports.postgres.containerPort = 5432;
              env = {
                POSTGRES_USER.value = "paperless";
                POSTGRES_PASSWORD.value = dbPassword;
                POSTGRES_DB.value = "paperless";
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
            volumes.data.persistentVolumeClaim.claimName = "paperless-db-data";
          };
        };
      };

      services.paperless-db.spec = {
        selector.app = "paperless-db";
        ports.postgres = {
          port = 5432;
          targetPort = 5432;
        };
      };

      # --- Redis ---

      deployments.paperless-redis.spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels.app = "paperless-redis";
        template = {
          metadata.labels.app = "paperless-redis";
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
            volumes.data.persistentVolumeClaim.claimName = "paperless-redis-data";
          };
        };
      };

      services.paperless-redis.spec = {
        selector.app = "paperless-redis";
        ports.redis = {
          port = 6379;
          targetPort = 6379;
        };
      };

      # --- Gotenberg (Office document to PDF conversion) ---

      deployments.paperless-gotenberg.spec = {
        replicas = 1;
        selector.matchLabels.app = "paperless-gotenberg";
        template = {
          metadata.labels.app = "paperless-gotenberg";
          spec = {
            containers.gotenberg = {
              # renovate: datasource=docker depName=gotenberg/gotenberg
              image = "gotenberg/gotenberg:8.27@sha256:d71ab8c13b6bd47c7bc81195082005dfb17eaa75e8b1fadd347a64ee66ed98d5";
              command = [
                "gotenberg"
                "--chromium-disable-javascript=true"
                "--chromium-allow-list=file:///tmp/.*"
              ];
              ports.http.containerPort = 3000;
              resources = {
                requests = {
                  memory = "256Mi";
                  cpu = "100m";
                };
                limits.memory = "1Gi";
              };
            };
          };
        };
      };

      services.paperless-gotenberg.spec = {
        selector.app = "paperless-gotenberg";
        ports.http = {
          port = 3000;
          targetPort = 3000;
        };
      };

      # --- Apache Tika (content extraction) ---

      deployments.paperless-tika.spec = {
        replicas = 1;
        selector.matchLabels.app = "paperless-tika";
        template = {
          metadata.labels.app = "paperless-tika";
          spec = {
            containers.tika = {
              # renovate: datasource=docker depName=apache/tika
              image = "apache/tika:3.2.3.0@sha256:c0154cb95587cde64be74f35ada1a2bd7892219f3f0ac3c9dc6cab34046b3573";
              ports.http.containerPort = 9998;
              resources = {
                requests = {
                  memory = "256Mi";
                  cpu = "100m";
                };
                limits.memory = "1Gi";
              };
            };
          };
        };
      };

      services.paperless-tika.spec = {
        selector.app = "paperless-tika";
        ports.http = {
          port = 9998;
          targetPort = 9998;
        };
      };

      # --- Paperless-ngx webserver ---

      deployments.paperless.spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels.app = "paperless";
        template = {
          metadata.labels.app = "paperless";
          spec = {
            containers.paperless = {
              image = paperlessImage;
              ports.http.containerPort = 8000;
              env = paperlessEnv;
              volumeMounts = {
                "/usr/src/paperless/data" = {
                  name = "data";
                };
                "/usr/src/paperless/media" = {
                  name = "media";
                };
                "/usr/src/paperless/consume" = {
                  name = "consume";
                };
                "/usr/src/paperless/export" = {
                  name = "export";
                };
              };
              resources = {
                requests = {
                  memory = "512Mi";
                  cpu = "200m";
                };
                limits.memory = "4Gi";
              };
            };
            volumes = {
              data.persistentVolumeClaim.claimName = "paperless-data";
              media.persistentVolumeClaim.claimName = "paperless-media";
              consume.persistentVolumeClaim.claimName = "paperless-consume";
              export.persistentVolumeClaim.claimName = "paperless-export";
            };
          };
        };
      };

      services.paperless.spec = {
        selector.app = "paperless";
        ports.http = {
          port = 8000;
          targetPort = 8000;
        };
      };

      # --- Tailscale ingress ---

      services.paperless-tailscale = {
        metadata.annotations = {
          "tailscale.com/proxy-group" = "ingress";
          "tailscale.com/hostname" = "paperless";
        };
        spec = {
          type = "LoadBalancer";
          loadBalancerClass = "tailscale";
          selector.app = "paperless";
          ports.http = {
            port = 80;
            targetPort = 8000;
          };
        };
      };
    };
  };
}
