{ ... }:
{
  # Both cache processes live on the NixOS host, not in Kubernetes. Use its
  # reserved node address (hosts/homelab/configuration.nix), reachable over CNI.
  applications.victoria-metrics = {
    resources.configMaps.nix-cache-dashboard = {
      metadata.labels.grafana_dashboard = "1";
      metadata.annotations.grafana_folder = "Cluster";
      data."nix-cache.json" = builtins.readFile ./dashboards/nix-cache.json;
    };

    yamls = [
      ''
        apiVersion: operator.victoriametrics.com/v1beta1
        kind: VMStaticScrape
        metadata:
          name: nix-cache-harmonia
          namespace: victoria-metrics
        spec:
          jobName: nix-cache-harmonia
          targetEndpoints:
            - targets: ["192.168.1.225:8502"]
              path: /metrics
              interval: 30s
              scrapeTimeout: 10s
      ''
      ''
        apiVersion: operator.victoriametrics.com/v1beta1
        kind: VMStaticScrape
        metadata:
          name: nix-cache-ncps
          namespace: victoria-metrics
        spec:
          jobName: nix-cache-ncps
          targetEndpoints:
            - targets: ["192.168.1.225:8501"]
              path: /metrics
              interval: 30s
              scrapeTimeout: 10s
      ''
    ];
  };
}
