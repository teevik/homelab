{ ... }:
let
  glanceConfig = builtins.toJSON {
    pages = [
      # Home tab - News and content
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
                limit = 10;
                collapse-after = 3;
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
                type = "markets";
                markets = [
                  {
                    symbol = "KOG.OL";
                    name = "Kongsberg Gruppen";
                  }
                  {
                    symbol = "NVDA";
                    name = "NVIDIA";
                  }
                  {
                    symbol = "NVO";
                    name = "Novo Nordisk ADR";
                  }
                ];
              }

              {
                type = "releases";
                cache = "1d";
                repositories = [
                  "glanceapp/glance"
                  "k3s-io/k3s"
                  "NixOS/nixpkgs"
                ];
              }
            ];
          }
        ];
      }

      # Homelab tab - Service health and server stats
      {
        name = "Homelab";
        columns = [
          {
            size = "small";
            widgets = [
              {
                type = "monitor";
                title = "Service Health";
                cache = "1m";
                sites = [
                  {
                    title = "Glance";
                    url = "http://glance";
                    check-url = "http://glance.glance.svc";
                    icon = "si:glance";
                  }
                ];
              }
            ];
          }

          {
            size = "full";
            widgets = [
              {
                type = "server-stats";
                title = "Server";
                servers = [
                  {
                    type = "remote";
                    name = "homelab";
                    url = "http://homelab:27973";
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
