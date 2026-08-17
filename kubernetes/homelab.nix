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
      };
    };

    # ProxyGroup for ingress proxies
    yamls = [
      ''
        apiVersion: tailscale.com/v1alpha1
        kind: ProxyGroup
        metadata:
          name: ingress
        spec:
          type: ingress
          replicas: 1
      ''
    ];
  };
}
