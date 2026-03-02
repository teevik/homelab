{ charts, ... }:
{
  applications.argocd = {
    namespace = "argocd";
    createNamespace = true;

    # Server-side apply avoids the 262144 byte annotation limit,
    # allowing large CRDs like applicationsets.argoproj.io.
    syncPolicy.syncOptions.serverSideApply = true;

    helm.releases.argocd = {
      chart = charts.argoproj.argo-cd;

      values = {
        # Pin ArgoCD image version
        # renovate: datasource=docker depName=quay.io/argoproj/argocd
        global.image.tag = "v3.3.2";

        # Single-node homelab: minimal HA, disable unused components
        dex.enabled = false;
        notifications.enabled = false;

        # TLS terminated by Tailscale, run insecure
        server.extraArgs = [ "--insecure" ];

        # Set admin password to "admin"
        configs.secret.argocdServerAdminPassword = "$2y$10$8NrH8ICB2uhtEYl9kSDvROCto1D9Ayyi4Ivt48uXvQqshN7548jXq";
        configs.secret.extra."server.secretkey" = "fku6ze1N0fxMjQXbpMfPR8A9g0xHDW1UOwUgWvz6634=";
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
