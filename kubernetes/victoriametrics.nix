{ charts, ... }:
{
  applications.victoria-metrics = {
    namespace = "victoria-metrics";
    createNamespace = true;

    # Server-side apply avoids the 262144 byte annotation limit,
    # allowing large resources like the node-exporter-full dashboard.
    syncPolicy.syncOptions.serverSideApply = true;

    helm.releases.vm = {
      chart = charts.victoriametrics.victoria-metrics-k8s-stack;

      values = {
        # k3s bundles controller-manager, scheduler, and etcd into the main
        # k3s process — there are no separate pods to scrape, so disable these
        # to avoid KubeControllerManagerDown, KubeSchedulerDown,
        # ScrapePoolHasNoTargets, and RecordingRulesNoData alerts.
        kubeControllerManager.enabled = false;
        kubeScheduler.enabled = false;
        kubeEtcd.enabled = false;

        # Give vmagent enough CPU headroom to avoid CPUThrottlingHigh alerts
        vmagent.spec.resources = {
          requests = {
            cpu = "100m";
            memory = "200Mi";
          };
          limits = {
            cpu = "500m";
            memory = "500Mi";
          };
        };

        # Single-node VMSingle with Longhorn storage
        vmsingle.spec = {
          retentionPeriod = "3";
          storage = {
            storageClassName = "longhorn";
            accessModes = [ "ReadWriteOnce" ];
            resources.requests.storage = "20Gi";
          };
        };

        # Disable admission webhook to avoid TLS certs being regenerated on every build
        # (Helm's `lookup` function doesn't work with offline rendering)
        victoria-metrics-operator.admissionWebhooks.enabled = false;

        # Required for the victoriametrics-metrics-datasource type in Grafana
        grafana.plugins = [ "victoriametrics-metrics-datasource" ];

        grafana."grafana.ini".dashboards.default_home_dashboard_path =
          "/var/lib/grafana/dashboards/default/homelab-overview.json";

        # Persist Grafana's SQLite database so sessions and settings survive pod restarts
        grafana.persistence = {
          enabled = true;
          storageClassName = "longhorn";
          size = "1Gi";
        };

        grafana.adminPassword = "admin";
      };
    };

    # Custom homelab overview dashboard
    resources.configMaps.homelab-overview = {
      metadata.labels.grafana_dashboard = "1";
      data."homelab-overview.json" = builtins.readFile ./dashboards/homelab-overview.json;
    };

    # Tailscale LoadBalancer to expose Grafana
    resources.services.grafana-tailscale = {
      metadata.annotations = {
        "tailscale.com/proxy-group" = "ingress";
        "tailscale.com/hostname" = "grafana";
      };
      spec = {
        type = "LoadBalancer";
        loadBalancerClass = "tailscale";
        selector = {
          "app.kubernetes.io/name" = "grafana";
          "app.kubernetes.io/instance" = "vm";
        };
        ports.http = {
          port = 80;
          targetPort = 3000;
        };
      };
    };
  };
}
