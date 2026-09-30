{ ... }:
{
  applications.bentopdf = {
    namespace = "bentopdf";
    createNamespace = true;

    resources = {
      deployments.bentopdf.spec = {
        replicas = 1;
        selector.matchLabels.app = "bentopdf";
        template = {
          metadata.labels.app = "bentopdf";
          spec.containers.bentopdf = {
            # renovate: datasource=docker depName=ghcr.io/alam00000/bentopdf
            image = "ghcr.io/alam00000/bentopdf:2.8.8@sha256:6ef493c8e3bdbaa26c9bfcec330377ae95116fa00660ca0342769063197b1952";
            ports.http.containerPort = 8080;
          };
        };
      };

      services.bentopdf = {
        metadata.annotations = {
          "tailscale.com/proxy-group" = "ingress";
          "tailscale.com/hostname" = "bentopdf";
        };
        spec = {
          type = "LoadBalancer";
          loadBalancerClass = "tailscale";
          selector.app = "bentopdf";
          ports.http = {
            port = 80;
            targetPort = 8080;
          };
        };
      };
    };
  };
}
