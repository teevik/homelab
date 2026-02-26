{ charts, ... }:
{
  applications.longhorn = {
    namespace = "longhorn-system";
    createNamespace = true;

    helm.releases.longhorn = {
      chart = charts.longhorn.longhorn;

      values = {
        # Network policy type for k3s
        networkPolicies.type = "k3s";

        # StorageClass settings for single-node
        persistence = {
          defaultClass = true;
          defaultClassReplicaCount = 1;
          defaultDataLocality = "best-effort";
          defaultFsType = "ext4";
        };

        # System default settings
        defaultSettings = {
          defaultReplicaCount = 1;
          # Reserve 15% disk space as safety margin
          storageMinimalAvailablePercentage = 15;
          storageReservedPercentageForDefaultDisk = 15;
        };

        # S3 backup target (Hetzner Object Storage, hel1)
        defaultBackupStore = {
          backupTarget = "s3://homelab-longhorn-backup@hel1/";
          backupTargetCredentialSecret = "longhorn-backup-secret";
          pollInterval = "5m0s";
        };

        # Single replica for UI on single-node
        longhornUI.replicas = 1;

        # Daily backup to S3 — targets volumes labeled with the "backup" group
        extraObjects = [
          {
            apiVersion = "longhorn.io/v1beta2";
            kind = "RecurringJob";
            metadata.name = "daily-backup";
            spec = {
              cron = "0 2 * * *";
              task = "backup";
              retain = 14;
              concurrency = 1;
              groups = [ "backup" ];
            };
          }
        ];
      };
    };

    # Tailscale LoadBalancer to expose Longhorn UI
    resources.services.longhorn-tailscale = {
      metadata.annotations = {
        "tailscale.com/proxy-group" = "ingress";
        "tailscale.com/hostname" = "longhorn";
      };
      spec = {
        type = "LoadBalancer";
        loadBalancerClass = "tailscale";
        selector = {
          app = "longhorn-ui";
        };
        ports.http = {
          port = 80;
          targetPort = 8000;
        };
      };
    };
  };
}
