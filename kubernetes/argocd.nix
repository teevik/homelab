{ charts, ... }:
{
  applications.argocd = {
    namespace = "argocd";
    createNamespace = true;

    helm.releases.argocd = {
      chart = charts.argoproj.argo-cd;

      values = {
        # Single-node homelab: minimal HA, disable unused components
        dex.enabled = false;
        notifications.enabled = false;

        # TLS terminated by Tailscale, run insecure
        server.extraArgs = [ "--insecure" ];
      };
    };

    # Tailscale LoadBalancer to expose ArgoCD UI
    resources.services.argocd-tailscale = {
      metadata.annotations = {
        "tailscale.com/proxy-group" = "ingress";
        "tailscale.com/hostname" = "argocd";
      };
      spec = {
        type = "LoadBalancer";
        loadBalancerClass = "tailscale";
        selector = {
          "app.kubernetes.io/name" = "argocd-server";
          "app.kubernetes.io/instance" = "argocd";
        };
        ports.http = {
          port = 80;
          targetPort = 8080;
        };
      };
    };
  };
}
