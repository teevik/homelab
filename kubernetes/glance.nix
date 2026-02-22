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

      # Homelab monitoring page - Enhanced with cluster info
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
                    url = "http://glance.glance.svc";
                    icon = "si:glance";
                  }
                  {
                    title = "Grafana";
                    url = "http://victoria-metrics-k8s-stack-grafana.monitoring.svc:80";
                    icon = "si:grafana";
                  }
                  {
                    title = "VictoriaMetrics";
                    url = "http://vmsingle-victoria-metrics-k8s-stack.monitoring.svc:8428";
                    icon = "si:victoriametrics";
                  }
                  {
                    title = "Alertmanager";
                    url = "http://vmalertmanager-victoria-metrics-k8s-stack.monitoring.svc:9093";
                    icon = "si:prometheus";
                  }
                  {
                    title = "VMAgent";
                    url = "http://vmagent-victoria-metrics-k8s-stack.monitoring.svc:8429";
                    icon = "si:victoriametrics";
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
                title = "Quick Links";
                groups = [
                  {
                    title = "Observability";
                    color = "30 80 50";
                    links = [
                      {
                        title = "Grafana";
                        url = "https://grafana";
                        icon = "si:grafana";
                      }
                      {
                        title = "Alertmanager";
                        url = "http://vmalertmanager-victoria-metrics-k8s-stack.monitoring.svc:9093";
                        icon = "si:prometheus";
                      }
                    ];
                  }
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

              {
                type = "server-stats";
                title = "Glance Server";
                servers = [
                  {
                    type = "local";
                    name = "Glance Pod";
                  }
                ];
              }
            ];
          }

          {
            size = "full";
            widgets = [
              {
                type = "split-column";
                widgets = [
                  {
                    type = "iframe";
                    title = "Node Overview";
                    source = "https://grafana/d/disk/kubernetes-views-nodes?orgId=1&refresh=5s&kiosk&theme=dark";
                    height = 350;
                  }
                  {
                    type = "iframe";
                    title = "Pod Status";
                    source = "https://grafana/d/k8s_views_pods/kubernetes-views-pods?orgId=1&refresh=5s&kiosk&theme=dark";
                    height = 350;
                  }
                ];
              }

              {
                type = "iframe";
                title = "VictoriaMetrics Health";
                source = "https://grafana/d/victoriametrics/victoriametrics?orgId=1&refresh=5s&kiosk&theme=dark";
                height = 280;
              }

              {
                type = "custom-api";
                title = "Active Alerts";
                cache = "1m";
                url = "http://vmalertmanager-victoria-metrics-k8s-stack.monitoring.svc:9093/api/v2/alerts?active=true&silenced=false&inhibited=false";
                template = ''
                  {{ $alerts := .JSON.Array "." }}
                  {{ if eq ($alerts | len) 0 }}
                    <div class="flex justify-center">
                      <span class="color-positive size-h3">No active alerts</span>
                    </div>
                  {{ else }}
                    <ul class="list list-gap-8">
                    {{ range $alerts }}
                      <li class="flex flex-col gap-4">
                        <div class="flex items-center gap-8">
                          <span class="color-negative size-h4">{{ .String "labels.alertname" }}</span>
                          <span class="size-h5 color-paragraph">{{ .String "labels.severity" }}</span>
                        </div>
                        <div class="size-h6 color-paragraph">{{ .String "annotations.summary" }}</div>
                      </li>
                    {{ end }}
                    </ul>
                  {{ end }}
                '';
              }
            ];
          }

          {
            size = "small";
            widgets = [
              {
                type = "custom-api";
                title = "Storage Overview";
                cache = "5m";
                url = "http://longhorn-backend.longhorn-system.svc:9500/v1/volumes";
                allow-insecure = true;
                template = ''
                  <div class="flex flex-col gap-10">
                    {{ $volumes := .JSON.Array "data" }}
                    {{ $healthy := 0 }}
                    {{ $total := len $volumes }}
                    {{ range $volumes }}
                      {{ if eq (.String "state") "attached" }}
                        {{ $healthy = add $healthy 1 }}
                      {{ end }}
                    {{ end }}
                    <div class="flex justify-between">
                      <span class="size-h6 color-paragraph">Volumes Healthy</span>
                      <span class="size-h4 {{ if eq $healthy $total }}color-positive{{ else }}color-negative{{ end }}">
                        {{ $healthy }} / {{ $total }}
                      </span>
                    </div>
                    <div class="flex justify-between">
                      <span class="size-h6 color-paragraph">Total Size</span>
                      <span class="size-h4 color-highlight">
                        {{ $size := 0 }}
                        {{ range $volumes }}
                          {{ $size = add $size (.Int "size") }}
                        {{ end }}
                        {{ div (toFloat $size) 1073741824 | printf "%.1f" }} GiB
                      </span>
                    </div>
                  </div>
                '';
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
