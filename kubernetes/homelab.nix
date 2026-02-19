{ charts, ... }:
{
  # Target repository for generated manifests.
  # Required by nixidy even when using 'nixidy apply' directly.
  nixidy.target.repository = "https://github.com/teevik/homelab.git";
  nixidy.target.branch = "main";
  nixidy.target.rootPath = "./manifests/homelab";

  # Traefik ingress controller
  applications.traefik = {
    namespace = "traefik";
    createNamespace = true;

    helm.releases.traefik = {
      chart = charts.traefik.traefik;

      values = {
        ingressClass = {
          enabled = true;
          isDefaultClass = true;
        };

        # Expose Traefik to the tailnet via the Tailscale operator
        service.annotations = {
          "tailscale.com/expose" = "true";
          "tailscale.com/hostname" = "traefik";
        };
      };
    };
  };

  applications.tailscale-operator = {
    namespace = "tailscale";
    createNamespace = true;

    helm.releases.tailscale-operator = {
      chart = charts.tailscale.tailscale-operator;
    };
  };

  # MetalLB load balancer
  applications.metallb = {
    namespace = "metallb-system";
    createNamespace = true;

    helm.releases.metallb = {
      chart = charts.metallb.metallb;
    };

    # MetalLB CRDs for L2 advertisement
    yamls = [
      ''
        apiVersion: metallb.io/v1beta1
        kind: IPAddressPool
        metadata:
          name: default-pool
          namespace: metallb-system
        spec:
          addresses:
            - 192.168.1.240-192.168.1.250
      ''
      ''
        apiVersion: metallb.io/v1beta1
        kind: L2Advertisement
        metadata:
          name: default
          namespace: metallb-system
        spec:
          ipAddressPools:
            - default-pool
      ''
    ];
  };

  # Longhorn distributed storage
  applications.longhorn = {
    namespace = "longhorn-system";
    createNamespace = true;

    helm.releases.longhorn = {
      chart = charts.longhorn.longhorn;

      values = {
        defaultSettings = {
          # Single-node setup: only 1 replica needed
          # TODO: increase for 3 pc setup
          defaultReplicaCount = 1;
        };
      };
    };
  };

  # Example application: nginx
  # Remove or replace this with your actual workloads.
  applications.nginx = {
    namespace = "nginx";
    createNamespace = true;

    resources = {
      deployments.nginx.spec = {
        replicas = 1;
        selector.matchLabels.app = "nginx";
        template = {
          metadata.labels.app = "nginx";
          spec = {
            containers.nginx = {
              image = "nginx:latest";
              ports.http.containerPort = 80;
              volumeMounts."/usr/share/nginx/html".name = "html";
            };
            volumes.html.configMap.name = "nginx-html";
          };
        };
      };

      services.nginx.spec = {
        selector.app = "nginx";
        ports.http.port = 80;
      };

      configMaps.nginx-html.data."index.html" = ''
        <!DOCTYPE html>
        <html>
          <body>
            <h1>Hello from nixidy!</h1>
          </body>
        </html>
      '';

      ingresses.nginx.spec.rules = [
        {
          http.paths = [
            {
              path = "/";
              pathType = "Prefix";
              backend.service = {
                name = "nginx";
                port.number = 80;
              };
            }
          ];
        }
      ];
    };
  };
}
