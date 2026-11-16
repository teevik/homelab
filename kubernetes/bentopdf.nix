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
            image = "ghcr.io/alam00000/bentopdf:2.8.11@sha256:b107c37d9f1f27b7edae28d262e526d8e225541a7cc26005b84dbab42c904105";
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
