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
            image = "ghcr.io/alam00000/bentopdf:2.8.10@sha256:039239902a01e58a5a0f52e29039fafa18ffc2a481bb8acd807599f1c6dde7ef";
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
