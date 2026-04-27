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
            image = "ghcr.io/alam00000/bentopdf:2.8.4@sha256:f54b9ed9c56b767e0098b525468206689b666323c2b500b9686c3cf41cdfa348";
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
