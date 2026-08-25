{ charts, ... }:
{
  # Target repository for generated manifests.
  nixidy.target.repository = "git@github.com:teevik/homelab.git";
  nixidy.target.branch = "main";
  nixidy.target.rootPath = "./manifests/homelab";

  # Local, versioned Helm charts are exposed to every application as `charts`.
  nixidy.chartsDir = ../charts;

  # ArgoCD auto-sync defaults: all applications auto-sync, prune, and self-heal
  nixidy.defaults.syncPolicy.autoSync = {
    enable = true;
    prune = true;
    selfHeal = true;
  };

  applications.tailscale-operator = {
    namespace = "tailscale";
    createNamespace = true;

    helm.releases.tailscale-operator = {
      chart = charts.tailscale.tailscale-operator;

      values = {
        operatorConfig = {
          hostname = "tailscale-operator-homelab";
        };
        apiServerProxyConfig = {
          mode = "true";
        };
        # Standalone Ingress/Service proxies pick up the metrics ProxyClass;
        # the ProxyGroup references it explicitly below.
        proxyConfig.defaultProxyClass = "metrics";
      };
    };

    yamls = [
      # Every proxy serves tailscaled metrics on <pod-ip>:9002/metrics
      ''
        apiVersion: tailscale.com/v1alpha1
        kind: ProxyClass
        metadata:
          name: metrics
        spec:
          metrics:
            enable: true
      ''
      # ProxyGroup for ingress proxies
      ''
        apiVersion: tailscale.com/v1alpha1
        kind: ProxyGroup
        metadata:
          name: ingress
        spec:
          type: ingress
          replicas: 1
          proxyClass: metrics
      ''
      # Scrape all operator-managed proxy pods by port number (the metrics
      # port is not a named container port)
      ''
        apiVersion: operator.victoriametrics.com/v1beta1
        kind: VMPodScrape
        metadata:
          name: tailscale-proxies
          namespace: tailscale
        spec:
          selector:
            matchLabels:
              tailscale.com/managed: "true"
          podMetricsEndpoints:
            - portNumber: 9002
              path: /metrics
      ''
    ];
  };
}
