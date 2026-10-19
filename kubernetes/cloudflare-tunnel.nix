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
              image = "cloudflare/cloudflared:2026.10.1@sha256:a15a3b50b8dabd57ac2090e9484c0247dba9dfa1f0df4d298d4317f9d69eb2d5";
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
