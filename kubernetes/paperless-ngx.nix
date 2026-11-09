{ ... }:
let
  paperlessEnv = {
    PAPERLESS_REDIS.value = "redis://paperless-redis:6379";
    PAPERLESS_DBHOST.value = "paperless-db";
    PAPERLESS_DBPORT.value = "5432";
    PAPERLESS_DBUSER.value = "paperless";
    PAPERLESS_DBPASS.valueFrom.secretKeyRef = {
      name = "paperless-secrets";
      key = "PAPERLESS_DBPASS";
    };
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
    PAPERLESS_ADMIN_PASSWORD.valueFrom.secretKeyRef = {
      name = "paperless-secrets";
      key = "PAPERLESS_ADMIN_PASSWORD";
    };
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
              image = "postgres:17-alpine@sha256:3540c0362c809df084ffac0ae69fe794515f9de92692f02178bcdce0ef0302ac";
              ports.postgres.containerPort = 5432;
              env = {
                POSTGRES_USER.value = "paperless";
                POSTGRES_PASSWORD.valueFrom.secretKeyRef = {
                  name = "paperless-secrets";
                  key = "PAPERLESS_DBPASS";
                };
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
              image = "redis:8.10-alpine@sha256:71885d8cc6e42f2bc0aa2eb853bfc4be200b5108a46ac50e117ae1df0531fb80";
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
              image = "gotenberg/gotenberg:8.40@sha256:53073e798c8ef39ea2187e44cb67bab77894ea2509100b94c4fe3b461f7b2996";
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
              image = "apache/tika:3.3.3.0@sha256:326b238b37904c94ff61fed87afe0af72e6a29fa715933b10af97b7d56f1d4cb";
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
              image = "ghcr.io/paperless-ngx/paperless-ngx:3.4.2@sha256:d704e84f88300eb6ab001ab15720a2330ff99169cf9f94d6b8fcc44b63a84c84";
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

      services.paperless-web.spec = {
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
