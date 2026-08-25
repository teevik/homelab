{ charts, ... }:
{
  applications.longhorn = {
    namespace = "longhorn-system";
    createNamespace = true;

    helm.releases.longhorn = {
      chart = charts.longhorn.longhorn;

      values = {
        # Longhorn's pre-upgrade Helm job is unsupported under Argo CD.
        preUpgradeChecker.jobEnabled = false;

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
          # Auto-upgrade volume engines to the new default image (up to 3 at a time)
          # so instance-manager hotfixes and upgrades take effect without manual restarts
          concurrentAutomaticEngineUpgradePerNodeLimit = 3;
        };

        # S3 backup target (Hetzner Object Storage, hel1)
        defaultBackupStore = {
          backupTarget = "s3://homelab-longhorn-backup@hel1/";
          backupTargetCredentialSecret = "longhorn-backup-secret";
          pollInterval = "300";
        };

        # Single replica for UI on single-node
        longhornUI.replicas = 1;

        # Recurring jobs:
        #   - hourly-snapshot: local snapshot every hour, retain 24 (intra-day rollback)
        #   - daily-backup: S3 export daily at 02:00, retain 14 (off-site DR)
        # Volumes opt in via labels:
        #   recurring-job-group.longhorn.io/snapshot: "enabled"
        #   recurring-job-group.longhorn.io/backup:   "enabled"
        extraObjects = [
          {
            apiVersion = "longhorn.io/v1beta2";
            kind = "RecurringJob";
            metadata = {
              name = "hourly-snapshot";
              namespace = "longhorn-system";
            };
            spec = {
              cron = "0 * * * *";
              task = "snapshot";
              retain = 24;
              concurrency = 1;
              groups = [ "snapshot" ];
            };
          }
          {
            apiVersion = "longhorn.io/v1beta2";
            kind = "RecurringJob";
            metadata = {
              name = "daily-backup";
              namespace = "longhorn-system";
            };
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

    # Scrape longhorn-manager metrics (volume, node, and backup health).
    # Written as a VMServiceScrape directly: the ServiceMonitor CRD is not
    # installed, so the chart's metrics.serviceMonitor toggle cannot be used.
    yamls = [
      ''
        apiVersion: operator.victoriametrics.com/v1beta1
        kind: VMServiceScrape
        metadata:
          name: longhorn-manager
          namespace: longhorn-system
        spec:
          selector:
            matchLabels:
              app: longhorn-manager
          endpoints:
            - port: manager
      ''
    ];

    # Longhorn's own NetworkPolicy only admits Longhorn pods to longhorn-manager;
    # let vmagent in on the metrics port. Policies are additive.
    resources.networkPolicies.longhorn-manager-metrics.spec = {
      podSelector.matchLabels.app = "longhorn-manager";
      policyTypes = [ "Ingress" ];
      ingress = [
        {
          from = [
            {
              namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "victoria-metrics";
              podSelector.matchLabels."app.kubernetes.io/name" = "vmagent";
            }
          ];
          ports = [
            {
              port = 9500;
              protocol = "TCP";
            }
          ];
        }
      ];
    };

    # Longhorn dashboard (grafana.com/dashboards/13032), picked up by the
    # Grafana sidecar from any namespace via the grafana_dashboard label.
    resources.configMaps.longhorn-dashboard = {
      metadata.labels.grafana_dashboard = "1";
      metadata.annotations.grafana_folder = "Cluster";
      data."longhorn.json" = builtins.readFile ./dashboards/longhorn.json;
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
