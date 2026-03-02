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
        # node-exporter-full dashboard is too large for client-side apply
        # (annotations exceed the 262144 byte k8s limit)
        defaultDashboards.dashboards.node-exporter-full.enabled = false;

        # Single-node VMSingle with Longhorn storage
        vmsingle.spec = {
          retentionPeriod = "3";
          storage = {
            storageClassName = "longhorn";
            accessModes = [ "ReadWriteOnce" ];
            resources.requests.storage = "20Gi";
          };
        };

        # Required for the victoriametrics-metrics-datasource type in Grafana
        grafana.plugins = [ "victoriametrics-metrics-datasource" ];

        grafana.adminPassword = "admin";
      };
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
