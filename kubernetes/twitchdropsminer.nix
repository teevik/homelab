{ ... }:
let
  backupLabels = {
    "recurring-job.longhorn.io/source" = "enabled";
    "recurring-job-group.longhorn.io/backup" = "enabled";
    "recurring-job-group.longhorn.io/snapshot" = "enabled";
  };
in
{
  applications.twitchdropsminer = {
    namespace = "twitchdropsminer";
    createNamespace = true;

    resources = {
      persistentVolumeClaims.twitchdropsminer-config = {
        metadata.labels = backupLabels;
        spec = {
          storageClassName = "longhorn";
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "1Gi";
        };
      };

      persistentVolumeClaims.twitchdropsminer-cache.spec = {
        storageClassName = "longhorn";
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = "1Gi";
      };

      deployments.twitchdropsminer.spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels.app = "twitchdropsminer";
        template = {
          metadata.labels.app = "twitchdropsminer";
          spec = {
            securityContext = {
              fsGroup = 568;
              fsGroupChangePolicy = "OnRootMismatch";
            };
            containers.twitchdropsminer = {
              # renovate: datasource=docker depName=dungfu/twitch-drops-miner
              image = "docker.io/dungfu/twitch-drops-miner:latest@sha256:2180ba72f7858a263071e5a42ac8446f26eaf1b938b5b933a6497136250d14e5";
              ports.http.containerPort = 5800;
              env = {
                DARK_MODE.value = "1";
                TZ.value = "Europe/Oslo";
              };
              securityContext = {
                runAsNonRoot = true;
                runAsUser = 568;
                runAsGroup = 568;
                allowPrivilegeEscalation = false;
              };
              volumeMounts = {
                "/TwitchDropsMiner/config".name = "config";
                "/TwitchDropsMiner/cache".name = "cache";
              };
            };
            volumes = {
              config.persistentVolumeClaim.claimName = "twitchdropsminer-config";
              cache.persistentVolumeClaim.claimName = "twitchdropsminer-cache";
            };
          };
        };
      };

      services.twitchdropsminer = {
        metadata.annotations = {
          "tailscale.com/proxy-group" = "ingress";
          "tailscale.com/hostname" = "twitchdropsminer";
        };
        spec = {
          type = "LoadBalancer";
          loadBalancerClass = "tailscale";
          selector.app = "twitchdropsminer";
          ports.http = {
            port = 80;
            targetPort = 5800;
          };
        };
      };
    };
  };
}
