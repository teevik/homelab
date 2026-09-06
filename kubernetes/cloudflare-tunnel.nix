{ ... }:
{
  applications.cloudflare-tunnel = {
    namespace = "cloudflare-tunnel";
    createNamespace = true;

    resources = {
      # Cloudflare Tunnel connector deployment
      # Routing rules are managed in the Cloudflare Zero Trust dashboard,
      # so this deployment only needs the tunnel token to connect.
      # To add new public services, add a route in the dashboard pointing
      # to the appropriate K8s service (e.g. http://service.namespace.svc:port).
      deployments.cloudflared.spec = {
        replicas = 1;
        selector.matchLabels.app = "cloudflared";
        template = {
          metadata.labels.app = "cloudflared";
          spec = {
            containers.cloudflared = {
              image = "cloudflare/cloudflared:2026.8.3@sha256:51c9cefcb4569df44e1ad403ab1d3d8065aa8e84339bcfc6aee75502e1140339";
              args = [
                "tunnel"
                "--no-autoupdate"
                "run"
              ];
              env = {
                TUNNEL_TOKEN.valueFrom.secretKeyRef = {
                  name = "cloudflare-tunnel-token";
                  key = "TUNNEL_TOKEN";
                };
              };
            };
          };
        };
      };
    };
  };
}
