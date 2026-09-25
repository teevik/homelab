{ ... }:
let
  widgets = import ./glance/widgets.nix;
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
                sites = [
                  {
                    title = "Glance";
                    url = "http://glance";
                    check-url = "http://glance.glance.svc";
                    icon = "si:glance";
                  }
                  {
                    title = "Longhorn";
                    url = "http://longhorn";
                    check-url = "http://longhorn-tailscale.longhorn-system.svc";
                    icon = "auto-invert https://raw.githubusercontent.com/cncf/artwork/main/projects/longhorn/icon/black/longhorn-icon-black.svg";
                  }
                  {
                    title = "Immich";
                    url = "http://immich";
                    check-url = "http://immich-tailscale.immich.svc";
                    icon = "si:immich";
                  }
                  {
                    title = "Grafana";
                    url = "http://grafana";
                    check-url = "http://grafana-tailscale.victoria-metrics.svc";
                    icon = "si:grafana";
                  }
                  {
                    title = "Nix Cache";
                    url = "http://grafana/d/nix-cache";
                    check-url = "http://192.168.1.225:8501/nix-cache-info";
                    icon = "si:nixos";
                  }
                  {
                    title = "ArgoCD";
                    url = "http://argocd";
                    check-url = "http://argocd-tailscale.argocd.svc";
                    icon = "si:argo";
                  }
                  {
                    title = "KodeKamp";
                    url = "https://kodekamp.teevik.no";
                    check-url = "http://kodekamp-web.kodekamp.svc:3000";
                    icon = "si:codewars";
                  }
                  {
                    title = "Paperless-ngx";
                    url = "http://paperless";
                    check-url = "http://paperless-tailscale.paperless-ngx.svc";
                    icon = "si:paperlessngx";
                  }
                  {
                    title = "BentoPDF";
                    url = "http://bentopdf";
                    check-url = "http://bentopdf.bentopdf.svc";
                    icon = "si:files";
                  }
                  {
                    title = "AMP";
                    url = "http://amp";
                    check-url = "http://amp.amp.svc";
                    icon = "mdi:gamepad-variant";
                  }
                  {
                    title = "TwitchDropsMiner";
                    url = "http://twitchdropsminer";
                    check-url = "http://twitchdropsminer.twitchdropsminer.svc";
                    icon = "si:twitch";
                  }
                  {
                    title = "ntfy";
                    url = "http://ntfy";
                    check-url = "http://ntfy.ntfy.svc";
                    icon = "si:ntfy";
                  }
                  {
                    title = "Immich Share";
                    url = "https://immich-share.tail84b6c.ts.net";
                    check-url = "http://immich-public-proxy.immich.svc:3000";
                    icon = "si:immich";
                  }
                  {
                    title = "Changedetection";
                    url = "http://changedetection";
                    check-url = "http://changedetection-tailscale.changedetection.svc";
                    icon = "di:changedetection-io";
                  }
                  {
                    title = "Registry";
                    url = "https://registry.tail84b6c.ts.net";
                    check-url = "http://zot.registry.svc:5000/v2/";
                    icon = "si:opencontainersinitiative";
                  }
                  {
                    title = "Reclip";
                    url = "http://reclip";
                    check-url = "http://reclip-tailscale.reclip.svc";
                    icon = "mdi:download";
                  }
                ];
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
              image = "glanceapp/glance:v0.8.6@sha256:9dfb09470b207dcb67ac715994bdb1929374ba3f9c0d7df7462c24adf10fd073";
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
