{ charts, ... }:
{
  applications.monitoring = {
    namespace = "monitoring";
    createNamespace = true;

    helm.releases.victoria-metrics-k8s-stack = {
      chart = charts.victoriametrics.victoria-metrics-k8s-stack;

      # Filter out the node-exporter-full dashboard ConfigMap (too large for kubectl apply annotations)
      transformer = builtins.filter (
        obj:
        !(
          obj.kind == "ConfigMap"
          && (obj.metadata.name or "") == "victoria-metrics-k8s-stack-node-exporter-full"
        )
      );

      values = {
        # VictoriaMetrics single-node mode
        vmsingle = {
          enabled = true;
          spec = {
            retentionPeriod = "14d";
            replicaCount = 1;
            storage = {
              accessModes = [ "ReadWriteOnce" ];
              storageClassName = "longhorn";
              resources.requests.storage = "20Gi";
            };
          };
        };

        # Disable cluster mode (using single-node)
        vmcluster.enabled = false;

        # VMAgent for scraping metrics
        vmagent.enabled = true;

        # Alerting
        vmalert.enabled = true;
        alertmanager.enabled = true;

        # Node exporter for host-level metrics (CPU, memory, disk, network)
        prometheus-node-exporter.enabled = true;

        # Kubernetes object metrics (pods, deployments, nodes)
        kube-state-metrics.enabled = true;

        # Default dashboards and alerting rules
        defaultDashboards.enabled = true;
        defaultRules.create = true;

        # Grafana
        grafana = {
          enabled = true;
          adminPassword = "admin";
          persistence = {
            enabled = true;
            type = "pvc";
            storageClassName = "longhorn";
            size = "5Gi";
          };
          defaultDashboardsTimezone = "browser";
          # Enable anonymous access for iframe embedding
          env = {
            GF_AUTH_ANONYMOUS_ENABLED = "true";
            GF_AUTH_ANONYMOUS_ORG_ROLE = "Viewer";
            GF_SECURITY_ALLOW_EMBEDDING = "true";
            GF_SECURITY_COOKIE_SAMESITE = "none";
          };
        };

        # k3s uses kubelet on a different port and doesn't run kube-proxy/etcd/scheduler/controller-manager as separate pods
        kubeEtcd.enabled = false;
        kubeControllerManager.enabled = false;
        kubeScheduler.enabled = false;
        kubeProxy.enabled = false;

        # VictoriaMetrics operator
        victoria-metrics-operator = {
          enabled = true;
          crds = {
            plain = true;
            # Disable cleanup hook to avoid label length issues
            cleanup.enabled = false;
          };
        };

        # Disable the node-exporter-full dashboard (too large for ConfigMap annotations)
        defaultDashboards.node.nodeExporterFull = false;
      };
    };

    # Expose Grafana via Tailscale
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
          "app.kubernetes.io/instance" = "victoria-metrics-k8s-stack";
        };
        ports.http = {
          port = 80;
          targetPort = 3000;
        };
      };
    };
  };
}
