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
              # renovate: datasource=docker depName=nokodo/twitchdropsminer
              image = "docker.io/nokodo/twitchdropsminer:latest@sha256:f10f0e97fe65c43cae842b33fa0557449b9b41c2a1bdfb37a7be52856fe45a9e";
              ports.http.containerPort = 5800;
              env = {
                DARK_MODE.value = "1";
                USER_ID.value = "568";
                GROUP_ID.value = "568";
                TZ.value = "Europe/Oslo";
              };
              securityContext = {
                runAsNonRoot = true;
                runAsUser = 568;
                runAsGroup = 568;
                allowPrivilegeEscalation = false;
              };
              volumeMounts = {
                "/config".name = "config";
                "/cache".name = "cache";
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
