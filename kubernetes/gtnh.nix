{ ... }:
let
  # renovate: datasource=docker depName=itzg/minecraft-server
  minecraftImage = "itzg/minecraft-server:java25@sha256:bb1cf73b342bdf6fa03b9d689b699bd1f8c6989f81ea07d520985eb2f18e6f30";

  # renovate: datasource=docker depName=itzg/rcon
  rconImage = "itzg/rcon:latest@sha256:c9521f333bf9eaedf2db0acd750e67be88eaaa9c5e9026385bd875dc18a49110";

  # renovate: datasource=docker depName=favonia/cloudflare-ddns
  cloudflareDdnsImage = "favonia/cloudflare-ddns:1.16.2@sha256:bc53b40b13c8b2a84e9b93c21f65fcd7d574b741014fb93912eb9efd93015aa2";

  gtnhVersion = "2.8.4";
in
{
  applications.gtnh = {
    namespace = "gtnh";
    createNamespace = true;

    resources = {
      persistentVolumeClaims.gtnh-data = {
        metadata.labels = {
          "recurring-job.longhorn.io/source" = "enabled";
          "recurring-job-group.longhorn.io/backup" = "enabled";
          "recurring-job-group.longhorn.io/snapshot" = "enabled";
        };
        spec = {
          storageClassName = "longhorn";
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "50Gi";
        };
      };

      persistentVolumeClaims.gtnh-rcon-data.spec = {
        storageClassName = "longhorn";
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = "1Gi";
      };

      deployments.gtnh.spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels.app = "gtnh";
        template = {
          metadata.labels.app = "gtnh";
          spec = {
            containers.gtnh = {
              image = minecraftImage;
              stdin = true;
              tty = true;
              ports = {
                minecraft.containerPort = 25565;
                rcon.containerPort = 25575;
              };
              env = {
                EULA.value = "TRUE";
                TYPE.value = "GTNH";
                GTNH_PACK_VERSION.value = gtnhVersion;
                MEMORY.value = "8G";
                ENABLE_RCON.value = "true";
                RCON_PORT.value = "25575";
                ENABLE_WHITELIST.value = "TRUE";
                RCON_PASSWORD.valueFrom.secretKeyRef = {
                  name = "gtnh-secrets";
                  key = "RCON_PASSWORD";
                };
              };
              volumeMounts."/data" = {
                name = "data";
              };
              resources = {
                requests = {
                  cpu = "2";
                  memory = "10Gi";
                };
                limits = {
                  memory = "12Gi";
                };
              };
            };
            volumes.data.persistentVolumeClaim.claimName = "gtnh-data";
          };
        };
      };

      services.gtnh.spec = {
        selector.app = "gtnh";
        ports = {
          minecraft = {
            port = 25565;
            targetPort = 25565;
            protocol = "TCP";
          };
          rcon = {
            port = 25575;
            targetPort = 25575;
            protocol = "TCP";
          };
        };
      };

      services.gtnh-public-nodeport.spec = {
        type = "NodePort";
        selector.app = "gtnh";
        ports.minecraft = {
          port = 25565;
          targetPort = 25565;
          nodePort = 30565;
          protocol = "TCP";
        };
      };

      services.gtnh-tailscale = {
        metadata.annotations = {
          "tailscale.com/proxy-group" = "ingress";
          "tailscale.com/hostname" = "gtnh";
        };
        spec = {
          type = "LoadBalancer";
          loadBalancerClass = "tailscale";
          selector.app = "gtnh";
          ports.minecraft = {
            port = 25565;
            targetPort = 25565;
            protocol = "TCP";
          };
        };
      };

      deployments.gtnh-rcon.spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels.app = "gtnh-rcon";
        template = {
          metadata.labels.app = "gtnh-rcon";
          spec = {
            containers.rcon = {
              image = rconImage;
              ports = {
                http.containerPort = 4326;
                websocket.containerPort = 4327;
              };
              env = {
                RWA_USERNAME.value = "admin";
                RWA_ADMIN.value = "TRUE";
                RWA_GAME.value = "minecraft";
                RWA_SERVER_NAME.value = "gtnh";
                RWA_RCON_HOST.value = "gtnh";
                RWA_RCON_PORT.value = "25575";
                RWA_WEBSOCKET_URL.value = "ws://gtnh-rcon:4327";
                RWA_WEBSOCKET_URL_SSL.value = "wss://gtnh-rcon:4327";
                RWA_PASSWORD.valueFrom.secretKeyRef = {
                  name = "gtnh-secrets";
                  key = "RCON_WEB_PASSWORD";
                };
                RWA_RCON_PASSWORD.valueFrom.secretKeyRef = {
                  name = "gtnh-secrets";
                  key = "RCON_PASSWORD";
                };
              };
              volumeMounts."/opt/rcon-web-admin/db" = {
                name = "data";
              };
              resources = {
                requests = {
                  cpu = "50m";
                  memory = "128Mi";
                };
                limits.memory = "512Mi";
              };
            };
            volumes.data.persistentVolumeClaim.claimName = "gtnh-rcon-data";
          };
        };
      };

      services.gtnh-rcon.spec = {
        selector.app = "gtnh-rcon";
        ports = {
          http = {
            port = 4326;
            targetPort = 4326;
          };
          websocket = {
            port = 4327;
            targetPort = 4327;
          };
        };
      };

      services.gtnh-rcon-tailscale = {
        metadata.annotations = {
          "tailscale.com/proxy-group" = "ingress";
          "tailscale.com/hostname" = "gtnh-rcon";
        };
        spec = {
          type = "LoadBalancer";
          loadBalancerClass = "tailscale";
          selector.app = "gtnh-rcon";
          ports = {
            http = {
              port = 80;
              targetPort = 4326;
            };
            websocket = {
              port = 4327;
              targetPort = 4327;
            };
          };
        };
      };

      deployments.gtnh-cloudflare-ddns.spec = {
        replicas = 1;
        selector.matchLabels.app = "gtnh-cloudflare-ddns";
        template = {
          metadata.labels.app = "gtnh-cloudflare-ddns";
          spec.containers.ddns = {
            image = cloudflareDdnsImage;
            env = {
              CLOUDFLARE_API_TOKEN.valueFrom.secretKeyRef = {
                name = "gtnh-secrets";
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
