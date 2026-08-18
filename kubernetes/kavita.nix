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
              image = "docker.io/jvmilazz0/kavita:0.9.0@sha256:36aab0c578d488f8b10bd33910953b50965aff9ac6adc476ef4692c38c60427e";
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
            volumes = {
              config.persistentVolumeClaim.claimName = "kavita-config";
              library.persistentVolumeClaim.claimName = "kavita-library";
            };
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
