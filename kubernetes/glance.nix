{ ... }:
let
  widgets = import ./glance/widgets.nix;
  catalog = import ../catalog-lib.nix { };
  dashboardCSS = builtins.readFile ./glance/dashboard.css;
  glanceConfig = builtins.toJSON {
    server.assets-path = "/app/assets";
    theme.custom-css-file = "/assets/dashboard.css";
    pages = [
      {
        name = "Home";
        columns = [
          {
            size = "small";
            widgets = [
              {
                type = "monitor";
                title = "Applications";
                cache = "1m";
                sites = catalog.glance;
              }
            ];
          }
          {
            size = "full";
            widgets = [
              widgets.attention
              widgets.backups
              widgets.resources
            ];
          }
          {
            size = "small";
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
              {
                type = "weather";
                location = "Oslo, Norway";
                units = "metric";
                hour-format = "24h";
              }
              {
                type = "calendar";
                first-day-of-week = "monday";
              }
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
            ];
          }
        ];
      }
      {
        name = "Feeds";
        columns = [
          {
            size = "small";
            widgets = [
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
                  { url = "https://samwho.dev/rss.xml"; }
                  { url = "https://ciechanow.ski/atom.xml"; }
                  {
                    url = "https://www.joshwcomeau.com/rss.xml";
                    title = "Josh Comeau";
                  }
                ];
              }
              {
                type = "releases";
                cache = "1d";
                repositories = [
                  "glanceapp/glance"
                  "k3s-io/k3s"
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
        ];
      }
    ];
  };

  configHash = builtins.hashString "sha256" (glanceConfig + dashboardCSS);
in
{
  applications.glance = {
    namespace = "glance";
    createNamespace = true;

    resources = {
      configMaps.glance-config.data = {
        "glance.yml" = glanceConfig;
        "dashboard.css" = dashboardCSS;
      };

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
              image = "glanceapp/glance:v0.8.5@sha256:32ab73d80f2b8b5fb0735b0431deb36b93fbb6b2fb43592449b0178c8b83e350";
              ports.http.containerPort = 8080;
              volumeMounts."/app/assets/dashboard.css" = {
                name = "config";
                subPath = "dashboard.css";
              };
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
