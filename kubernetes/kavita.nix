{ ... }:
let
  backupLabels = {
    "recurring-job.longhorn.io/source" = "enabled";
    "recurring-job-group.longhorn.io/backup" = "enabled";
    "recurring-job-group.longhorn.io/snapshot" = "enabled";
  };
in
{
  applications.kavita = {
    namespace = "kavita";
    createNamespace = true;

    resources = {
      # Kavita config: SQLite database, covers cache, bookmarks, backups
      persistentVolumeClaims.kavita-config = {
        metadata.labels = backupLabels;
        spec = {
          storageClassName = "longhorn";
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "10Gi";
        };
      };

      # Library: manga, comics, books
      persistentVolumeClaims.kavita-library = {
        metadata.labels = backupLabels;
        spec = {
          storageClassName = "longhorn";
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "100Gi";
        };
      };

      deployments.kavita.spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels.app = "kavita";
        template = {
          metadata.labels.app = "kavita";
          spec = {
            containers.kavita = {
              # renovate: datasource=docker depName=jvmilazz0/kavita
              image = "docker.io/jvmilazz0/kavita:0.9.1@sha256:454f2a77ac740b70c58cc7300a11122fc9ce7b7e2161ef5b0d1df8f81067cc85";
              ports.http.containerPort = 5000;
              env = {
                TZ.value = "Europe/Oslo";
              };
              volumeMounts = {
                "/kavita/config".name = "config";
                "/library".name = "library";
              };
              resources = {
                requests = {
                  memory = "256Mi";
                  cpu = "100m";
                };
                limits.memory = "2Gi";
              };
            };

            # Web file manager for uploading to the library (Kavita has no upload UI).
            # Runs as root so it can write to the root-owned library like Kavita does.
            containers.filebrowser = {
              # renovate: datasource=docker depName=filebrowser/filebrowser
              image = "docker.io/filebrowser/filebrowser:v2.63.23@sha256:a469ea076d4a1b4b1d86a41d130f2f536cd9da996a2b1fb39c0d7635f9d89b9a";
              ports.http.containerPort = 8080;
              env = {
                FB_PORT.value = "8080";
                FB_ADDRESS.value = "0.0.0.0";
                FB_ROOT.value = "/library";
                FB_DATABASE.value = "/database/filebrowser.db";
                FB_NOAUTH.value = "true";
              };
              securityContext = {
                runAsUser = 0;
                runAsGroup = 0;
              };
              volumeMounts = {
                "/library".name = "library";
                "/database" = {
                  name = "config";
                  subPath = "filebrowser";
                };
              };
              resources = {
                requests = {
                  memory = "32Mi";
                  cpu = "10m";
                };
                limits.memory = "256Mi";
              };
            };
            volumes = {
              config.persistentVolumeClaim.claimName = "kavita-config";
              library.persistentVolumeClaim.claimName = "kavita-library";
            };
          };
        };
      };

      services.kavita-files = {
        metadata.annotations = {
          "tailscale.com/proxy-group" = "ingress";
          "tailscale.com/hostname" = "kavita-files";
        };
        spec = {
          type = "LoadBalancer";
          loadBalancerClass = "tailscale";
          selector.app = "kavita";
          ports.http = {
            port = 80;
            targetPort = 8080;
          };
        };
      };

      services.kavita = {
        metadata.annotations = {
          "tailscale.com/proxy-group" = "ingress";
          "tailscale.com/hostname" = "kavita";
        };
        spec = {
          type = "LoadBalancer";
          loadBalancerClass = "tailscale";
          selector.app = "kavita";
          ports.http = {
            port = 80;
            targetPort = 5000;
          };
        };
      };
    };
  };
}
