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
            image = "ghcr.io/alam00000/bentopdf:2.6.0@sha256:96709a7ecd64a3fb4adf4dcf320808248a565993ea0c67febd25da12a34dcab7";
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
