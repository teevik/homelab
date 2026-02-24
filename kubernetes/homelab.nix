{ charts, ... }:
{
  # Target repository for generated manifests.
  # Required by nixidy even when using 'nixidy apply' directly.
  nixidy.target.repository = "https://github.com/teevik/homelab.git";
  nixidy.target.branch = "main";
  nixidy.target.rootPath = "./manifests/homelab";

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
