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

        # Expose Traefik to the tailnet via Tailscale ProxyGroup (HA mode)
        service = {
          loadBalancerClass = "tailscale";
          annotations = {
            "tailscale.com/proxy-group" = "ingress";
            "tailscale.com/hostname" = "homelab";
          };
        };
      };
    };

    # Wildcard TLS certificate and Traefik default TLS store
    yamls = [
      ''
        apiVersion: cert-manager.io/v1
        kind: Certificate
        metadata:
          name: lab-teevik-no-wildcard
          namespace: traefik
        spec:
          secretName: lab-teevik-no-tls
          issuerRef:
            name: letsencrypt
            kind: ClusterIssuer
          dnsNames:
            - "lab.teevik.no"
            - "*.lab.teevik.no"
      ''
      ''
        apiVersion: traefik.io/v1alpha1
        kind: TLSStore
        metadata:
          name: default
          namespace: traefik
        spec:
          defaultCertificate:
            secretName: lab-teevik-no-tls
      ''
    ];
  };

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

  # cert-manager for TLS certificates
  applications.cert-manager = {
    namespace = "cert-manager";
    createNamespace = true;

    helm.releases.cert-manager = {
      chart = charts.jetstack.cert-manager;

      values = {
        crds.enabled = true;

        # Use public DNS for ACME DNS-01 propagation checks
        # (cluster DNS can't resolve _acme-challenge records)
        extraArgs = [
          "--dns01-recursive-nameservers-only"
          "--dns01-recursive-nameservers=1.1.1.1:53,8.8.8.8:53"
        ];
      };
    };

    # ClusterIssuer for Let's Encrypt via Cloudflare DNS-01 challenge
    yamls = [
      ''
        apiVersion: cert-manager.io/v1
        kind: ClusterIssuer
        metadata:
          name: letsencrypt
        spec:
          acme:
            email: teemuvikoren1@gmail.com
            server: https://acme-v02.api.letsencrypt.org/directory
            privateKeySecretRef:
              name: letsencrypt-account-key
            solvers:
              - dns01:
                  cloudflare:
                    apiTokenSecretRef:
                      name: cloudflare-api-token
                      key: api-token
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
          defaultReplicaCount = 3;
        };
      };
    };
  };

  # CoreDNS for lab.teevik.no resolution (used with Tailscale Split DNS)
  applications.coredns = {
    namespace = "coredns";
    createNamespace = true;

    resources = {
      configMaps.coredns.data."Corefile" = ''
        lab.teevik.no:53 {
          template IN A {
            answer "{{ .Name }} 60 IN A 100.103.158.180"
          }
          template IN AAAA {
            rcode NOERROR
          }
        }
      '';

      deployments.coredns.spec = {
        replicas = 2;
        selector.matchLabels.app = "coredns";
        template = {
          metadata.labels.app = "coredns";
          spec = {
            containers.coredns = {
              image = "coredns/coredns:1.12.0";
              args = [
                "-conf"
                "/etc/coredns/Corefile"
              ];
              ports."dns-udp" = {
                containerPort = 53;
                protocol = "UDP";
              };
              ports."dns-tcp" = {
                containerPort = 53;
                protocol = "TCP";
              };
              volumeMounts."/etc/coredns".name = "config";
            };
            volumes.config.configMap.name = "coredns";
          };
        };
      };

      services.coredns = {
        metadata.annotations = {
          "tailscale.com/expose" = "true";
          "tailscale.com/hostname" = "homelab-dns";
        };
        spec = {
          selector.app = "coredns";
          ports."dns-udp" = {
            port = 53;
            protocol = "UDP";
          };
          ports."dns-tcp" = {
            port = 53;
            protocol = "TCP";
          };
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

      ingresses.nginx.spec = {
        tls = [
          {
            hosts = [ "nginx.lab.teevik.no" ];
          }
        ];
        rules = [
          {
            host = "nginx.lab.teevik.no";
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
  };
}
