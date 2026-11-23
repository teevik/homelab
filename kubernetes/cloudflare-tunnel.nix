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
              image = "cloudflare/cloudflared:2026.11.2@sha256:55c7e3e8d89d5e8d20b75a82f3602cbf98e06db406e73e282073cfdc5a9a3af6";
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
