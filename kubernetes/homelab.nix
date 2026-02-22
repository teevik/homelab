{ charts, ... }:
{
  # Target repository for generated manifests.
  # Required by nixidy even when using 'nixidy apply' directly.
  nixidy.target.repository = "https://github.com/teevik/homelab.git";
  nixidy.target.branch = "main";
  nixidy.target.rootPath = "./manifests/homelab";

  applications.tailscale-operator = {
    namespace = "tailscale";
    createNamespace = true;

    helm.releases.tailscale-operator = {
      chart = charts.tailscale.tailscale-operator;
    };

    # ProxyGroup for HA ingress proxies (one per node)
    yamls = [
      ''
        apiVersion: tailscale.com/v1alpha1
        kind: ProxyGroup
        metadata:
          name: ingress
        spec:
          type: ingress
          replicas: 3
      ''
    ];
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
        # Hotfix images for v1.11.0 regression issues
        # See: https://github.com/longhorn/longhorn/releases/tag/v1.11.0
        image = {
          longhorn.manager.repository = "longhornio/longhorn-manager";
          longhorn.manager.tag = "v1.11.0-hotfix-1";
          longhorn.instanceManager.repository = "longhornio/longhorn-instance-manager";
          longhorn.instanceManager.tag = "v1.11.0-hotfix-1";
        };

        # Disable version check to allow hotfix "downgrade"
        preUpgradeChecker = {
          upgradeVersionCheck = false;
        };

        defaultSettings = {
          defaultReplicaCount = 3;
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
        replicas = 3;
        selector.matchLabels.app = "nginx";
        template = {
          metadata.labels.app = "nginx";
          spec = {
            # Ensure nginx pods are evenly distributed across all nodes
            topologySpreadConstraints = [
              {
                maxSkew = 1;
                topologyKey = "kubernetes.io/hostname";
                whenUnsatisfiable = "ScheduleAnyway";
                labelSelector.matchLabels.app = "nginx";
              }
            ];
            initContainers.generate-html = {
              image = "busybox:latest";
              command = [
                "/bin/sh"
                "-c"
                ''echo "<!DOCTYPE html><html><body><h1>Hello from nixidy!</h1><p>Pod: $(hostname)</p></body></html>" > /html/index.html''
              ];
              volumeMounts."/html".name = "html";
            };
            containers.nginx = {
              image = "nginx:latest";
              ports.http.containerPort = 80;
              volumeMounts."/usr/share/nginx/html".name = "html";
            };
            volumes.html.emptyDir = { };
          };
        };
      };

      services.nginx = {
        metadata.annotations = {
          "tailscale.com/proxy-group" = "ingress";
          "tailscale.com/hostname" = "nginx";
        };
        spec = {
          type = "LoadBalancer";
          loadBalancerClass = "tailscale";
          selector.app = "nginx";
          ports.http.port = 80;
        };
      };
    };
  };
}
