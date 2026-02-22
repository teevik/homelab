{ ... }:
let
  glanceConfig = builtins.toJSON {
    pages = [
      {
        name = "Home";
        columns = [
          {
            size = "small";
            widgets = [
              {
                type = "calendar";
                first-day-of-week = "monday";
              }

              {
                type = "weather";
                location = "Oslo, Norway";
                units = "metric";
                hour-format = "24h";
              }

              {
                type = "rss";
                title = "News & Blogs";
                limit = 15;
                collapse-after = 5;
                cache = "12h";
                feeds = [
                  {
                    url = "https://selfh.st/rss/";
                    title = "selfh.st";
                    limit = 4;
                  }
                  { url = "https://blog.syndtr.com/feed.xml"; }
                  { url = "https://samwho.dev/rss.xml"; }
                  { url = "https://ciechanow.ski/atom.xml"; }
                  {
                    url = "https://www.joshwcomeau.com/rss.xml";
                    title = "Josh Comeau";
                  }
                ];
              }
            ];
          }

          {
            size = "full";
            widgets = [
              {
                type = "group";
                widgets = [
                  { type = "hacker-news"; }
                  { type = "lobsters"; }
                ];
              }

              {
                type = "videos";
                channels = [
                  "UCR-DXc1voovS8nhAvccRZhg" # Jeff Geerling
                  "UCsBjURrPoezykLs9EqgamOA" # Fireship
                  "UCXuqSBlHAE6Xw-yeJA0Tunw" # Linus Tech Tips
                  "UCHnyfMqiRRG1u-2MsSQLbXA" # Veritasium
                ];
              }

              {
                type = "group";
                widgets = [
                  {
                    type = "reddit";
                    subreddit = "selfhosted";
                    show-thumbnails = true;
                  }
                  {
                    type = "reddit";
                    subreddit = "homelab";
                    show-thumbnails = true;
                  }
                ];
              }
            ];
          }

          {
            size = "small";
            widgets = [
              {
                type = "bookmarks";
                groups = [
                  {
                    title = "Homelab";
                    color = "10 70 50";
                    links = [
                      {
                        title = "Longhorn";
                        url = "https://longhorn.local";
                      }
                      {
                        title = "ArgoCD";
                        url = "https://argocd.local";
                      }
                    ];
                  }
                  {
                    title = "General";
                    color = "200 50 50";
                    links = [
                      {
                        title = "GitHub";
                        url = "https://github.com";
                      }
                      {
                        title = "Wikipedia";
                        url = "https://en.wikipedia.org";
                      }
                    ];
                  }
                ];
              }

              {
                type = "markets";
                markets = [
                  {
                    symbol = "SPY";
                    name = "S&P 500";
                  }
                  {
                    symbol = "BTC-USD";
                    name = "Bitcoin";
                  }
                  {
                    symbol = "ETH-USD";
                    name = "Ethereum";
                  }
                  {
                    symbol = "NVDA";
                    name = "NVIDIA";
                  }
                ];
              }

              {
                type = "releases";
                cache = "1d";
                repositories = [
                  "glanceapp/glance"
                  "longhorn/longhorn"
                  "k3s-io/k3s"
                  "NixOS/nixpkgs"
                ];
              }
            ];
          }
        ];
      }

      # Homelab monitoring page
      {
        name = "Homelab";
        columns = [
          {
            size = "small";
            widgets = [
              {
                type = "monitor";
                title = "Services";
                cache = "1m";
                sites = [
                  {
                    title = "Glance";
                    url = "http://glance.glance.svc:8080";
                    icon = "si:glance";
                  }
                  {
                    title = "Longhorn UI";
                    url = "http://longhorn-frontend.longhorn-system.svc:80";
                    icon = "si:longhorn";
                  }
                  {
                    title = "Nginx";
                    url = "http://nginx.nginx.svc:80";
                    icon = "si:nginx";
                  }
                ];
              }

              {
                type = "bookmarks";
                title = "Cluster Services";
                groups = [
                  {
                    title = "Infrastructure";
                    color = "10 70 50";
                    links = [
                      {
                        title = "Longhorn";
                        url = "https://longhorn.local";
                        icon = "si:longhorn";
                      }
                      {
                        title = "ArgoCD";
                        url = "https://argocd.local";
                        icon = "si:argo";
                      }
                    ];
                  }
                  {
                    title = "Networking";
                    color = "200 50 50";
                    links = [
                      {
                        title = "Tailscale";
                        url = "https://login.tailscale.com/admin/machines";
                        icon = "si:tailscale";
                      }
                    ];
                  }
                ];
              }
            ];
          }

          {
            size = "full";
            widgets = [
              {
                type = "repository";
                repository = "teevik/homelab";
                pull-requests-limit = 5;
                issues-limit = 5;
                commits-limit = 10;
              }

              {
                type = "group";
                widgets = [
                  {
                    type = "reddit";
                    subreddit = "selfhosted";
                    show-thumbnails = true;
                    collapse-after = 5;
                  }
                  {
                    type = "reddit";
                    subreddit = "homelab";
                    show-thumbnails = true;
                    collapse-after = 5;
                  }
                  {
                    type = "reddit";
                    subreddit = "kubernetes";
                    show-thumbnails = true;
                    collapse-after = 5;
                  }
                ];
              }
            ];
          }

          {
            size = "small";
            widgets = [
              {
                type = "releases";
                title = "Infrastructure Releases";
                cache = "1d";
                repositories = [
                  "k3s-io/k3s"
                  "longhorn/longhorn"
                  "argoproj/argo-cd"
                  "tailscale/tailscale"
                  "metallb/metallb"
                  "NixOS/nixpkgs"
                  "glanceapp/glance"
                ];
              }

              {
                type = "rss";
                title = "Homelab News";
                limit = 10;
                collapse-after = 5;
                cache = "12h";
                feeds = [
                  {
                    url = "https://selfh.st/rss/";
                    title = "selfh.st";
                  }
                  {
                    url = "https://kubernetes.io/feed.xml";
                    title = "Kubernetes Blog";
                  }
                  {
                    url = "https://www.talos.dev/blog/index.xml";
                    title = "Talos Blog";
                  }
                ];
              }
            ];
          }
        ];
      }
    ];
  };

  configHash = builtins.hashString "sha256" glanceConfig;
in
{
  applications.glance = {
    namespace = "glance";
    createNamespace = true;

    resources = {
      configMaps.glance-config.data."glance.yml" = glanceConfig;

      deployments.glance.spec = {
        replicas = 1;
        selector.matchLabels.app = "glance";
        template = {
          metadata = {
            labels.app = "glance";
            annotations."checksum/config" = configHash;
          };
          spec = {
            containers.glance = {
              image = "glanceapp/glance:latest";
              ports.http.containerPort = 8080;
              volumeMounts."/app/config/glance.yml" = {
                name = "config";
                subPath = "glance.yml";
              };
            };
            volumes.config.configMap.name = "glance-config";
          };
        };
      };

      services.glance = {
        metadata.annotations = {
          "tailscale.com/proxy-group" = "ingress";
          "tailscale.com/hostname" = "glance";
        };
        spec = {
          type = "LoadBalancer";
          loadBalancerClass = "tailscale";
          selector.app = "glance";
          ports.http = {
            port = 80;
            targetPort = 8080;
          };
        };
      };
    };
  };
}
