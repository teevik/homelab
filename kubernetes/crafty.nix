{ ... }:
let
  # renovate: datasource=docker depName=registry.gitlab.com/crafty-controller/crafty-4
  craftyImage = "registry.gitlab.com/crafty-controller/crafty-4:4.10.4@sha256:d2f61fcabb4756a63bc8538fb4f5e35ffddca3f1916a733c95a31c705c697742";

  # renovate: datasource=docker depName=favonia/cloudflare-ddns
  cloudflareDdnsImage = "favonia/cloudflare-ddns:1.16.2@sha256:bc53b40b13c8b2a84e9b93c21f65fcd7d574b741014fb93912eb9efd93015aa2";

  backupLabels = {
    "recurring-job.longhorn.io/source" = "enabled";
    "recurring-job-group.longhorn.io/backup" = "enabled";
    "recurring-job-group.longhorn.io/snapshot" = "enabled";
  };

  mkPvc = storage: {
    spec = {
      storageClassName = "longhorn";
      accessModes = [ "ReadWriteOnce" ];
      resources.requests.storage = storage;
    };
  };

  mkBackedUpPvc = storage: (mkPvc storage) // { metadata.labels = backupLabels; };
in
{
  applications.crafty = {
    namespace = "crafty";
    createNamespace = true;

    resources = {
      persistentVolumeClaims.crafty-config = mkPvc "2Gi";
      persistentVolumeClaims.crafty-servers = mkBackedUpPvc "80Gi";
      persistentVolumeClaims.crafty-backups = mkBackedUpPvc "50Gi";
      persistentVolumeClaims.crafty-logs = mkPvc "5Gi";
      persistentVolumeClaims.crafty-import = mkPvc "10Gi";

      deployments.crafty.spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels.app = "crafty";
        template = {
          metadata.labels.app = "crafty";
          spec = {
            securityContext = {
              fsGroup = 0;
              fsGroupChangePolicy = "OnRootMismatch";
            };
            containers.crafty = {
              image = craftyImage;
              ports = {
                http.containerPort = 8000;
                https.containerPort = 8443;
                minecraft.containerPort = 25565;
              };
              volumeMounts = {
                "/crafty/app/config" = {
                  name = "config";
                };
                "/crafty/servers" = {
                  name = "servers";
                };
                "/crafty/backups" = {
                  name = "backups";
                };
                "/crafty/logs" = {
                  name = "logs";
                };
                "/crafty/import" = {
                  name = "import";
                };
              };
              resources = {
                requests = {
                  cpu = "2";
                  memory = "10Gi";
                };
                limits.memory = "14Gi";
              };
            };
            volumes = {
              config.persistentVolumeClaim.claimName = "crafty-config";
              servers.persistentVolumeClaim.claimName = "crafty-servers";
              backups.persistentVolumeClaim.claimName = "crafty-backups";
              logs.persistentVolumeClaim.claimName = "crafty-logs";
              import.persistentVolumeClaim.claimName = "crafty-import";
            };
          };
        };
      };

      services.crafty.spec = {
        selector.app = "crafty";
        ports = {
          http = {
            port = 8000;
            targetPort = 8000;
            protocol = "TCP";
          };
          https = {
            port = 8443;
            targetPort = 8443;
            protocol = "TCP";
          };
          minecraft = {
            port = 25565;
            targetPort = 25565;
            protocol = "TCP";
          };
        };
      };

      services.crafty-minecraft-public-nodeport.spec = {
        type = "NodePort";
        selector.app = "crafty";
        ports.minecraft = {
          port = 25565;
          targetPort = 25565;
          nodePort = 30565;
          protocol = "TCP";
        };
      };

      services.crafty-tailscale = {
        metadata.annotations = {
          "tailscale.com/proxy-group" = "ingress";
          "tailscale.com/hostname" = "crafty";
        };
        spec = {
          type = "LoadBalancer";
          loadBalancerClass = "tailscale";
          selector.app = "crafty";
          ports = {
            http = {
              port = 80;
              targetPort = 8000;
              protocol = "TCP";
            };
            https = {
              port = 443;
              targetPort = 8443;
              protocol = "TCP";
            };
          };
        };
      };

      deployments.crafty-cloudflare-ddns.spec = {
        replicas = 1;
        selector.matchLabels.app = "crafty-cloudflare-ddns";
        template = {
          metadata.labels.app = "crafty-cloudflare-ddns";
          spec.containers.ddns = {
            image = cloudflareDdnsImage;
            env = {
              CLOUDFLARE_API_TOKEN.valueFrom.secretKeyRef = {
                name = "crafty-secrets";
                key = "CLOUDFLARE_API_TOKEN";
              };
              IP4_DOMAINS.value = "gtnh.teevik.no";
              IP6_PROVIDER.value = "none";
              PROXIED.value = "false";
            };
            resources = {
              requests = {
                cpu = "10m";
                memory = "32Mi";
              };
              limits.memory = "128Mi";
            };
          };
        };
      };
    };
  };
}
